#!/bin/bash
# ---- Split a large LAS/LAZ file into chunks, run CSF on each, then merge ----
INPUT_FILE="$1"

# ---- CHECK INPUT ----
if [ -z "$INPUT_FILE" ]; then
    echo "Usage: ./split_and_process.sh <input file>"
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
BASENAME=$(basename "$INPUT_FILE")
STEM="${BASENAME%.*}"

CHUNKS_DIR="$DIR/${STEM}_chunks"
GROUND_DIR="$DIR/${STEM}_ground_chunks"
FINAL_OUTPUT="$DIR/${STEM}_ground.las"

mkdir -p "$CHUNKS_DIR"
mkdir -p "$GROUND_DIR"

# ---- STEP 1: SPLIT ----
# length=200 targets ~50M points per tile to keep RAM under ~8GB per CSF run
# Adjust lower (e.g. 100) if CSF still runs out of memory
echo "Step 1: Splitting $INPUT_FILE into 200m x 200m chunks..."

TMP_SPLIT=$(mktemp /tmp/pdal_split_XXXXXX.json)
printf '{\n  "pipeline": [\n    {\n      "type": "readers.las",\n      "filename": "%s"\n    },\n    {\n      "type": "filters.splitter",\n      "length": 200\n    },\n    {\n      "type": "writers.las",\n      "filename": "%s/chunk_#.las"\n    }\n  ]\n}\n' "$INPUT_FILE" "$CHUNKS_DIR" > "$TMP_SPLIT"

pdal pipeline "$TMP_SPLIT"
rm -f "$TMP_SPLIT"

if [ $? -ne 0 ]; then
    echo "Splitting failed. Aborting."
    exit 1
fi

CHUNK_TOTAL=$(find "$CHUNKS_DIR" -type f -iname "*.las" | wc -l | tr -d ' ')
echo "Split into $CHUNK_TOTAL chunks."
echo "------------------------------------"

# ---- STEP 2: CSF ON EACH CHUNK, DELETE CHUNK AFTER TO SAVE DISK ----
echo "Step 2: Running CSF ground filter on each chunk..."
CHUNK_CURRENT=0

find "$CHUNKS_DIR" -type f -iname "*.las" > /tmp/pdal_chunklist.txt

while IFS= read -r chunk; do
    CHUNK_CURRENT=$((CHUNK_CURRENT+1))
    CHUNK_BASENAME=$(basename "$chunk")
    CHUNK_STEM="${CHUNK_BASENAME%.*}"
    CHUNK_OUTPUT="$GROUND_DIR/${CHUNK_STEM}_ground.las"

    echo "[$CHUNK_CURRENT/$CHUNK_TOTAL] Processing chunk: $chunk"

    TMP_PIPELINE=$(mktemp /tmp/pdal_pipeline_XXXXXX.json)
    printf '{\n  "pipeline": [\n    {\n      "type": "readers.las",\n      "filename": "%s"\n    },\n    {\n      "type": "filters.csf",\n      "resolution": 1.0,\n      "rigidness": 3,\n      "threshold": 0.5,\n      "smooth": false\n    },\n    {\n      "type": "filters.range",\n      "limits": "Classification[2:2]"\n    },\n    {\n      "type": "writers.las",\n      "filename": "%s"\n    }\n  ]\n}\n' "$chunk" "$CHUNK_OUTPUT" > "$TMP_PIPELINE"

    pdal pipeline "$TMP_PIPELINE"

    if [ $? -eq 0 ]; then
        echo "[$CHUNK_CURRENT/$CHUNK_TOTAL] Chunk success: $CHUNK_OUTPUT"
        # Delete processed chunk immediately to free disk space
        rm -f "$chunk"
    else
        echo "[$CHUNK_CURRENT/$CHUNK_TOTAL] Chunk failed: $chunk"
        echo "Chunk preserved for inspection."
    fi

    rm -f "$TMP_PIPELINE"
    echo "------------------------------------"

done < /tmp/pdal_chunklist.txt
rm -f /tmp/pdal_chunklist.txt

# ---- STEP 3: MERGE ----
echo "Step 3: Merging ground chunks into $FINAL_OUTPUT..."

GROUND_FILES=$(find "$GROUND_DIR" -type f -iname "*.las" | tr '\n' ' ')

TMP_MERGE=$(mktemp /tmp/pdal_merge_XXXXXX.json)

READERS=""
for f in $GROUND_FILES; do
    READERS="$READERS    {\"type\": \"readers.las\", \"filename\": \"$f\"},"
done
READERS="${READERS%,}"

printf '{\n  "pipeline": [\n%s,\n    {"type": "filters.merge"},\n    {"type": "writers.las", "filename": "%s"}\n  ]\n}\n' "$READERS" "$FINAL_OUTPUT" > "$TMP_MERGE"

pdal pipeline "$TMP_MERGE"
rm -f "$TMP_MERGE"

if [ $? -eq 0 ]; then
    echo "Merge successful: $FINAL_OUTPUT"
    echo "Cleaning up ground chunks..."
    rm -rf "$GROUND_DIR"
    rmdir "$CHUNKS_DIR" 2>/dev/null
else
    echo "Merge failed. Ground chunks preserved in: $GROUND_DIR"
fi

echo "Done!"
