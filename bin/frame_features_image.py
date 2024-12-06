#!/usr/bin/env python
from cellphe import import_data
from cellphe.features.frame import extract_static_features, STATIC_FEATURE_NAMES
from cellphe.input import read_roi, read_tiff
from cellphe.processing import normalise_image
import argparse
import re
import os
import numpy as np
import pandas as pd

parser = argparse.ArgumentParser(
                    description='Tracks a given image'
)
parser.add_argument('trackmate_file', help="Input trackmate CSV file")
parser.add_argument('image_file', help="Input frame filepath")
parser.add_argument('roi_folder', help="Input ROIs folder")
parser.add_argument('--min_cell', help="Minimum cell size",
type=int, default=8)
args = parser.parse_args()

df = import_data(args.trackmate_file, "Trackmate_auto")

# Load frame
image = read_tiff(args.image_file)
image = normalise_image(image, 0, 255)

def get_index(fn):
    res = re.search(r"([0-9]+)(?:.ome)?\.tiff?$", fn)
    if res is None:
        return None
    else:
        return int(res.group(1))

# Get FrameID from filename
frame_id = get_index(args.image_file)

# Find all cells in this frame
records = []
cell_ids = df.loc[df["FrameID"] == frame_id]["CellID"].unique()
for cell_id in cell_ids:
    roi_fn = df.loc[(df["FrameID"] == frame_id) & (df["CellID"] == cell_id)]["ROI_filename"].values[0]
    roi_path = os.path.join(args.roi_folder, f"{roi_fn}.roi")
    try:
        roi = read_roi(roi_path)
    except FileNotFoundError:
        print(f"Unable to read file {roi_path} - skipping to next ROI")
        continue
    # No negative coordinates
    roi = np.maximum(roi, 0)
    # Ensure cell is minimum size
    max_dims = roi.max(axis=0)
    min_dims = roi.min(axis=0)
    range_dims = max_dims - min_dims + 1
    if np.any(range_dims < args.min_cell):
        continue

    # Calculate static features of the frame/cell pair
    static_features = extract_static_features(image, roi)

    # Collate into a dict that will later populate a data frame
    record = dict(zip(STATIC_FEATURE_NAMES, static_features))
    record["FrameID"] = frame_id
    record["CellID"] = cell_id
    record["ROI_filename"] = roi_fn
    records.append(record)
feats = pd.DataFrame.from_records(records)
feats.to_csv(f"frame_features_{frame_id}.csv", index=False)
