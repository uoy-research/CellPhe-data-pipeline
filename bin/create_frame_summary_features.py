#!/usr/bin/env python
import cellphe
import argparse
import pandas as pd
import numpy as np

parser = argparse.ArgumentParser(
                    description='Creates the temporal frame features (density, velocity etc...)'
)
parser.add_argument('frame_features', help="The static frame features CSV")
parser.add_argument('trackmate', help="The original Trackmate CSV")
parser.add_argument('output', help="Where to save the resultant file with the added features")
parser.add_argument('--framerate', help="Cell framerate", default=0.0028, type=float)
args = parser.parse_args()

# Read in the combined static features
feature_df = pd.read_csv(args.frame_features)
trackmate_df = cellphe.import_data(args.trackmate, "Trackmate_auto")

# Movement features
# Overall distance since starting point
start_vals = feature_df.loc[feature_df.groupby("CellID")["FrameID"].idxmin(), ["CellID", "x", "y"]]
start_vals.rename(columns={"x": "x_start", "y": "y_start"}, inplace=True)
feature_df = feature_df.merge(start_vals, on="CellID")
# Order in time so movement features are accurate
feature_df.sort_values(["CellID", "FrameID"], inplace=True)
feature_df["Dis"] = np.sqrt(
    (feature_df["x"] - feature_df["x_start"]) ** 2 + (feature_df["y"] - feature_df["y_start"]) ** 2
)

# Frame by frame distance and speed
feature_df["x_diff"] = feature_df.groupby("CellID")["x"].transform("diff")
feature_df["y_diff"] = feature_df.groupby("CellID")["y"].transform("diff")
feature_df["frame_dist"] = np.sqrt(feature_df["x_diff"] ** 2 + feature_df["y_diff"] ** 2)
feature_df.loc[pd.isna(feature_df["frame_dist"]), "frame_dist"] = 0

# Cumulative distance moved and ratio to distance from start
feature_df["Trac"] = feature_df.groupby("CellID")["frame_dist"].transform("cumsum")
feature_df["D2T"] = feature_df["Dis"] / feature_df["Trac"]
feature_df.loc[pd.isna(feature_df["D2T"]), "D2T"] = 0

# Velocity
feature_df["FrameID_diff"] = feature_df.groupby("CellID")["FrameID"].transform("diff")
# Doesn't matter what this is set to as it's only used for the first
# appearance of a cell, in which case the numerator will be 0. Just need it
# to be non-NA and non-0 (as that causes Infs)
feature_df.loc[pd.isna(feature_df["FrameID_diff"]), "FrameID_diff"] = 1
feature_df["Vel"] = (args.framerate * feature_df["frame_dist"]) / feature_df["FrameID_diff"]

# Drop intermediate columns
feature_df.drop(columns=["x_start", "y_start", "x_diff", "y_diff", "frame_dist", "FrameID_diff"], inplace=True)

# Add on the original columns
feature_df = feature_df.merge(trackmate_df, on=["CellID", "FrameID", "ROI_filename"])

# Add density
# TODO: doesn't work with large datasets, runs out of memory
#dens = cellphe.features.frame.calculate_density(feature_df)
#feature_df = feature_df.merge(dens, how="left", on=["FrameID", "CellID"])
#feature_df.loc[pd.isna(feature_df["dens"]), "dens"] = 0
feature_df['dens'] = 0

# Reorder columns
col_order = trackmate_df.columns.values.tolist() + ["Dis", "Trac", "D2T", "Vel"] + cellphe.features.frame.STATIC_FEATURE_NAMES + ["dens"]
feature_df = feature_df[col_order]

# Set data types for anything that isn't float
feature_df["Area"] = feature_df["Area"].astype("int")

feature_df.to_csv(args.output, index=False)

