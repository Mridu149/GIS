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
TOTAL=$(find "$SOURCE_DIR" -not -path '*/.*' -type f \( -iname "*.laz" -o -iname "*.las" \) | wc -l)
CURRENT=0

echo "Found $TOTAL file(s) to process."
echo "--------------------------------"

# ---- MAIN LOOP ----
while IFS= read -r file; do
	CURRENT=$((CURRENT+1))

	#Derive output filename next to input file
	DIR=$(dirname "$file")
	BASENAME=$(basename "$file")
	STEM="${BASENAME%.*}"
	OUTPUT="$DIR/${STEM}_ground.las"

	echo "[$CURRENT/$TOTAL] Processing: $file"
	
	#write a temporary pipeline JSON with actual file paths baked in
	TMP_PIPELINE=$(mktemp /tmp/pdal_pipeline_XXXXXX.json)
	cat > "$TMP_PIPELINE" << JSON
{
	"pipeline": [
	{
		"type": "readers.las",
		"filename": "$file"
	},
	{
		"type": "filters.csf",
		"resolution": 1.0,
		"rigidness": 3,
		"threshold": 0.5,
		"smooth": false
	},
	{	"type": "filters.range",
		"limits": "Classification[2:2]"
	},
	{
		"type": "writers.las",
		"filename": "$OUTPUT"
	}
	]
}
JSON

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
done < <(find "$SOURCE_DIR" -not -path '*/.*' -type f \( -iname "*.laz" -o -iname "*.las" \))

echo "All files processed!"
