#!/usr/bin/env python
from cellphe import time_series_features
import pandas as pd
import argparse

parser = argparse.ArgumentParser(
                    description='Tracks a given image'
)
parser.add_argument('frame_file', help="Input frame features CSV file")
parser.add_argument('time_series_file', help="Output time series features CSV")
args = parser.parse_args()

# Step 6: Extract time series features only for cells tracked for more than 5 frames
new_features = pd.read_csv(args.frame_file)
cell_counts = new_features["CellID"].value_counts()

if any(cell_counts > 5):
    # Filter new_features to include only cells with more than 3 frames
    valid_cells = cell_counts[cell_counts > 50].index
    filtered_features = new_features[
        new_features["CellID"].isin(valid_cells)
    ]

    # Extract time series features
tsvariables = time_series_features(filtered_features)

# Save the new features to a CSV file
tsvariables.to_csv(args.time_series_file, index=False)

