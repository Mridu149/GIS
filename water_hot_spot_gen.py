import numpy as np
import rasterio
import glob
import os
import sys
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, roc_auc_score
from scipy.ndimage import generic_filter
import matplotlib.pyplot as plt
import joblib

# ================================
# INPUT HANDLING
# ================================
if len(sys.argv) < 3:
    print("Usage: python water_hot_spot_gen.py <dtm_folder> <output_folder>")
    sys.exit(1)

data_folder = sys.argv[1]
output_folder = sys.argv[2]

if not os.path.exists(data_folder):
    print("Error: Input DTM folder not found!")
    sys.exit(1)

os.makedirs(output_folder, exist_ok=True)

print(f"Input DTM folder: {data_folder}")
print(f"Output folder: {output_folder}")

# ================================
# LOAD FILES
# ================================
tif_files = sorted(glob.glob(os.path.join(data_folder, "*.tif")))

if len(tif_files) == 0:
    print("No DTM files found!")
    sys.exit(1)

print(f"Found {len(tif_files)} DTM file(s):")
for f in tif_files:
    print(f"  - {os.path.basename(f)}")

# ================================
# FUNCTIONS
# ================================
def load_dtm(path):
    with rasterio.open(path) as src:
        elev = src.read(1).astype(float)
        profile = src.profile
        nodata = src.nodata

    if nodata is not None:
        elev[elev == nodata] = np.nan

    return elev, profile


def extract_features(elev):
    elev = np.nan_to_num(elev)

    dy, dx = np.gradient(elev)
    slope = np.arctan(np.sqrt(dx**2 + dy**2))

    curvature = (
        np.gradient(np.gradient(elev, axis=1), axis=1) +
        np.gradient(np.gradient(elev, axis=0), axis=0)
    )

    roughness = generic_filter(elev, np.std, size=3)

    def low_neighbour_count(patch):
        centre = patch[len(patch)//2]
        return np.sum(patch < centre)

    flow_proxy = generic_filter(elev, low_neighbour_count, size=5)

    slope_safe = np.where(slope < 0.001, 0.001, slope)
    twi = np.log((flow_proxy + 1) / np.tan(slope_safe))

    local_min = generic_filter(elev, np.min, size=7)
    depression = elev - local_min

    return {
        'elevation': elev,
        'slope': slope,
        'twi': twi,
        'curvature': curvature,
        'roughness': roughness,
        'flow_proxy': flow_proxy,
        'depression': depression
    }


def generate_labels(features):
    twi = features['twi']
    depression = features['depression']

    twi_thresh = np.nanpercentile(twi, 80)
    dep_thresh = np.nanpercentile(depression, 20)

    return ((twi >= twi_thresh) & (depression <= dep_thresh)).astype(np.uint8)

# ================================
# BUILD DATASET
# ================================
print("\nExtracting features...")

all_X = []
all_y = []
meta_list = []

for i, tif in enumerate(tif_files):
    name = os.path.splitext(os.path.basename(tif))[0]
    print(f"[{i+1}/{len(tif_files)}] {name}")

    elev, profile = load_dtm(tif)
    features = extract_features(elev)
    labels = generate_labels(features)

    feat_stack = np.stack(list(features.values()), axis=-1)
    X = feat_stack.reshape(-1, len(features))
    y = labels.flatten()

    valid = ~np.isnan(X).any(axis=1)

    if valid.sum() == 0:
        print(f"Skipping {name} (no valid pixels)")
        continue

    all_X.append(X[valid])
    all_y.append(y[valid])

    meta_list.append({
        'name': name,
        'features': features,
        'profile': profile
    })

# Combine dataset
X_all = np.vstack(all_X)
y_all = np.hstack(all_y)

print(f"\nTotal samples: {len(X_all)}")
print(f"Hotspot ratio: {y_all.mean()*100:.2f}%")

# ================================
# TRAIN MODEL
# ================================
print("\nTraining Random Forest...")

X_train, X_test, y_train, y_test = train_test_split(
    X_all, y_all, test_size=0.2, stratify=y_all, random_state=42
)

rf = RandomForestClassifier(
    n_estimators=200,
    max_depth=15,
    min_samples_leaf=10,
    class_weight='balanced',
    n_jobs=-1,
    random_state=42
)

rf.fit(X_train, y_train)

y_pred = rf.predict(X_test)
y_prob = rf.predict_proba(X_test)[:, 1]

print("\nClassification Report:")
print(classification_report(y_test, y_pred))
print(f"ROC-AUC: {roc_auc_score(y_test, y_prob):.4f}")

# Save model
model_path = os.path.join(output_folder, "rf_model.pkl")
joblib.dump(rf, model_path)
print(f"Model saved: {model_path}")

# ================================
# GENERATE OUTPUTS
# ================================
print("\nGenerating hotspot maps...")

for meta in meta_list:
    name = meta['name']
    features = meta['features']
    profile = meta['profile']

    feat_stack = np.stack(list(features.values()), axis=-1)
    h, w, n = feat_stack.shape

    X_full = feat_stack.reshape(-1, n)
    valid = ~np.isnan(X_full).any(axis=1)

    probs = np.full(h * w, np.nan)
    probs[valid] = rf.predict_proba(X_full[valid])[:, 1]

    prob_map = probs.reshape(h, w)

    # Save GeoTIFF
    tif_path = os.path.join(output_folder, f"{name}_hotspot.tif")
    out_profile = profile.copy()
    out_profile.update(dtype='float32', count=1, nodata=-1)

    with rasterio.open(tif_path, 'w', **out_profile) as dst:
        dst.write(prob_map.astype('float32'), 1)

    # Save PNG
    png_path = os.path.join(output_folder, f"{name}_hotspot.png")

    plt.figure(figsize=(6, 5))
    plt.imshow(prob_map, cmap='RdYlGn_r', vmin=0, vmax=1)
    plt.title(f"{name} Hotspot")
    plt.colorbar(label='Probability')
    plt.axis('off')
    plt.tight_layout()
    plt.savefig(png_path, dpi=120)
    plt.close()

    print(f"Saved: {tif_path}")

print("\nAll hotspot maps generated successfully.")
