import sys
import laspy
import numpy as np
import CSF
from pathlib import Path

# ---- Configuration ----
CHUNK_SIZE = 1_000_000  # points per read chunk (keep low for low RAM)
TILE_SIZE  = 500        # spatial tile size in map units (metres)
OVERLAP    = 10         # overlap between tiles to avoid edge artefacts

print("Script started!")

if len(sys.argv) < 2:
    print("Usage: python extract_points.py <input file>")
    sys.exit(1)

input_file = sys.argv[1]
input_path = Path(input_file)

if not input_path.exists():
    print(f"Error: File not found: {input_file}")
    sys.exit(1)

# ---- Step 1: Scan file to get XY bounds ----
print("Scanning file bounds...")
x_min = y_min =  np.inf
x_max = y_max = -np.inf

try:
    with laspy.open(input_file) as f:
        header = f.header
        total_points = int(header.point_count)
        print(f"Total points: {total_points}")
        for chunk in f.chunk_iterator(CHUNK_SIZE):
            # Use np.min/max on the scaled coordinates
            x_min = min(x_min, np.min(chunk.x))
            x_max = max(x_max, np.max(chunk.x))
            y_min = min(y_min, np.min(chunk.y))
            y_max = max(y_max, np.max(chunk.y))
except Exception as e:
    print(f"Error scanning file: {e}")
    sys.exit(1)

print(f"Bounds: X({x_min:.1f} - {x_max:.1f})  Y({y_min:.1f} - {y_max:.1f})")

# ---- Step 2: Build tile grid ----
x_tiles = int(np.ceil((x_max - x_min) / TILE_SIZE))
y_tiles = int(np.ceil((y_max - y_min) / TILE_SIZE))
total_tiles = x_tiles * y_tiles
print(f"Tile grid: {x_tiles} x {y_tiles} = {total_tiles} tiles  (tile size: {TILE_SIZE}m, overlap: {OVERLAP}m)")

# ---- Step 3: Output path ----
output_dir    = input_path.parent
stem          = input_path.stem
ground_output = output_dir / f"{stem}_ground.las"

# ---- Step 4: Process each tile ----
tile_num = 0
ground_points_total = 0

try:
    # Use the original header for the output to preserve coordinate precision (offsets/scales)
    with laspy.open(str(ground_output), mode='w', header=header) as writer:
        for xi in range(x_tiles):
            for yi in range(y_tiles):
                tile_num += 1

                # Tile bounds with overlap for CSF context
                tx_min = x_min + xi * TILE_SIZE - OVERLAP
                tx_max = x_min + (xi + 1) * TILE_SIZE + OVERLAP
                ty_min = y_min + yi * TILE_SIZE - OVERLAP
                ty_max = y_min + (yi + 1) * TILE_SIZE + OVERLAP

                print(f"[{tile_num}/{total_tiles}] Filtering tile area...", end="\r")

                # ---- Collect all points in this tile ----
                tile_chunks = []
                with laspy.open(input_file) as f:
                    for chunk in f.chunk_iterator(CHUNK_SIZE):
                        mask = (
                            (chunk.x >= tx_min) & (chunk.x < tx_max) &
                            (chunk.y >= ty_min) & (chunk.y < ty_max)
                        )
                        if np.any(mask):
                            # Slice the chunk to get a PointRecord
                            tile_chunks.append(chunk[mask])

                if not tile_chunks:
                    continue  

                # Merge list of PointRecords into one
                merged_points = laspy.merge_chunks(tile_chunks)
                del tile_chunks

                # Create temp LasData for processing
                tile_las = laspy.LasData(header)
                tile_las.points = merged_points

                print(f"[{tile_num}/{total_tiles}] Running CSF on {len(tile_las)} points...    ", end="\r")

                # ---- Build XYZ for CSF (Needs raw floats) ----
                xyz = np.vstack((
                    np.array(tile_las.x),
                    np.array(tile_las.y),
                    np.array(tile_las.z)
                )).T

                # ---- Run CSF ----
                csf = CSF.CSF()
                csf.params.cloth_resolution = 1.0
                csf.params.rigidness        = 3
                csf.params.threshold        = 0.5
                csf.params.bSlopeSmooth     = False
                csf.setPointCloud(xyz)

                ground = CSF.VecInt()
                non_ground = CSF.VecInt()
                csf.do_filtering(ground, non_ground)

                ground_indices = np.array(ground)

                if len(ground_indices) == 0:
                    del tile_las, merged_points, xyz
                    continue

                # ---- Strip overlap zone — keep only strict tile interior ----
                strict_x_min = x_min + xi * TILE_SIZE
                strict_x_max = x_min + (xi + 1) * TILE_SIZE
                strict_y_min = y_min + yi * TILE_SIZE
                strict_y_max = y_min + (yi + 1) * TILE_SIZE

                gx = xyz[ground_indices, 0]
                gy = xyz[ground_indices, 1]
                
                inside_mask = (
                    (gx >= strict_x_min) & (gx < strict_x_max) &
                    (gy >= strict_y_min) & (gy < strict_y_max)
                )
                
                final_indices = ground_indices[inside_mask]

                if len(final_indices) > 0:
                    # Write the ground points from this tile to the master file
                    writer.write_points(merged_points[final_indices])
                    ground_points_total += len(final_indices)

                print(f"[{tile_num}/{total_tiles}] Ground points so far: {ground_points_total}    ")

                # Clear memory for next tile
                del tile_las, merged_points, xyz, ground_indices

except MemoryError:
    print("\nError: Ran out of RAM. Try reducing TILE_SIZE.")
    sys.exit(1)
except Exception as e:
    print(f"\nError: {e}")
    sys.exit(1)

print(f"\nTotal ground points saved: {ground_points_total}")
print(f"Saved to: {ground_output}")
