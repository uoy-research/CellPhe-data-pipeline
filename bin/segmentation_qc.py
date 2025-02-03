#!/usr/bin/env python
import argparse
import re
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap
import os
import math
from PIL import Image

# Extract file paths from arguments
parser = argparse.ArgumentParser(
            prog='Segmentation QC',
            description='Generates summary plots from the segmentation'
        )
parser.add_argument('files')
args = parser.parse_args()
fns = args.files.split(" ")

# Split into fns to be read just to get counts and those which will keep to plot
fns_plot = [fns[i] for i in range(len(fns)) if i % 10 == 0]

def extract_frame_id(fn):
    bn = os.path.basename(fn)
    res = re.search('frame_([0-9]+)_mask.png', bn)
    return int(res.groups()[0])

def get_image(fn):
    return np.array(Image.open(fn))

images = [get_image(fn) for fn in fns_plot]

# Create plots
def create_cmap(img, page_size=20, palette="Pastel1"):
    n_groups = np.unique(img).size
    
    viridis = plt.get_cmap(palette, page_size)
    newcolors = np.zeros((n_groups, 4))
    # Pagination
    n_remaining = n_groups
    start = 0
    while n_remaining > 0:
        n_page = min(n_remaining, page_size)
        newcolors[start:(start+n_page), ] = viridis.colors[:n_page]
        n_remaining -= n_page
        start += n_page
        
    # Shuffle
    rng = np.random.default_rng()
    rng.shuffle(newcolors)
    newcolors[0, ] = np.array([1, 1, 1, 0.1])
    return ListedColormap(newcolors)

n_images = len(images)
COLS = 8
ROWS = math.ceil(n_images / COLS)
fig, axes = plt.subplots(
    ROWS,
    COLS,
    sharex=True,
    sharey=True,
    figsize=(COLS*2, ROWS*2)
)
counter = 0
# Subplots returns 1D list if request 1 row, force
# it to always return 2D
if ROWS == 1:
    axes = [axes,]
for i, ax_row in enumerate(axes):
    for j in range(len(ax_row)):
        ax = ax_row[j]
        ax.tick_params(
            axis='both',
            which='both',
            bottom=False,
            left=False,
            labelbottom=False,
            labelleft=False
        )
        if counter >= len(images):
            _dummy = ax.axis("off")
        else:
            _dummy = ax.imshow(
                images[counter], 
                cmap=create_cmap(images[counter])
            )
            _dummy = ax.set_title(
                f"Frame {extract_frame_id(fns_plot[counter])}",
                fontsize=8
            )
        counter += 1
fig.subplots_adjust(wspace=0.05, hspace=0, top=0.99, left=0.01, bottom=0.01, right=0.99)
fig.savefig("segmentation_masks_stitched.png")


# Summary statistics
def get_counts(fn):
    img = get_image(fn)
    counts = np.unique(img, return_counts=True)
    df = pd.DataFrame({
        'frame_id': extract_frame_id(fn),
        'mask_id': counts[0],
        'n': counts[1]
    })
    return df.loc[df['mask_id'] != 0]
    
counts = pd.concat([get_counts(x) for x in fns])

def plot_histogram(vals, filename, x_lab, y_lab):
    fig, ax = plt.subplots(1,1, figsize=(8, 6))
    ax.hist(vals)
    props = dict(boxstyle='round', facecolor='grey', alpha=0.15)  # bbox features
    ax.text(1.03, 0.98, vals.describe(), transform=ax.transAxes, fontsize=12, verticalalignment='top', bbox=props)
    ax.set_ylabel(y_lab)
    ax.set_xlabel(x_lab)
    fig.tight_layout()
    fig.savefig(filename, bbox_inches='tight')

# Summarise how many cells per frame
cells_per_frame = counts.groupby(['frame_id']).agg('count').reset_index()[['frame_id', 'n']]
plot_histogram(cells_per_frame['n'], "segmentation_cells_per_frame.png", "Number of cells in a frame",
               "Number of frames")

# Summarise cell areas
plot_histogram(counts['n'], "segmentation_cells_area.png", "Cell size (pixels)", "Number of cells")
