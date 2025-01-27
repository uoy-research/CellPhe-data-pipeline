#!/usr/bin/env python
from cellpose import models
import argparse
import numpy as np
from PIL import Image
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
image = np.array(Image.open(args.input))
masks = model.eval(image, channels=[0, 0])[0]
io.imsave(args.output, masks.astype("uint16"))  # Assuming masks are uint16
