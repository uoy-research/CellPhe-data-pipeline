#!/usr/bin/env python
from cellpose import models
import argparse
import numpy as np
from pathlib import Path
from PIL import Image
from skimage import io
import json

parser = argparse.ArgumentParser(
                    description='Creates the segmentation mask for a single image using CellPose'
)
parser.add_argument('model_args', help="Arguments for CellPoseModel")
parser.add_argument('eval_args', help="Arguments for CellPoseModel.eval")
parser.add_argument('files', help="List of images to process")
args = parser.parse_args()
model_args = json.loads(args.model_args)
eval_args = json.loads(args.eval_args)

model = models.CellposeModel(**model_args)
for fn in args.files.split(" "):
    output_fn = f"{Path(fn).stem}_mask.png"
    image = np.array(Image.open(fn))
    masks = model.eval(image, **eval_args)[0]
    io.imsave(output_fn, masks.astype("uint16"))  # Assuming masks are uint16
