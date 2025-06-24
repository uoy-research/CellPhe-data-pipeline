#!/usr/bin/env python
import argparse
from dataclasses import dataclass, field
import json
import sys
from typing import List
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

# Get all Spots
nodes = {}
@dataclass
class Node:
    id: int
    frame: int
    children: List[id] = field(default_factory=list)
    parents: List[id] = field(default_factory=list)

for frame in tree.findall("./Model/AllSpots/SpotsInFrame"):
    # Get all spots, reading in their attributes and ROIs
    for spot in frame.findall("Spot"):
        spot_records.append(spot.attrib)
        node_id = int(spot.attrib['ID'])
        nodes[node_id] = Node(id=node_id, frame=int(spot.attrib['FRAME']))
        # Read ROIs
        coords = np.array([spot.text.split(" ")]).astype(float)
        coords = coords.reshape(int(coords.size / 2), 2)
        coords[:, 0] = coords[:, 0] + float(spot.attrib["POSITION_X"])
        coords[:, 1] = coords[:, 1] + float(spot.attrib["POSITION_Y"])
        rois[spot.attrib["name"]] = coords
spot_df = pd.DataFrame.from_records(spot_records)
spot_df = spot_df.rename(columns={"name": "LABEL"})
spot_df['ID'] = spot_df['ID'].astype('int')
spot_df['FRAME'] = spot_df['FRAME'].astype('int')

# Add edges to children and parents
for track in tree.findall("./Model/AllTracks/Track"):
    for edge in track.findall("Edge"):
        source_id = int(edge.attrib["SPOT_SOURCE_ID"])
        target_id = int(edge.attrib["SPOT_TARGET_ID"])
        nodes[source_id].children.append(target_id)
        nodes[target_id].parents.append(source_id)

# Remove nodes with no parents or children - not part of any track
for id in list(nodes.keys()):
    if len(nodes[id].parents) == 0 and len(nodes[id].children) == 0:
        nodes.pop(id)

# Obtain root nodes in frame order
root_nodes = [n for id, n in nodes.items() if len(n.parents) == 0]
root_nodes.sort(key = lambda x: x.frame)

# Iterate through graph, creating unique track ids
track_records = []
track_id = 0
traversed_nodes = set()
def traverse_track(node, accum=False):
    """
    Recursive function to traverse a graph representing tracks between
    cells in a timelapse.
    A global counter keeps track of the current track id, and is incremented
    whenever a split event is reached (defined as a parent having more than
    1 child).

    Args:
        - node (Node): The current node being visited.
        - accum (bool): Whether to accumulate the track_id counter in case a
          split event is reached.

    Returns:
        None. Populates a global variable `track_records` with visited nodes
        and their newly assigned track_id instead.
    """
    global track_id

    # Prevent multiple tracks on a merge
    if node.id in traversed_nodes:
        return

    # Assign different track_ids after a split
    if accum:
        track_id += 1

    track_records.append({'ID': node.id, 'TRACK_ID': track_id})
    traversed_nodes.add(node.id)
    for j, child in enumerate(node.children):
        traverse_track(nodes[child], j > 0)

# Traverse graph starting from from all root nodes, each of which will
# accumulate the track counter.
for i, root in enumerate(root_nodes):
    traverse_track(root, i > 0)

# Combine Spots and Tracks into single DataFrame
track_df = pd.DataFrame.from_records(track_records)
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
comb_df["TRACK_ID"] = comb_df["TRACK_ID"] + 1
comb_df["FRAME"] = comb_df["FRAME"] + 1
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
