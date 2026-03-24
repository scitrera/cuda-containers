#!/bin/bash
set -euo pipefail

# Local test build for Dockerfile.sglang-nightly
# Uses the real Dockerfile with the same build-args as CI.
#
# Usage:
#   ./test-sglang-nightly.sh                    # build runtime target
#   ./test-sglang-nightly.sh wheels             # build wheels target
#   SGLANG_REF=v0.5.9 ./test-sglang-nightly.sh # override ref
#   BUILD_JOBS=4 ./test-sglang-nightly.sh       # override parallelism

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_DIR="${SCRIPT_DIR}"

# Load parameters from file (env overrides take precedence)
PARAMS_FILE="${SCRIPT_DIR}/../container-recipes/sglang-nightly.parameters"
if [[ -f "$PARAMS_FILE" ]]; then
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        [[ -z "$key" ]] && continue
        if [[ -z "${!key:-}" ]]; then
            export "$key=$value"
        fi
    done < "$PARAMS_FILE"
fi

# Defaults
BASE_IMAGE="${BASE_IMAGE:-nvcr.io/nvidia/pytorch:26.02-py3}"
SGLANG_REF="${SGLANG_REF:-main}"
SGLANG_VERSION="${SGLANG_VERSION:-}"
BUILD_JOBS="${BUILD_JOBS:-2}"
CUDA_ARCHITECTURES="${CUDA_ARCHITECTURES:-121}"
TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-12.1a}"
NVCC_GENCODE="${NVCC_GENCODE:--gencode=arch=compute_121,code=sm_121}"
FLASHINFER_VERSION="${FLASHINFER_VERSION:-}"
TRANSFORMERS_VERSION="${TRANSFORMERS_VERSION:-}"
TRANSFORMERS_REF="${TRANSFORMERS_REF:-}"
TRANSFORMERS_PRE="${TRANSFORMERS_PRE:-0}"
TARGET="${1:-runtime}"

echo "=== SGLang Nightly Local Build ==="
echo "Base image:         ${BASE_IMAGE}"
echo "SGLang ref:         ${SGLANG_REF}"
echo "SGLang version:     ${SGLANG_VERSION:-<auto>}"
echo "Build jobs:         ${BUILD_JOBS}"
echo "CUDA arch:          ${TORCH_CUDA_ARCH_LIST}"
echo "FlashInfer version: ${FLASHINFER_VERSION:-<sglang default>}"
echo "Transformers:       ${TRANSFORMERS_VERSION:-<sglang default>}"
echo "Target:             ${TARGET}"
echo ""

docker buildx build \
    --file "${CONTEXT_DIR}/Dockerfile.sglang-nightly" \
    --target "${TARGET}" \
    --platform linux/arm64 \
    --progress plain \
    --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
    --build-arg "SGLANG_REF=${SGLANG_REF}" \
    --build-arg "SGLANG_VERSION=${SGLANG_VERSION}" \
    --build-arg "BUILD_JOBS=${BUILD_JOBS}" \
    --build-arg "CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES}" \
    --build-arg "TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST}" \
    --build-arg "NVCC_GENCODE=${NVCC_GENCODE}" \
    --build-arg "FLASHINFER_VERSION=${FLASHINFER_VERSION}" \
    --build-arg "TRANSFORMERS_VERSION=${TRANSFORMERS_VERSION}" \
    --build-arg "TRANSFORMERS_REF=${TRANSFORMERS_REF}" \
    --build-arg "TRANSFORMERS_PRE=${TRANSFORMERS_PRE}" \
    --tag "sglang-nightly-test:local" \
    "${CONTEXT_DIR}"
