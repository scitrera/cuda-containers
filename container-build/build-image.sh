#!/bin/bash

set -euo pipefail

# Get script directory for finding recipes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECIPES_DIR="${SCRIPT_DIR}/../container-recipes"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <recipe>

Build a container image using a recipe file.

ARGUMENTS:
  recipe              Recipe name (without .recipe extension) or path to recipe file

OPTIONS:
  -h, --help          Show this help message
  -n, --dry-run       Show what would be built without building
  -l, --list          List available recipes
  --no-cache          Build without using cache

RECIPE FORMAT:
  Recipe files are simple key=value pairs (one per line, # for comments).

  Required variables:
    DOCKERFILE        Dockerfile to use (e.g., Dockerfile.base, Dockerfile.llm_inference)
    IMAGE_TAG         Output image tag (e.g., ghcr.io/scitrera/dgx-spark-vllm:0.13.0)

  Optional variables:
    TARGET            Docker build target stage (if not specified, builds default target)

  Build arg variables (passed as --build-arg):
    CUDA_VERSION, CUDA_SHORT, NCCL_VERSION, BUILD_JOBS,
    TORCH_CUDA_ARCH_LIST, NVCC_GENCODE,
    TORCH_VERSION, TORCH_AUDIO_VERSION, TORCH_VISION_VERSION,
    TORCH_REF, TORCH_AUDIO_REF, TORCH_VISION_REF,
    FLASHINFER_VERSION, TRANSFORMERS_VERSION, TRITON_VERSION,
    VLLM_VERSION, VLLM_REF, SGLANG_VERSION, SGLANG_REF,
    DEV_BASE_IMAGE, RUN_BASE_IMAGE, TRANSFORMERS_REF
    VLLM_REPO

EXAMPLES:
  $(basename "$0") vllm-0.13.0-t4           # Build using recipes/vllm-0.13.0-t4.recipe
  $(basename "$0") pytorch-test             # Build using recipes/pytorch-test.recipe
  $(basename "$0") ./my-custom.recipe       # Build using custom recipe file path
  $(basename "$0") -n vllm-0.13.0-t4        # Dry run - show config without building
  $(basename "$0") --list                   # List available recipes
EOF
}

