#!/usr/bin/env python
from cellphe import import_data, cell_features
import argparse

parser = argparse.ArgumentParser(
                    description='Tracks a given image'
)
parser.add_argument('trackmate_file', help="Input trackmate CSV file")
parser.add_argument('image_folder', help="Input frames folder")
parser.add_argument('rois_folder', help="Input ROIs folder")
parser.add_argument('frame_file', help="Filename for the output frame features CSV")
args = parser.parse_args()

feature_table = import_data(args.trackmate_file, "Trackmate_auto")
new_features = cell_features(
    feature_table, args.rois_folder, args.image_folder, framerate=0.0028
)
new_features.to_csv(args.frame_file, index=False)

