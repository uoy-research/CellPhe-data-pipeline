params.dataset = ''

process segment_image {
    executor 'slurm'
    cpus 1
    time '5 min'
    memory '4 GB'

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

process cellphe_frame_features {
    executor 'slurm'
    cpus 1
    time '60 min'
    memory '16 GB'
    publishDir "datasets/${params.dataset}/", mode: 'copy'

    input:
    path trackmate_csv
    path raw_dir
    path roi_dir

    output:
    path "frame_features.csv"
 
    script:
    """
    frame_features.py ${trackmate_csv} ${raw_dir} ${roi_dir} frame_features.csv
    """
}

process cellphe_time_series_features {
    executor 'slurm'
    cpus 1
    time '5 min'
    memory '8 GB'
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
    maskDir = segment_image(allFiles)
    track_out = track_images(maskDir.collect())
    frame_out = cellphe_frame_features(track_images.out.trackmate_features, file("datasets/${params.dataset}/raw"), track_images.out.rois)
    cellphe_time_series_features(frame_out)
}
