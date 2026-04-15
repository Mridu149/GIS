# GIS Processing Pipeline: Ground Classification, DTM Generation, Drainage Network & Water Hotspot Detection

## Overview

This project implements an automated GIS pipeline for processing LiDAR data. It takes raw LAS/LAZ files as input and performs the following operations:

- Ground point classification  
- Digital Terrain Model (DTM) generation  
- Drainage network extraction  
- Water hotspot detection using machine learning  

The entire workflow is automated using a Bash script (`GIScript.sh`), allowing batch processing of multiple datasets with minimal manual intervention.

---

## Pipeline Workflow

Input LAS/LAZ  
↓  
Ground Classification (PDAL)  
↓  
DTM Generation (PDAL)  
↓  
Drainage Network Extraction (WhiteboxTools)  
↓  
Water Hotspot Detection (Random Forest)  
↓  
Final Outputs  

---

## Project Structure

project/  
├── GIScript.sh  
├── auto_pdal.sh  
├── auto_dtm.sh  
├── drainage_network.py  
├── water_hot_spot_gen.py  
└── results/  
&nbsp;&nbsp;&nbsp;&nbsp;├── ground/  
&nbsp;&nbsp;&nbsp;&nbsp;├── dtm/  
&nbsp;&nbsp;&nbsp;&nbsp;├── drainage/  
&nbsp;&nbsp;&nbsp;&nbsp;└── hotspot/  

---

## Requirements

### System Dependencies

- PDAL  
- Python 3  
- WhiteboxTools  

### Python Libraries

Install required Python packages using:

pip install numpy rasterio scikit-learn scipy matplotlib joblib

---

## Usage

### Make the script executable

chmod +x GIScript.sh

### Run the pipeline

Default DTM resolution (1.0 meter):

./GIScript.sh <input_folder>

Custom DTM resolution:

./GIScript.sh <input_folder> <resolution>

Example:

./GIScript.sh ./data 0.5

---

## Input

- A directory containing `.las` or `.laz` LiDAR files  

### Important

The script automatically scans the provided directory **recursively**, meaning:

- It detects `.las` and `.laz` files inside the main folder  
- It also detects files inside all subdirectories  
- No need to manually organize files into a single folder  

Example:

data/  
├── area1/  
│   ├── file1.las  
│   └── file2.laz  
├── area2/  
│   └── subarea/  
│       └── file3.las  

All files will be processed automatically.

---

## Output

All results are stored inside:

results/

### Output Breakdown

- ground/ → Ground-classified LAS files  
- dtm/ → Generated DTM files (.tif)  
- drainage/ → Extracted drainage network (.shp)  
- hotspot/ → Water hotspot maps (.tif and .png)  

---

## Water Hotspot Detection

The hotspot detection module uses a Random Forest classifier trained on terrain-derived features.

### Features Used

- Elevation  
- Slope  
- Curvature  
- Roughness  
- Flow proxy  
- Topographic Wetness Index (TWI)  
- Depression  

The model outputs a probability map indicating areas prone to water accumulation.

---

## Features

- Fully automated end-to-end pipeline  
- Recursive file discovery (supports nested directories)  
- Modular design (each step is independent)  
- Supports batch processing of multiple files  
- Progress tracking via terminal  
- Clean separation of input and output data  
- Machine learning-based analysis  

---

## Notes

- Ensure PDAL and WhiteboxTools are properly installed and added to PATH  
- Large datasets may take significant processing time  
- The drainage extraction threshold may need adjustment depending on terrain  

---

## Future Improvements

- Parallel processing for faster execution  
- CLI-based argument parsing with flags  
- Interactive visualization or web interface  
- Improved model tuning and validation  

---

## Author

Mridupawan Kashyap  

---

## License

This project is intended for academic and educational use.
