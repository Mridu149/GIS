#!/bin/bash
# ---- Process large LAZ file by cropping into 3 Y-axis tiles ----
# Bounding box: X 473186.8455-479385.7063, Y 1361077.703-1367579.77

INPUT_FILE="$1"

if [ -z "$INPUT_FILE" ]; then
    echo "Usage: ./process_large.sh <input.laz>"
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "File not found: $INPUT_FILE"
    exit 1
fi

if ! command -v pdal &> /dev/null; then
    echo "pdal is not installed."
    exit 1
fi

DIR=$(dirname "$INPUT_FILE")
STEM=$(basename "$INPUT_FILE" | sed 's/\.[^.]*$//')
GROUND_DIR="$DIR/${STEM}_ground_tiles"
FINAL_OUTPUT="$DIR/${STEM}_ground.las"

mkdir -p "$GROUND_DIR"

# Tile bounds (split Y into 3 equal parts, full X extent)
MINX=473186.8455
MAXX=479385.7063
MINY1=1361077.703;  MAXY1=1363244.369
MINY2=1363244.369;  MAXY2=1365411.036
MINY3=1365411.036;  MAXY3=1367579.770

declare -a MINS_Y=($MINY1 $MINY2 $MINY3)
declare -a MAXS_Y=($MAXY1 $MAXY2 $MAXY3)

TOTAL=3
echo "Processing $INPUT_FILE in $TOTAL tiles..."
echo "------------------------------------"

for i in 1 2 3; do
    IDX=$((i-1))
    MINY=${MINS_Y[$IDX]}
    MAXY=${MAXS_Y[$IDX]}
    OUTPUT="$GROUND_DIR/${STEM}_tile${i}_ground.las"

    echo "[$i/$TOTAL] Tile $i — Y: $MINY to $MAXY"

    TMP_PIPELINE=$(mktemp /tmp/pdal_pipeline_XXXXXX.json)
    printf '{\n  "pipeline": [\n    {\n      "type": "readers.las",\n      "filename": "%s"\n    },\n    {\n      "type": "filters.crop",\n      "bounds": "([%s, %s], [%s, %s])"\n    },\n    {\n      "type": "filters.csf",\n      "resolution": 1.0,\n      "rigidness": 3,\n      "threshold": 0.5,\n      "smooth": false\n    },\n    {\n      "type": "filters.range",\n      "limits": "Classification[2:2]"\n    },\n    {\n      "type": "writers.las",\n      "filename": "%s"\n    }\n  ]\n}\n' \
        "$INPUT_FILE" "$MINX" "$MAXX" "$MINY" "$MAXY" "$OUTPUT" > "$TMP_PIPELINE"

    pdal pipeline "$TMP_PIPELINE"

    if [ $? -eq 0 ]; then
        echo "[$i/$TOTAL] Tile $i success: $OUTPUT"
    else
        echo "[$i/$TOTAL] Tile $i FAILED"
    fi

    rm -f "$TMP_PIPELINE"
    echo "------------------------------------"
done

# ---- MERGE ----
echo "Merging tiles into $FINAL_OUTPUT..."

TILE1="$GROUND_DIR/${STEM}_tile1_ground.las"
TILE2="$GROUND_DIR/${STEM}_tile2_ground.las"
TILE3="$GROUND_DIR/${STEM}_tile3_ground.las"

TMP_MERGE=$(mktemp /tmp/pdal_merge_XXXXXX.json)
printf '{\n  "pipeline": [\n    {"type": "readers.las", "filename": "%s"},\n    {"type": "readers.las", "filename": "%s"},\n    {"type": "readers.las", "filename": "%s"},\n    {"type": "filters.merge"},\n    {"type": "writers.las", "filename": "%s"}\n  ]\n}\n' \
    "$TILE1" "$TILE2" "$TILE3" "$FINAL_OUTPUT" > "$TMP_MERGE"

pdal pipeline "$TMP_MERGE"
rm -f "$TMP_MERGE"

if [ $? -eq 0 ]; then
    echo "Merge successful: $FINAL_OUTPUT"
    echo "Cleaning up tiles..."
    rm -rf "$GROUND_DIR"
else
    echo "Merge failed. Tiles preserved in: $GROUND_DIR"
fi

echo "Done!"
