#!/bin/bash
set -e

# This script splits a directory into N parts, approximately equal in size.
# It works at the top-level directory/file level to avoid splitting individual packages.
# Usage: ./directory_split.sh <directory_path> <num_parts> [--exclude <pattern1> --exclude <pattern2> ...]

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

echo "Splitting $TARGET_DIR into $NUM_PARTS parts..."

# Create destination directories
for i in $(seq 1 "$NUM_PARTS"); do
    mkdir -p "$PARENT_DIR/${BASE_NAME}-$i"
done

# Get list of top-level items with their sizes in bytes, sorted by name for determinism
# We use 'du -sb' to get size in bytes and 'find' to avoid issues with globbing hidden files
# or too many arguments.
# format: <size_in_bytes> <path>
FIND_CMD=(find "$TARGET_DIR" -maxdepth 1 -mindepth 1)
for pattern in "${EXCLUDES[@]}"; do
    FIND_CMD+=(-not -name "$pattern")
done
FIND_CMD+=(-exec du -sb {} +)

ITEMS=$("${FIND_CMD[@]}")

# Initialize buckets sizes
declare -a BUCKET_SIZES
for i in $(seq 1 "$NUM_PARTS"); do
    BUCKET_SIZES[$i]=0
done

# Greedily assign items to the bucket with the smallest current size
# This is a simple heuristic for the partition problem.
# Sorting by size descending, then by name for deterministic tie-break
IFS=$'\n'
SORTED_ITEMS=$(echo "$ITEMS" | sort -rn -k1,1 -k2,2)

for line in $SORTED_ITEMS; do
    SIZE=$(echo "$line" | awk '{print $1}')
    ITEM_PATH=$(echo "$line" | cut -f2-)
    ITEM_NAME=$(basename "$ITEM_PATH")

    # Find the bucket with the minimum size
    MIN_BUCKET=1
    MIN_SIZE=${BUCKET_SIZES[1]}
    
    for i in $(seq 2 "$NUM_PARTS"); do
        if [ "${BUCKET_SIZES[$i]}" -lt "$MIN_SIZE" ]; then
            MIN_SIZE=${BUCKET_SIZES[$i]}
            MIN_BUCKET=$i
        fi
    done
    
    # Move item to the selected bucket
    mv "$ITEM_PATH" "$PARENT_DIR/${BASE_NAME}-$MIN_BUCKET/"
    
    # Update bucket size
    BUCKET_SIZES[$MIN_BUCKET]=$((BUCKET_SIZES[$MIN_BUCKET] + SIZE))
done

echo "Split completed."
for i in $(seq 1 "$NUM_PARTS"); do
    SIZE_HUMAN=$(du -sh "$PARENT_DIR/${BASE_NAME}-$i" | cut -f1)
    echo "Bucket $i: $SIZE_HUMAN"
done