list_recipes() {
    echo "Available recipes in ${RECIPES_DIR}:"
    echo ""
    if [[ -d "$RECIPES_DIR" ]]; then
        for recipe in "$RECIPES_DIR"/*.recipe; do
            if [[ -f "$recipe" ]]; then
                name=$(basename "$recipe" .recipe)
                # Extract IMAGE_TAG and DOCKERFILE from recipe for display
                image_tag=$(grep -E '^IMAGE_TAG=' "$recipe" 2>/dev/null | head -1 | cut -d= -f2- || echo "")
                dockerfile=$(grep -E '^DOCKERFILE=' "$recipe" 2>/dev/null | head -1 | cut -d= -f2- || echo "")
                printf "  %-25s" "$name"
                [[ -n "$dockerfile" ]] && printf " [%s]" "$dockerfile"
                [[ -n "$image_tag" ]] && printf " -> %s" "$image_tag"
                echo ""
            fi
        done
    else
        echo "  (recipes directory not found)"
    fi
}

# Known build arg variable names
KNOWN_BUILD_ARGS=(
    CUDA_VERSION CUDA_SHORT NCCL_VERSION BUILD_JOBS
    TORCH_CUDA_ARCH_LIST NVCC_GENCODE
    TORCH_VERSION TORCH_AUDIO_VERSION TORCH_VISION_VERSION
    TORCH_REF TORCH_AUDIO_REF TORCH_VISION_REF
    FLASHINFER_VERSION TRANSFORMERS_VERSION TRITON_VERSION
    VLLM_VERSION VLLM_REF SGLANG_VERSION SGLANG_REF
    DEV_BASE_IMAGE RUN_BASE_IMAGE TRANSFORMERS_REF
    VLLM_REPO
)

# Parse recipe file and populate variables
load_recipe() {
    local recipe_file="$1"

    if [[ ! -f "$recipe_file" ]]; then
        echo "Error: Recipe file not found: ${recipe_file}" >&2
        exit 1
    fi

    echo "Loading recipe: ${recipe_file}"
    echo ""

    # Reset recipe variables
    DOCKERFILE=""
    TARGET=""
    IMAGE_TAG=""
    declare -gA BUILD_ARG_VALUES=()

    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        case "$key" in
            DOCKERFILE)
                DOCKERFILE="$value"
                ;;
            TARGET)
                TARGET="$value"
                ;;
            IMAGE_TAG)
                IMAGE_TAG="$value"
                ;;
            *)
                # Check if it's a known build arg
                for known in "${KNOWN_BUILD_ARGS[@]}"; do
                    if [[ "$key" == "$known" ]]; then
                        BUILD_ARG_VALUES["$key"]="$value"
                        break
                    fi
                done
                ;;
        esac
    done < "$recipe_file"
}

# Options
DRY_RUN=false
NO_CACHE=false
RECIPE_ARG=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -l|--list)
            list_recipes
            exit 0
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            if [[ -n "$RECIPE_ARG" ]]; then
                echo "Error: Multiple recipes specified. Only one recipe allowed." >&2
                exit 1
            fi
            RECIPE_ARG="$1"
            shift
            ;;
    esac
done

# Check recipe was specified
if [[ -z "$RECIPE_ARG" ]]; then
    echo "Error: No recipe specified." >&2
    echo "" >&2
    usage >&2
    exit 1
fi

# Resolve recipe file path
if [[ -f "$RECIPE_ARG" ]]; then
    RECIPE_FILE="$RECIPE_ARG"
elif [[ -f "${RECIPES_DIR}/${RECIPE_ARG}.recipe" ]]; then
    RECIPE_FILE="${RECIPES_DIR}/${RECIPE_ARG}.recipe"
elif [[ -f "${RECIPES_DIR}/${RECIPE_ARG}" ]]; then
    RECIPE_FILE="${RECIPES_DIR}/${RECIPE_ARG}"
else
    echo "Error: Recipe not found: ${RECIPE_ARG}" >&2
    echo "       Looked in: ${RECIPE_ARG}, ${RECIPES_DIR}/${RECIPE_ARG}.recipe" >&2
    exit 1
fi

# Load the recipe
declare -A BUILD_ARG_VALUES
load_recipe "$RECIPE_FILE"

# Validate required variables
if [[ -z "$DOCKERFILE" ]]; then
    echo "Error: Recipe must specify DOCKERFILE" >&2
    exit 1
fi

if [[ -z "$IMAGE_TAG" ]]; then
    echo "Error: Recipe must specify IMAGE_TAG" >&2
    exit 1
fi

# Check Dockerfile exists
if [[ ! -f "${SCRIPT_DIR}/${DOCKERFILE}" ]]; then
    echo "Error: Dockerfile not found: ${SCRIPT_DIR}/${DOCKERFILE}" >&2
    exit 1
fi

# Collect version labels (all *_VERSION variables)
declare -A VERSION_LABELS=()
for key in "${!BUILD_ARG_VALUES[@]}"; do
    if [[ "$key" == *_VERSION ]]; then
        # Convert to lowercase label name: TORCH_VERSION -> org.scitrera.torch_version
        label_name="dev.scitrera.$(echo "$key" | tr '[:upper:]' '[:lower:]')"
        VERSION_LABELS["$label_name"]="${BUILD_ARG_VALUES[$key]}"
    fi
done

# Print configuration
echo "========================================"
echo "Build Configuration"
echo "========================================"
echo ""
echo "Dockerfile: ${DOCKERFILE}"
[[ -n "$TARGET" ]] && echo "Target:     ${TARGET}"
echo "Image Tag:  ${IMAGE_TAG}"
echo ""
if [[ ${#BUILD_ARG_VALUES[@]} -gt 0 ]]; then
    echo "Build Args:"
    for key in "${!BUILD_ARG_VALUES[@]}"; do
        echo "  ${key}=${BUILD_ARG_VALUES[$key]}"
    done | sort
    echo ""
fi
if [[ ${#VERSION_LABELS[@]} -gt 0 ]]; then
    echo "Image Labels:"
    for key in "${!VERSION_LABELS[@]}"; do
        echo "  ${key}=${VERSION_LABELS[$key]}"
    done | sort
    echo ""
fi
echo "========================================"
echo ""

if $DRY_RUN; then
    echo "[DRY RUN] Would build with above configuration."
    exit 0
fi

# Build the docker command
BUILD_CMD=(docker buildx build)

# Add --no-cache if requested
$NO_CACHE && BUILD_CMD+=(--no-cache)

# Add Dockerfile
BUILD_CMD+=(-f "${DOCKERFILE}")

# Add build args
for key in "${!BUILD_ARG_VALUES[@]}"; do
    BUILD_CMD+=(--build-arg "${key}=${BUILD_ARG_VALUES[$key]}")
done

# Add version labels
for key in "${!VERSION_LABELS[@]}"; do
    BUILD_CMD+=(--label "${key}=${VERSION_LABELS[$key]}")
done

# Add maintainer label
BUILD_CMD+=(--label "maintainer=scitrera.ai <open-source-team@scitrera.com>")

# Add target if specified
[[ -n "$TARGET" ]] && BUILD_CMD+=(--target "$TARGET")

# Add tag
BUILD_CMD+=(-t "$IMAGE_TAG")

# Add context
BUILD_CMD+=(.)

# Execute build
echo "=== Building ${IMAGE_TAG} ==="
cd "$SCRIPT_DIR"

"${BUILD_CMD[@]}"

echo ""
echo "=== Build complete ==="
echo "Image: ${IMAGE_TAG}"