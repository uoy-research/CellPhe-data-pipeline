params.dataset = ''

process segment_image {
    label 'slurm'
    time { 10.minute * task.attempt }
    memory { 2.GB * task.attempt }
    publishDir "../Datasets/${params.dataset}/masks", mode: 'copy'

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
    label 'slurm'
    cpus 4
    time { 30.minute * task.attempt }
    memory { 32.GB * task.attempt }
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
    track_images.py masks rois.zip trackmate_features.csv "$task.memory"
    """
}

process cellphe_frame_features_image {
    label 'slurm'
    time { 15.minute * task.attempt }
    memory { 2.GB * task.attempt }

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
    label 'slurm'
    time { 5.minute * task.attempt }
    memory { 4.GB * task.attempt }

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
    label 'slurm'
    time { 15.minute * task.attempt }
    memory { 4.GB * task.attempt }
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
    label 'slurm'
    time { 30.minute * task.attempt }
    memory { 4.GB * task.attempt }
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
    label 'local'

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
    label 'local'

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
    label 'local'

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
    label 'local'
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
    // Split .ome files up into 1 image per frame if XML is present
    xml_chan = file("../Datasets/${params.dataset}/raw/*companion.ome*")
    if (xml_chan.isEmpty()) {
        allFiles = channel.fromPath("../Datasets/${params.dataset}/raw/*.{tif,tiff,jpg,jpeg,TIF,TIFF,JPG,JPEG}")
    } else {
	    // Obtain a list of all the frames in the dataset in the format:
	    // (ome filename, ome frame index, overall frame index)
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
                | map( it -> (it.toInteger() + 1).toString().padLeft(5, "0"))  // TODO possible to get the maximum number of frames dynamically?
        allFiles = xml1
            | merge(xml2)
            | merge(xml3)
            | split_ome_frames
    }

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
