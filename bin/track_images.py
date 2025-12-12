#!/usr/bin/env python
import argparse
import json
import sys
import scyjava as sj
import imagej

def setup_imagej(max_heap: int | None = None) -> None:
    """
    Sets up a JVM with ImageJ and the TrackMate plugin loaded.

    :param max_heap: Size in GB of the maximum heap size allocated to the JVM.
    Use if you are encountering memory problems with large datasets. Be careful
    when using this parameter, the rule of thumb is not to assign more than 80%
    of your computer's available memory.
    :return: None, although could be updated to return reference to a Java class
    net.imagej.ImageJ.
    """
    if max_heap is not None and isinstance(max_heap, int) and max_heap > 0:
        sj.config.add_option(f"-Xmx{max_heap}g")
    imagej.init(["net.imagej:imagej", "sc.fiji:TrackMate:7.13.2"], add_legacy=False)


def read_image_stack(image_dir: str):
    """
    Reads a directory containing TIFs into ImageJ as a stack.

    :param dir: Directory where the TIFs are located.
    :return: An ImagePlus instance containing an ImageStack.
    """
    # pylint doesn't like the camel case naming. I think it helps readability as
    # it denotes a Java class
    # pylint: disable=invalid-name
    FolderOpener = sj.jimport("ij.plugin.FolderOpener")
    # Load all images as framestack
    imp = FolderOpener.open(image_dir, "")

    # When reading in the imagestack, the the number of frames is often
    # (always?) interpreted as the number of channels. This corrects that in the
    # same way as the info box that pops up when using TrackMate in the GUI
    # Dims are ordered X Y Z C T
    dims = imp.getDimensions()
    if dims[4] == 1:
        # If time dimension is actually in Z, swap Z & T
        if dims[2] > 1:
            imp.setDimensions(dims[4], dims[3], dims[2])
        # If time dimension is actually in channels (usual case), swap C & T
        elif dims[3] > 1:
            imp.setDimensions(dims[2], dims[4], dims[3])
        # If none of Z, C, T contain more than 1 (i.e. time), then we have an
        # error
        else:
            raise ValueError(
                f"""Time-dimension could not be identified as none of the Z, C, or T
                channels contain more than 1 value: {dims[2:]}"""
            )
    return imp


def load_detector(settings) -> None:
    """
    Loads a TrackMate detector.
    Currently hardcoded to be the LabelImageDetector, as this works with the
    labelled masks output from Cellpose.

    :param settings: An instance of the Java class
        fiji.plugin.Trackmate.Settings
    :return: None, updates settings as a side-effect.
    """
    settings.detectorFactory = sj.jimport("fiji.plugin.trackmate.detection.LabelImageDetectorFactory")()
    settings.detectorSettings = settings.detectorFactory.getDefaultSettings()


def load_tracker(settings, tracker: str, tracker_settings: dict) -> None:
    """
    Loads a TrackMate tracker.

    :param settings: An instance of the Java class
        fiji.plugin.Trackmate.Settings
    :param tracker: String specifying which tracking algorithm to use. Possible
        options are:
            - SimpleSparseLAP
            - SparseLAP
            - Kalman
            - AdvancedKalman
            - NearestNeighbor
            - Overlap
    :param tracker_settings: Dictionary containing parameters for the specified
        tracker. These should be written the same way they are in the TrackMate
        GUI. See the source code for a full reference:
            https://github.com/trackmate-sc/TrackMate/blob/master/src/main/java/fiji/plugin/trackmate/tracking/TrackerKeys.java.
    :return: None, updates settings as a side-effect.
    """
    options = {
        "SimpleSparseLAP": "fiji.plugin.trackmate.tracking.jaqaman.SimpleSparseLAPTrackerFactory",
        "SparseLAP": "fiji.plugin.trackmate.tracking.jaqaman.SparseLAPTrackerFactory",
        "Kalman": "fiji.plugin.trackmate.tracking.kalman.KalmanTrackerFactory",
        "AdvancedKalman": "fiji.plugin.trackmate.tracking.kalman.AdvancedKalmanTrackerFactory",
        "NearestNeighbor": "fiji.plugin.trackmate.tracking.kdtree.NearestNeighborTrackerFactory",
        "Overlap": "fiji.plugin.trackmate.tracking.overlap.OverlapTrackerFactory",
    }
    try:
        selected = options[tracker]
    except KeyError as ex:
        raise KeyError(f"tracker must be one of {','.join(options.keys())}") from ex

    settings.trackerFactory = sj.jimport(selected)()
    settings.trackerSettings = settings.trackerFactory.getDefaultSettings()
    if tracker_settings is not None:
        for k, v in tracker_settings.items():
            # The automatic type conversion fails in some cases
            if isinstance(v, dict):
                hash_map = sj.jimport("java.util.HashMap")
                val = hash_map(v)
            elif isinstance(v, bool):
                jbool = sj.jimport("java.lang.Boolean")
                val = jbool(v)
            elif isinstance(v, int):
                jint = sj.jimport("java.lang.Integer")
                val = jint(v)
            else:
                val = v
            settings.trackerSettings[k] = val

parser = argparse.ArgumentParser(
                    description='Tracks a given image'
)
parser.add_argument('mask_dir', help="Path to the folder containing the masks")
parser.add_argument('memory', help="Requested memory")
parser.add_argument('config', help="TrackMate configuration settings")
parser.add_argument('xml_path', help="Where to save the XML to")
args = parser.parse_args()

# Comes through as 'X GB' from Nextflow, obtain the number
try:
    requested_memory = int(args.memory.split(" ")[0])
except ValueError:
    requested_memory = None
config = json.loads(args.config)
mask_dir = args.mask_dir
tracker = config['algorithm']
tracker_settings = config['settings']

try:
    setup_imagej(requested_memory)

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
