#!/usr/bin/env python
from cellphe.features.frame import extract_static_features, STATIC_FEATURE_NAMES
from cellphe.input import read_rois, read_tiff, import_data
from cellphe.processing import normalise_image
import argparse
import re
import os
import numpy as np
import pandas as pd
from PIL import Image

parser = argparse.ArgumentParser(
                    description='Tracks a given image'
)
parser.add_argument('trackmate_file', help="Input trackmate CSV file")
parser.add_argument('image_file', help="Input frame filepath")
parser.add_argument('roi_file', help="Input ROIs archive")
args = parser.parse_args()

def load_image(path):
    image = Image.open(path)
    if (image.mode == 'RGB'):
        image = image.convert('L')
    image = np.array(image)
    image = (image - image.min()) / (image.max() - image.min())
    return image.astype("float32")

def get_index(fn):
    res = re.search(r"frame_([0-9]+)\.[jpg|jpeg|tif|tiff|JPG|JPEG|TIF|TIFF]", fn)
    if res is None:
        return None
    else:
        return int(res.group(1))

# Parse trackmate file
df = import_data(args.trackmate_file, "Trackmate_auto")

# Load frame and normalize to 0-1
image = load_image(args.image_file)

# Get FrameID from filename
frame_id = get_index(args.image_file)

# Find all cells in this frame
records = []
cell_ids = df.loc[df["FrameID"] == frame_id]["CellID"].unique()
rois = read_rois(args.roi_file)
for cell_id in cell_ids:
    roi_fn = df.loc[(df["FrameID"] == frame_id) & (df["CellID"] == cell_id)]["ROI_filename"].values[0]
    try:
        roi = rois[f"{roi_fn}.roi"]
    except FileNotFoundError:
        print(f"Unable to read file {roi_fn} - skipping to next ROI")
        continue
    # No negative coordinates
    roi = np.maximum(roi, 0)

    # Calculate static features of the frame/cell pair
    try:
        static_features = extract_static_features(image, roi)
    except RuntimeError:
        # Throw from lack of interior pixels
        pass

    # Collate into a dict that will later populate a data frame
    record = dict(zip(STATIC_FEATURE_NAMES, static_features))
    record["FrameID"] = frame_id
    record["CellID"] = cell_id
    record["ROI_filename"] = roi_fn
    records.append(record)
feats = pd.DataFrame.from_records(records)
# Create an empty header row if don't have any data, as otherwise nextflow complains
output_fn = f"frame_features_{frame_id}.csv"
if feats.shape[0] == 0:
    cols = STATIC_FEATURE_NAMES + ['FrameID', 'CellID', 'ROI_filename']
    with open(output_fn, "w") as outfile:
        outfile.write(",".join(cols))
else:
    feats.to_csv(output_fn, index=False)
