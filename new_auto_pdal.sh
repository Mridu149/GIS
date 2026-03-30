#!/bin/bash
# ---- config ----
SOURCE_DIR="$1"

# ---- CHECK INPUT ----
if [ -z "$SOURCE_DIR" ]; then
    echo "Usage: ./auto_pdal.sh <source folder>"
    exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Source Folder not found!"
    exit 1
fi

if ! command -v pdal &> /dev/null; then
    echo "pdal is not installed."
    exit 1
fi

# ---- COUNT TOTAL FILES ----
TOTAL=$(find "$SOURCE_DIR" -type f \( -iname "*.laz" -o -iname "*.las" \) | wc -l | tr -d ' ')
CURRENT=0

echo "Found $TOTAL file(s) to process."
echo "--------------------------------"

# ---- MAIN LOOP ----
find "$SOURCE_DIR" -type f \( -iname "*.laz" -o -iname "*.las" \) > /tmp/pdal_filelist.txt

while IFS= read -r file; do
    CURRENT=$((CURRENT+1))

    # Derive output filename next to input file
    DIR=$(dirname "$file")
    BASENAME=$(basename "$file")
    STEM="${BASENAME%.*}"
    OUTPUT="$DIR/${STEM}_ground.las"

    echo "[$CURRENT/$TOTAL] Processing: $file"

    # Write a temporary pipeline JSON with chipper for memory-safe processing
    TMP_PIPELINE=$(mktemp /tmp/pdal_pipeline_XXXXXX.json)

    printf '{\n  "pipeline": [\n    {\n      "type": "readers.las",\n      "filename": "%s"\n    },\n    {\n      "type": "filters.chipper",\n      "capacity": 1000000\n    },\n    {\n      "type": "filters.csf",\n      "resolution": 1.0,\n      "rigidness": 3,\n      "threshold": 0.5,\n      "smooth": false\n    },\n    {\n      "type": "filters.range",\n      "limits": "Classification[2:2]"\n    },\n    {\n      "type": "writers.las",\n      "filename": "%s"\n    }\n  ]\n}\n' "$file" "$OUTPUT" > "$TMP_PIPELINE"

    pdal pipeline "$TMP_PIPELINE"

    if [ $? -eq 0 ]; then
        echo "[$CURRENT/$TOTAL] Success: $OUTPUT"
        # rm "$file"  # Original file deletion disabled — remove this comment to re-enable
    else
        echo "[$CURRENT/$TOTAL] Failed: $file"
        echo "Skipping Delete"
    fi

    rm -f "$TMP_PIPELINE"
    echo "------------------------------------"

done < /tmp/pdal_filelist.txt

rm -f /tmp/pdal_filelist.txt

echo "All files processed!"
