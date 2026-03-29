#!/bin/bash
# ---- CONFIG ----
SOURCE_DIR="$1"
PYTHON_SCRIPT="extract_points.py"

# ---- CHECK INPUT ----
if [ -z "$SOURCE_DIR" ]; then
    echo "Usage: ./run_pipeline.sh <source_folder>"
    exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Source folder not found!"
    exit 1
fi

# ---- COUNT TOTAL FILES ----
TOTAL=$(find "$SOURCE_DIR" -not -path '*/.*' -type f \( -iname "*.laz" \) | wc -l)
CURRENT=0

echo "Found $TOTAL file(s) to process."
echo "-----------------------------"

# ---- MAIN LOOP ----
find "$SOURCE_DIR" -not -path '*/.*' -type f \( -iname "*.laz" \) | while read -r file
do
    CURRENT=$((CURRENT + 1))
    echo "[$CURRENT/$TOTAL] Processing: $file"

    python "$PYTHON_SCRIPT" "$file"

    if [ $? -eq 0 ]; then
        echo "[$CURRENT/$TOTAL] Success: $file"
        rm "$file"
    else
        echo "[$CURRENT/$TOTAL] Failed: $file (skipping delete)"
    fi

    echo "-----------------------------"
done

echo "All files processed!"
