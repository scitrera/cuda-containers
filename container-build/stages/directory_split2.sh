#!/bin/bash
set -e

# This script splits a directory into N parts, approximately equal in size.
# Unlike directory_split.sh which works only at the top-level, this script goes
# one level deeper into top-level directories to achieve better balance.
#
# For each top-level entry:
#   - If it's a FILE: treated as an atomic unit (assigned whole to a bucket)
#   - If it's a DIRECTORY: its children are each treated as atomic units, allowing
#     the directory's contents to be spread across multiple buckets. The parent
#     directory structure is recreated in each bucket as needed.
#
# This prevents a single large top-level directory from dominating one bucket.
#
# Usage: ./directory_split2.sh <directory_path> <num_parts> [--exclude <pattern1> --exclude <pattern2> ...]
# Excludes apply to top-level entries only (same as directory_split.sh).
#
# Output: <parent>/<basename>-1, <parent>/<basename>-2, ..., <parent>/<basename>-N
# Deterministic: same inputs always produce the same split (sorted by name, greedy bin-packing).

EXCLUDES=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --exclude)
            EXCLUDES+=("$2")
            shift 2
            ;;
        *)
            if [ -z "$TARGET_DIR_RAW" ]; then
                TARGET_DIR_RAW="$1"
            elif [ -z "$NUM_PARTS_RAW" ]; then
                NUM_PARTS_RAW="$1"
            else
                echo "Unknown argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "$TARGET_DIR_RAW" ] || [ -z "$NUM_PARTS_RAW" ]; then
    echo "Usage: $0 <directory_path> <num_parts> [--exclude <pattern>]"
    exit 1
fi

TARGET_DIR=$(realpath "$TARGET_DIR_RAW")
NUM_PARTS="$NUM_PARTS_RAW"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory $TARGET_DIR does not exist."
    exit 1
fi

if [[ ! "$NUM_PARTS" =~ ^[0-9]+$ ]] || [ "$NUM_PARTS" -le 0 ]; then
    echo "Error: Number of parts must be a positive integer."
    exit 1
fi

PARENT_DIR=$(dirname "$TARGET_DIR")
BASE_NAME=$(basename "$TARGET_DIR")

echo "Splitting $TARGET_DIR into $NUM_PARTS parts (deep mode)..."

# Create destination directories
for i in $(seq 1 "$NUM_PARTS"); do
    mkdir -p "$PARENT_DIR/${BASE_NAME}-$i"
done

# Build find command for top-level entries (with exclusions)
FIND_CMD=(find "$TARGET_DIR" -maxdepth 1 -mindepth 1)
for pattern in "${EXCLUDES[@]}"; do
    FIND_CMD+=(-not -name "$pattern")
done

# Collect all work items as: <size_bytes>\t<relative_path_from_TARGET_DIR>
# For top-level files: the item itself
# For top-level directories: each child inside the directory
WORK_ITEMS=""

while IFS= read -r entry; do
    if [ -f "$entry" ]; then
        # Top-level file: treat as atomic
        SIZE=$(du -sb "$entry" | awk '{print $1}')
        REL_NAME=$(basename "$entry")
        WORK_ITEMS+="${SIZE}"$'\t'"${REL_NAME}"$'\n'
    elif [ -d "$entry" ]; then
        DIR_NAME=$(basename "$entry")
        # Check if directory has children
        CHILD_COUNT=$(find "$entry" -maxdepth 1 -mindepth 1 | wc -l)
        if [ "$CHILD_COUNT" -eq 0 ]; then
            # Empty directory: assign as zero-size item to preserve it
            WORK_ITEMS+="0"$'\t'"${DIR_NAME}/"$'\n'
        else
            # Go one level deeper: each child becomes a work item
            while IFS= read -r child; do
                SIZE=$(du -sb "$child" | awk '{print $1}')
                CHILD_NAME=$(basename "$child")
                WORK_ITEMS+="${SIZE}"$'\t'"${DIR_NAME}/${CHILD_NAME}"$'\n'
            done < <(find "$entry" -maxdepth 1 -mindepth 1 | sort)
        fi
    fi
done < <("${FIND_CMD[@]}" | sort)

# Remove trailing newline
WORK_ITEMS=$(echo -n "$WORK_ITEMS" | sed '/^$/d')

if [ -z "$WORK_ITEMS" ]; then
    echo "No items found to split."
    exit 0
fi

# Initialize bucket sizes
declare -a BUCKET_SIZES
for i in $(seq 1 "$NUM_PARTS"); do
    BUCKET_SIZES[$i]=0
done

# Sort items: descending by size, then ascending by name for deterministic tie-break
SORTED_ITEMS=$(echo "$WORK_ITEMS" | sort -t$'\t' -k1,1rn -k2,2)

# Greedily assign each item to the bucket with the smallest current size
IFS=$'\n'
for line in $SORTED_ITEMS; do
    SIZE=$(echo "$line" | cut -f1)
    REL_PATH=$(echo "$line" | cut -f2-)

    # Find the bucket with the minimum size (lowest index wins ties for determinism)
    MIN_BUCKET=1
    MIN_SIZE=${BUCKET_SIZES[1]}

    for i in $(seq 2 "$NUM_PARTS"); do
        if [ "${BUCKET_SIZES[$i]}" -lt "$MIN_SIZE" ]; then
            MIN_SIZE=${BUCKET_SIZES[$i]}
            MIN_BUCKET=$i
        fi
    done

    DEST_DIR="$PARENT_DIR/${BASE_NAME}-$MIN_BUCKET"
    SRC_PATH="$TARGET_DIR/$REL_PATH"

    # Check if this is a deep item (contains /)
    if [[ "$REL_PATH" == */* ]]; then
        # Ensure parent directory exists in the destination bucket
        ITEM_PARENT=$(dirname "$REL_PATH")
        mkdir -p "$DEST_DIR/$ITEM_PARENT"
    fi

    # Handle empty directory markers (trailing /)
    if [[ "$REL_PATH" == */ ]]; then
        # Strip trailing slash for the directory name
        DIR_PATH="${REL_PATH%/}"
        mkdir -p "$DEST_DIR/$DIR_PATH"
    else
        mv "$SRC_PATH" "$DEST_DIR/$REL_PATH"
    fi

    # Update bucket size
    BUCKET_SIZES[$MIN_BUCKET]=$((BUCKET_SIZES[$MIN_BUCKET] + SIZE))
done

# Clean up: remove now-empty directories from the source
# (top-level dirs whose children were all moved out)
find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -type d -empty -delete 2>/dev/null || true

echo "Split completed."
for i in $(seq 1 "$NUM_PARTS"); do
    SIZE_HUMAN=$(du -sh "$PARENT_DIR/${BASE_NAME}-$i" | cut -f1)
    echo "Bucket $i: $SIZE_HUMAN"
done
