#!/usr/bin/env python
from cellphe import track_images
import argparse
import sys

parser = argparse.ArgumentParser(
                    description='Tracks a given image'
)
parser.add_argument('mask_dir', help="Path to the folder containing the masks")
parser.add_argument('roi_filename', help="Archive to store the output ROIs in")
parser.add_argument('csv_filename', help="Filename for the output CSV file")
parser.add_argument('memory', help="Requested memory")
args = parser.parse_args()

# Comes through as 'X GB' from Nextflow, obtain the number
requested_memory = int(args.memory.split(" ")[0])

try:
    track_images(
        mask_dir = args.mask_dir,
        csv_filename = args.csv_filename,
        roi_filename = args.roi_filename,
        tracker = "SimpleSparseLAP",
        tracker_settings = None,
        max_heap=requested_memory
    )
except Exception:  # Assume OOM - scyjava doesn't make it possible to specify which Java error was thrown
    sys.exit(125)  # Slurm out-of-memory
