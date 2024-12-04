params.dataset = ''


def get_mask_dir = { x -> x.getParent().getParent() / 'masks' }
def get_mask_fn = { x -> get_mask_dir(x) / x.getName() }


process segment_image {
    executor 'slurm'
    cpus 1
    time '5 min'
    memory '4 GB'

    input:
    tuple path(input_fn, stageAs: "raw/*"), path(output_fn, stageAs: "masks/*")

    output:
    path output_fn
 
    script:
    """
    segment_image.py $input_fn $output_fn
    """
}

process track_images {
    executor 'slurm'
    cpus 1
    time '5 min'
    memory '8 GB'

    input:
    path mask_dir
    path roi_dir
    path csv_fn
    val dummy

    output:
    path csv_fn
 
    script:
    """
    track_images.py $mask_dir $roi_dir $csv_fn 
    """
}

process cellphe_frame_features {
    executor 'slurm'
    cpus 1
    time '60 min'
    memory '16 GB'

    input:
    path trackmate_csv
    path roi_dir
    path image_dir
    path frame_features

    output:
    path frame_features
 
    script:
    """
    frame_features.py $trackmate_csv $roi_dir $image_dir $frame_features
    """
}

process cellphe_time_series_features {
    executor 'slurm'
    cpus 1
    time '5 min'
    memory '8 GB'

    input:
    path(frame_features) 
    path(ts_features)

    output:
    path ts_features
 
    script:
    """
    time_series_features.py $frame_features $ts_features
    """
}


workflow {
    // Specify file paths
    image_dir = channel.fromPath("datasets/${params.dataset}/raw", type: 'dir')
    mask_dir = channel.fromPath("datasets/${params.dataset}/masks", type: 'dir')
    roi_dir = channel.fromPath("datasets/${params.dataset}/rois", type: 'dir')
    rois_fn = channel.fromPath("datasets/${params.dataset}/rois/*.roi", type: 'file')
    trackmate_csv = channel.fromPath("datasets/${params.dataset}/trackmate_features.csv", type: 'file')
    frame_features_csv = channel.fromPath("datasets/${params.dataset}/frame_features.csv", type: 'file')
    time_series_features_csv = channel.fromPath("datasets/${params.dataset}/ts_features.csv", type: 'file')
    allFiles = channel.fromPath("datasets/${params.dataset}/raw/*.tif*")

    maskFiles = allFiles.map(get_mask_fn)
    both = allFiles.merge(maskFiles)
    segment_output = segment_image(both).collect().transpose().collect()
    trackmate_features = track_images(mask_dir, roi_dir, trackmate_csv, segment_output)
    frame_out = cellphe_frame_features(trackmate_features, image_dir, roi_dir, frame_features_csv)
    cellphe_time_series_features(frame_out, time_series_features_csv)
}
