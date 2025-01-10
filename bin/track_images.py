#!/usr/bin/env python
from cellphe import track_images
import argparse

parser = argparse.ArgumentParser(
                    description='Tracks a given image'
)
parser.add_argument('mask_dir', help="Path to the folder containing the masks")
parser.add_argument('roi_filename', help="Archive to store the output ROIs in")
parser.add_argument('csv_filename', help="Filename for the output CSV file")
args = parser.parse_args()

track_images(
    mask_dir = args.mask_dir,
    csv_filename = args.csv_filename,
    roi_filename = args.roi_filename,
    tracker = "SimpleSparseLAP",
    tracker_settings = None,
    max_heap=32
)
