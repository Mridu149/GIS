#!/bin/bash
# ---- config ----
SOURCE_DIR="$1"
RESOLUTION="${2:-1.0}"   # Default 1m resolution, override with 2nd argument

# ---- CHECK INPUT ----
if [ -z "$SOURCE_DIR" ]; then
    echo "Usage: ./auto_dtm.sh <source folder> [resolution in meters]"
    echo "Example: ./auto_dtm.sh ./output 0.5"
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
TOTAL=$(find "$SOURCE_DIR" -type f -iname "*_ground.las" | wc -l | tr -d ' ')
CURRENT=0

echo "Found $TOTAL ground file(s) to process."
echo "Resolution: ${RESOLUTION}m"
echo "--------------------------------"

# ---- MAIN LOOP ----
find "$SOURCE_DIR" -type f -iname "*_ground.las" > /tmp/dtm_filelist.txt

while IFS= read -r file; do
    CURRENT=$((CURRENT+1))

    DIR=$(dirname "$file")
    BASENAME=$(basename "$file")
    STEM="${BASENAME%.*}"
    OUTPUT="$DIR/${STEM}_dtm.tif"

    echo "[$CURRENT/$TOTAL] Processing: $file"

    TMP_PIPELINE=$(mktemp /tmp/dtm_pipeline_XXXXXX.json)

    printf '{
  "pipeline": [
    {
      "type": "readers.las",
      "filename": "%s"
    },
    {
      "type": "writers.gdal",
      "filename": "%s",
      "resolution": %s,
      "output_type": "idw",
      "gdalopts": "COMPRESS=LZW",
      "data_type": "float32",
      "nodata": -9999
    }
  ]
}\n' "$file" "$OUTPUT" "$RESOLUTION" > "$TMP_PIPELINE"

    pdal pipeline "$TMP_PIPELINE"

    if [ $? -eq 0 ]; then
        echo "[$CURRENT/$TOTAL] Success: $OUTPUT"
    else
        echo "[$CURRENT/$TOTAL] Failed: $file"
    fi

    rm -f "$TMP_PIPELINE"
    echo "------------------------------------"

done < /tmp/dtm_filelist.txt

rm -f /tmp/dtm_filelist.txt

echo "All DTMs generated!"
