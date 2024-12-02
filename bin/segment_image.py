#!/usr/bin/env python
import argparse
import os
import glob
from cellpose import models
from cellphe.input import read_tiff
from skimage import io

parser = argparse.ArgumentParser(
                    description='Creates the segmentation mask for a single image using CellPose'
)
parser.add_argument('input', help="Path to the raw TIF")
parser.add_argument('output', help="Path to the output TIF mask")
args = parser.parse_args()

model = models.Cellpose(gpu=False, model_type="cyto")
image = read_tiff(args.input)
masks, _, _, _ = model.eval(image)
io.imsave(args.output, masks.astype("uint16"))  # Assuming masks are uint16
