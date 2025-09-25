#!/usr/bin/env python
import argparse
import json
import sys
import scyjava as sj
from cellphe.imagej import read_image_stack, setup_imagej
from cellphe.trackmate import configure_trackmate, get_trackmate_xml, load_detector, load_tracker

parser = argparse.ArgumentParser(
                    description='Tracks a given image'
)
parser.add_argument('mask_dir', help="Path to the folder containing the masks")
parser.add_argument('memory', help="Requested memory")
parser.add_argument('config', help="TrackMate configuration settings")
parser.add_argument('xml_path', help="Where to save the XML to")
args = parser.parse_args()

# Comes through as 'X GB' from Nextflow, obtain the number
requested_memory = int(args.memory.split(" ")[0])
config = json.loads(args.config)
mask_dir = args.mask_dir
tracker = config['algorithm']
tracker_settings = config['settings']
max_heap = requested_memory

try:
    setup_imagej(max_heap)

    imp = read_image_stack(mask_dir)
    settings = sj.jimport("fiji.plugin.trackmate.Settings")(imp)
    load_detector(settings)
    load_tracker(settings, tracker, tracker_settings)

    # Configure TrackMate instance
    model = sj.jimport("fiji.plugin.trackmate.Model")()
    settings.initialSpotFilterValue = 1.0

    # Rather than using addAllAnalyzers which adds all Spot, Edge, and Track features,
    # we want to add all bar elliptical ones, which can error in certain ROIs.
    # It's not possible to add all the feature providers and then just remove the elliptical
    # one, so instead we'll manually add just the ones we want

    spot_provider = sj.jimport("fiji.plugin.trackmate.providers.SpotAnalyzerProvider")(1)
    spot_keys = spot_provider.getKeys()
    for key in spot_keys:
        settings.addSpotAnalyzerFactory(spot_provider.getFactory(key))

    morph_provider = sj.jimport("fiji.plugin.trackmate.providers.SpotMorphologyAnalyzerProvider")(1)
    settings.addSpotAnalyzerFactory(morph_provider.getFactory('Spot 2D shape descriptors'))

    edge_provider = sj.jimport("fiji.plugin.trackmate.providers.EdgeAnalyzerProvider")()
    edge_keys = edge_provider.getKeys()
    for key in edge_keys:
        settings.addEdgeAnalyzer(edge_provider.getFactory(key))

    track_provider = sj.jimport("fiji.plugin.trackmate.providers.TrackAnalyzerProvider")()
    track_keys = track_provider.getKeys()
    for key in track_keys:
        settings.addTrackAnalyzer(track_provider.getFactory(key))

    tm_cls = sj.jimport("fiji.plugin.trackmate.TrackMate")
    trackmate = tm_cls(model, settings)

    print("Configured trackmate")
    if not trackmate.checkInput():
        print("Settings error")
        sys.exit(str(trackmate.getErrorMessage()))
    print("Checked input")

    # Run the full detection + tracking process
    if not trackmate.process():
        print("process error")
        sys.exit(str(trackmate.getErrorMessage()))
    print("Processed")

    # Export to and extract the Spots, Tracks, and ROIs
    file_cls = sj.jimport("java.io.File")
    writer_cls = sj.jimport("fiji.plugin.trackmate.io.TmXmlWriter")
    writer = writer_cls(file_cls(args.xml_path))
    writer.appendSettings(settings)
    writer.appendModel(model)
    writer.writeToFile()
    print("Written to XML")

except Exception as e:
    print(f"Error: {e}")
    if str(e) == 'java.lang.OutOfMemoryError':
        code = 125 # Slurm out of memory, will retry
    else:
        code = 1
    sys.exit(code)
