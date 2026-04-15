#!/bin/bash

# ================================
# GIS FULL PIPELINE AUTOMATION
# ================================

# -------- INPUT --------
SOURCE_DIR="$1"

if [ -z "$SOURCE_DIR" ]; then
    echo "Usage: ./run_pipeline.sh <input_las_folder> [dtm_resolution]"
    exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Input folder not found!"
    exit 1
fi

# -------- RESOLUTION HANDLING --------
if [ -z "$2" ]; then
    DTM_RES=1.0
    echo "No DTM resolution provided. Using default: 1.0m"
else
    DTM_RES="$2"
    echo "Using user-defined DTM resolution: ${DTM_RES}m"
fi

# Validate resolution
if ! [[ "$DTM_RES" =~ ^[0-9]*\.?[0-9]+$ ]]; then
    echo "Invalid resolution value!"
    exit 1
fi

# -------- OUTPUT SETUP --------
OUTPUT_DIR="$SOURCE_DIR/results"

mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/ground"
mkdir -p "$OUTPUT_DIR/dtm"
mkdir -p "$OUTPUT_DIR/drainage"
mkdir -p "$OUTPUT_DIR/hotspot"

# -------- DEPENDENCIES --------
echo "Checking dependencies..."
command -v pdal >/dev/null || { echo "PDAL not found!"; exit 1; }
command -v python3 >/dev/null || { echo "Python3 not found!"; exit 1; }

echo "All dependencies OK"
echo "====================================="

# -------- PROGRESS BAR FUNCTION --------
progress_bar () {
    local current=$1
    local total=$2
    local width=30

    local progress=$((current * width / total))
    local remaining=$((width - progress))

    printf "["
    printf "%0.s#" $(seq 1 $progress)
    printf "%0.s-" $(seq 1 $remaining)
    printf "] %d/%d\r" "$current" "$total"
}

# =================================
# STEP 1: GROUND CLASSIFICATION
# =================================
echo "STEP 1/4: Ground Classification"

FILES=($(find "$SOURCE_DIR" -type f \( -iname "*.las" -o -iname "*.laz" \)))
TOTAL=${#FILES[@]}
COUNT=0

if [ "$TOTAL" -eq 0 ]; then
    echo "No LAS/LAZ files found!"
    exit 1
fi

for file in "${FILES[@]}"; do
    COUNT=$((COUNT+1))

    BASENAME=$(basename "$file")
    STEM="${BASENAME%.*}"
    OUT="$OUTPUT_DIR/ground/${STEM}_ground.las"

    TMP=$(mktemp /tmp/pdal_pipeline_XXXX.json)

    printf '{
      "pipeline":[
        {"type":"readers.las","filename":"%s"},
        {"type":"filters.csf"},
        {"type":"filters.range","limits":"Classification[2:2]"},
        {"type":"writers.las","filename":"%s"}
      ]
    }' "$file" "$OUT" > "$TMP"

    pdal pipeline "$TMP" >/dev/null 2>&1
    rm -f "$TMP"

    progress_bar $COUNT $TOTAL
done

echo -e "\nGround classification complete"
echo "====================================="

# =================================
# STEP 2: DTM GENERATION
# =================================
echo "STEP 2/4: DTM Generation"

FILES=($(find "$OUTPUT_DIR/ground" -iname "*_ground.las"))
TOTAL=${#FILES[@]}
COUNT=0

for file in "${FILES[@]}"; do
    COUNT=$((COUNT+1))

    BASENAME=$(basename "$file")
    STEM="${BASENAME%.*}"
    OUT="$OUTPUT_DIR/dtm/${STEM}_dtm.tif"

    TMP=$(mktemp /tmp/dtm_pipeline_XXXX.json)

    printf '{
      "pipeline":[
        {"type":"readers.las","filename":"%s"},
        {"type":"writers.gdal",
         "filename":"%s",
         "resolution":%s,
         "output_type":"idw"}
      ]
    }' "$file" "$OUT" "$DTM_RES" > "$TMP"

    pdal pipeline "$TMP" >/dev/null 2>&1
    rm -f "$TMP"

    progress_bar $COUNT $TOTAL
done

echo -e "\nDTM generation complete"
echo "====================================="

# =================================
# STEP 3: DRAINAGE NETWORK
# =================================
echo "STEP 3/4: Drainage Network"

FILES=($(find "$OUTPUT_DIR/dtm" -iname "*_dtm.tif"))
TOTAL=${#FILES[@]}
COUNT=0

for file in "${FILES[@]}"; do
    COUNT=$((COUNT+1))

    python3 drainage_network.py "$file" "$OUTPUT_DIR/drainage" >/dev/null 2>&1

    progress_bar $COUNT $TOTAL
done

echo -e "\nDrainage networks created"
echo "====================================="

# =================================
# STEP 4: WATER HOTSPOT
# =================================
echo "STEP 4/4: Water Hotspot Detection"

python3 water_hot_spot_gen.py "$OUTPUT_DIR/dtm" "$OUTPUT_DIR/hotspot"

echo "====================================="
echo "PIPELINE COMPLETED SUCCESSFULLY"

echo "Results saved in:"
echo "$OUTPUT_DIR"
