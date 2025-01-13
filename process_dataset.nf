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
    publishDir "../Datasets/${params.dataset}/", mode: 'copy'

    input:
    path mask_fns

    output:
    path "rois.zip", emit: rois
    path "trackmate_features.csv", emit: trackmate_features
 
    script:
    """
    mkdir masks
    mv *.mask.tif masks
    track_images.py masks rois.zip trackmate_features.csv
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
    path roi_fn

    output:
    path "frame_features_*.csv"
 
    script:
    """
    frame_features_image.py ${trackmate_csv} ${image_fn} ${roi_fn}
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
    publishDir "../Datasets/${params.dataset}/", mode: 'copy'

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
    publishDir "../Datasets/${params.dataset}/", mode: 'copy'

    input:
    path(frame_features) 

    output:
    path "time_series_features.csv"
 
    script:
    """
    time_series_features.py $frame_features time_series_features.csv
    """
}

process ome_get_global_t {
    input:
    path(xml_file)

    output:
    stdout

    script:
    """
    xpath -q -e '//OME/Image/Pixels/TiffData/@FirstT' $xml_file | sed 's/FirstT=//g' | sed 's/\"//g'
    """
}

process ome_get_frame_t {
    input:
    path(xml_file)

    output:
    stdout

    script:
    """
    xpath -q -e '//OME/Image/Pixels/TiffData/@IFD' $xml_file | sed 's/IFD=//g' | sed 's/\"//g'
    """
}

process ome_get_filename {
    input:
    path(xml_file)

    output:
    stdout

    script:
    """
    xpath -q -e '//OME/Image/Pixels/TiffData/UUID/@FileName' $xml_file | sed 's/FileName=//g' | sed 's/\"//g'
    """
}

process split_ome_frames {
    publishDir "../Datasets/${params.dataset}/frames", mode: 'copy'

    input:
    tuple path(ome_fn), val(frame_index), val(global_frame_index)
    
    output:
    file('frame_*.tiff')

    script:
    """
    tiffcp ${ome_fn},${frame_index} frame_${global_frame_index}.tiff
    """
}

workflow {
    // TODO Split .ome files up if XML is present

    // Obtain a list of all the frames in the dataset with in the format:
    // (ome filename, ome frame index, overall frame index)
    xml_chan = channel.fromPath("../Datasets/${params.dataset}/raw/*companion.ome*")
    xml1 = ome_get_filename(xml_chan) 
        | splitText()
        | map( it -> it.trim())
        | map( it -> file("../Datasets/${params.dataset}/raw/" + it) )
    xml2 = ome_get_frame_t(xml_chan)
            | splitText()
            | map( it -> it.trim())
    xml3 = ome_get_global_t(xml_chan) 
            | splitText()
            | map( it -> it.trim())
            | map( it -> (it.toInteger() + 1).toString().padLeft(5, "0"))  // TODO possible to get the maximum number of frames?
                                                                           // Can't see a way of getting channel count as a groovy variable
    xml1
        | merge(xml2)
        | merge(xml3)
        | split_ome_frames

    // Specify file paths
    //allFiles = channel.fromPath("../Datasets/${params.dataset}/raw/*.tif*")

    //// Segment all images and track
    //segment_image(allFiles)
    //  | collect
    //  | track_images

    //// Generate CellPhe features on each frame separately
    //// Then combine and add the summary features (density, velocity etc..., then time-series features)
    //static_feats = cellphe_frame_features_image(
    //    allFiles,
    //    track_images.out.trackmate_features,
    //    track_images.out.rois
    //)
    //  | collect
    //  | combine_frame_features

    //create_frame_summary_features(static_feats, track_images.out.trackmate_features)
    //  | cellphe_time_series_features
}
