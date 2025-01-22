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

frame_features = pd.read_csv(args.frame_file)
tsvariables = time_series_features(frame_features)
tsvariables.to_csv(args.time_series_file, index=False)

