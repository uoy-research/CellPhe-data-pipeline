#!/usr/bin/env python
import argparse
import json
import sys
import xml.etree.ElementTree as ET
import scyjava as sj
import numpy as np
import pandas as pd
from cellphe.processing.roi import save_rois
from cellphe.trackmate import load_detector, load_tracker

parser = argparse.ArgumentParser(
                    description='Tracks a given image'
)
parser.add_argument('xml_path', help="Path of TrackMate XML file")
parser.add_argument('rois_path', help="Path to output ROIs zip")
parser.add_argument('csv_path', help="Path to output feature csv")
args = parser.parse_args()

tree = ET.parse(args.xml_path)
spot_records = []
rois = {}
# Get all Spots firstly
for frame in tree.findall("./Model/AllSpots/SpotsInFrame"):
    # Get all spots, reading in their attributes and ROIs
    for spot in frame.findall("Spot"):
        spot_records.append(spot.attrib)
        # Read ROIs
        coords = np.array([spot.text.split(" ")]).astype(float)
        coords = coords.reshape(int(coords.size / 2), 2)
        coords[:, 0] = coords[:, 0] + float(spot.attrib["POSITION_X"])
        coords[:, 1] = coords[:, 1] + float(spot.attrib["POSITION_Y"])
        rois[spot.attrib["name"]] = coords
spot_df = pd.DataFrame.from_records(spot_records)
spot_df = spot_df.rename(columns={"name": "LABEL"})

# Then get all Tracks so can add TRACK_ID
# Tracks are stored as edges between source and target cells in consecutive
# frames. To get the unique cell ids in each track, store both source and
# target and remove duplicates after. More memory intensive but simple
track_records = []
for track in tree.findall("./Model/AllTracks/Track"):
    for edge in track.findall("Edge"):
        track_records.append({"TRACK_ID": track.attrib["TRACK_ID"], "ID": edge.attrib["SPOT_TARGET_ID"]})
        track_records.append({"TRACK_ID": track.attrib["TRACK_ID"], "ID": edge.attrib["SPOT_SOURCE_ID"]})
track_df = pd.DataFrame.from_records(track_records).drop_duplicates()

# Combine Spots and Tracks
comb_df = pd.merge(spot_df, track_df, on="ID")
# Reorder columns to be the same as exported from the GUI
col_order = [
    "LABEL",
    "ID",
    "TRACK_ID",
    "QUALITY",
    "POSITION_X",
    "POSITION_Y",
    "POSITION_Z",
    "POSITION_T",
    "FRAME",
    "RADIUS",
    "VISIBILITY",
    "MEAN_INTENSITY_CH1",
    "MEDIAN_INTENSITY_CH1",
    "MIN_INTENSITY_CH1",
    "MAX_INTENSITY_CH1",
    "TOTAL_INTENSITY_CH1",
    "STD_INTENSITY_CH1",
    "CONTRAST_CH1",
    "SNR_CH1",
    "ELLIPSE_X0",
    "ELLIPSE_Y0",
    "ELLIPSE_MAJOR",
    "ELLIPSE_MINOR",
    "ELLIPSE_THETA",
    "ELLIPSE_ASPECTRATIO",
    "AREA",
    "PERIMETER",
    "CIRCULARITY",
    "SOLIDITY",
    "SHAPE_INDEX",
]
comb_df = comb_df[col_order]

# Want CellID and FrameID to be 1-indexed
comb_df["TRACK_ID"] = comb_df["TRACK_ID"].astype(int) + 1
comb_df["FRAME"] = comb_df["FRAME"].astype(int) + 1
# Create a ROI filename column - 0 padded
n_digits_track_id = len(str(np.max(comb_df["TRACK_ID"])))
n_digits_frame_id = len(str(np.max(comb_df["FRAME"])))
n_digits_spot_id = len(str(np.max(comb_df["ID"])))
comb_df["ROI_FILENAME"] = (
    comb_df["FRAME"].astype(str).str.pad(n_digits_frame_id, fillchar="0")
    + "-"
    + comb_df["TRACK_ID"].astype(str).str.pad(n_digits_track_id, fillchar="0")
    + "-"
    + comb_df["ID"].astype(str).str.pad(n_digits_spot_id, fillchar="0")
)
clean_rois = []
for _, row in comb_df.iterrows():
    try:
        this_cell = {
            "CellID": row["TRACK_ID"],
            "FrameID": row["FRAME"],
            "Filename": row["ROI_FILENAME"],
            "coords": rois[row["LABEL"]],
        }
        clean_rois.append(this_cell)
    except KeyError:
        pass

# Save to disk
comb_df.to_csv(args.csv_path, index=False)
save_rois(clean_rois, args.rois_path)
