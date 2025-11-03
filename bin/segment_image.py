#!/usr/bin/env python3
from cellpose import models
import argparse
import numpy as np
from PIL import Image
from skimage import io
import json

parser = argparse.ArgumentParser(
                    description='Creates the segmentation mask for a single image using CellPose'
)
parser.add_argument('input', help="Path to the raw image")
parser.add_argument('output', help="Path to the output mask")
parser.add_argument('model_args', help="Arguments for CellPoseModel")
parser.add_argument('eval_args', help="Arguments for CellPoseModel.eval")
args = parser.parse_args()
model_args = json.loads(args.model_args)
eval_args = json.loads(args.eval_args)

image = np.array(Image.open(args.input))
model = models.CellposeModel(**model_args)
masks = model.eval(image, **eval_args)[0]
io.imsave(args.output, masks.astype("uint16"))  # Assuming masks are uint16
