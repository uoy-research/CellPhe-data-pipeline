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
parser.add_argument('input', help="Path to the raw image")
parser.add_argument('model', help="The name of the cellpose model to use")
parser.add_argument('output', help="Path to the output mask")
args = parser.parse_args()

if args.model.lower() == 'iolight':
    model = models.CellposeModel(gpu=False, pretrained_model="/mnt/scratch/projects/biol-imaging-2024/CP_20241218_ioLight")

else:
    model = models.CellposeModel(gpu=False, model_type=args.model)
image = read_tiff(args.input)
masks = model.eval(image)[0]
io.imsave(args.output, masks.astype("uint16"))  # Assuming masks are uint16
