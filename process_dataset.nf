params.dataset = ''

process segment_image {
    executor 'slurm'
    cpus 1
    time '30 min'
    memory '8 GB'

    input:
    path input_fn

    output:
    path "*.mask.tif"
 
    script:
    outName = input_fn.baseName 
    """
    segment_image.py ${input_fn} ${outName}.mask.tif
    """
}

process track_images {
    executor 'slurm'
    cpus 8
    time '120 min'
    memory '32 GB'
    publishDir "datasets/${params.dataset}/", mode: 'copy'

    input:
    path mask_fns

    output:
    path "rois/", emit: rois, type: 'dir'
    path "trackmate_features.csv", emit: trackmate_features
 
    script:
    """
    mkdir masks
    mv *.mask.tif masks
    track_images.py masks rois trackmate_features.csv
    """
}

process cellphe_frame_features_image {
    executor 'slurm'
    cpus 1
    time '60 min'
    memory '16 GB'

    input:
    path image_fn
    path trackmate_csv
    path roi_dir

    output:
    path "frame_features_*.csv"
 
    script:
    """
    frame_features_image.py ${trackmate_csv} ${image_fn} ${roi_dir}
    """
}

process combine_frame_features {
    executor 'slurm'
    cpus 1
    time '15 min'
    memory '4 GB'

    input:
    path input_fns

    output:
    path "combined_frame_features.csv"
 
    script:
    """
    awk '(NR == 1) || (FNR > 1)' ${input_fns} > combined_frame_features.csv
    """
}

process create_frame_summary_features {
    executor 'slurm'
    cpus 2
    time '30 min'
    memory '16 GB'
    publishDir "datasets/${params.dataset}/", mode: 'copy'

    input:
    path(frame_features_static) 
    path(trackmate_features) 

    output:
    path "frame_features.csv"
 
    script:
    """
    create_frame_summary_features.py $frame_features_static $trackmate_features frame_features.csv
    """
}

process cellphe_time_series_features {
    executor 'slurm'
    cpus 1
    time '60 min'
    memory '16 GB'
    publishDir "datasets/${params.dataset}/", mode: 'copy'

    input:
    path(frame_features) 

    output:
    path "time_series_features.csv"
 
    script:
    """
    time_series_features.py $frame_features time_series_features.csv
    """
}


workflow {
    // Specify file paths
    allFiles = channel.fromPath("datasets/${params.dataset}/raw/*.tif*")

    // Segment all images and track
    segment_image(allFiles)
      | collect
      | track_images

    // Generate CellPhe features on each frame separately
    // Then combine and add the summary features (density, velocity etc..., then time-series features)
    static_feats = cellphe_frame_features_image(
	allFiles,
	track_images.out.trackmate_features,
 	track_images.out.rois
    )
      | collect
      | combine_frame_features

    create_frame_summary_features(static_feats, track_images.out.trackmate_features)
      | cellphe_time_series_features
}
