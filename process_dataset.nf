import groovy.json.JsonOutput
params.dataset = ''
// Populated by params file
params.segmentation = ''
params.tracking = ''
params.QC = ''

cellpose_model_opts = JsonOutput.toJson(params.segmentation.model)
cellpose_eval_opts = JsonOutput.toJson(params.segmentation.eval)
trackmate_opts = JsonOutput.toJson(params.tracking)

process segment_image {
    label 'slurm'
    time { 5.minute * task.attempt }
    memory { 4.GB * task.attempt }
    publishDir "../Datasets/${params.dataset}/masks", mode: 'copy'

    input:
    path input_fn

    output:
    path "*_mask.png"
 
    script:
    outName = input_fn.baseName 
    """
    segment_image.py ${input_fn} ${outName}_mask.png '${cellpose_model_opts}' '${cellpose_eval_opts}'
    """
}

process track_images {
    label 'slurm'
    clusterOptions '--cpus-per-task=64 --ntasks=1'
    time 60.minute
    memory 64.GB
    maxRetries 0

    input:
    path mask_fns

    output:
    path "trackmate.xml"
 
    script:
    """
    mkdir masks
    mv *_mask.png masks
    track_images.py masks '$task.memory' '${trackmate_opts}' trackmate.xml
    """
}

process parse_trackmate_xml {
    label 'slurm'
    clusterOptions '--cpus-per-task=4 --ntasks=1'
    time { 20.minute * task.attempt }
    memory { 8.GB * task.attempt }
    publishDir "../Datasets/${params.dataset}/", mode: 'copy'

    input:
    path xml_file

    output:
    path "rois.zip", emit: rois
    path "trackmate_features.csv", emit: features

    script:
    """
    parse_xml.py ${xml_file} rois.zip trackmate_features.csv
    """
}

process filter_size_and_observations {
    label 'slurm'
    time { 5.minute * task.attempt }
    memory { 8.GB * task.attempt }
    publishDir "../Datasets/${params.dataset}/", mode: 'copy'

    input:
    path features_original

    output:
    path("trackmate_features_filtered.csv", arity: '1')

    """
    #!/usr/bin/env python
    import pandas as pd
    feats = pd.read_csv("${features_original}")
    feats = feats.loc[feats['AREA'] >= int(${params.QC.minimum_cell_size})]
    feats = feats.groupby("TRACK_ID").filter(lambda x: x["FRAME"].count() >= int(${params.QC.minimum_observations}))
    if feats.shape[0] > 0:
        feats.to_csv("trackmate_features_filtered.csv", index=False)
    """
}

process cellphe_frame_features_image {
    label 'slurm'
    time { 5.minute * task.attempt }
    memory { 16.GB * task.attempt }

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

    input:
    tuple path(ome_fn), val(frame_index), val(global_frame_index)
    
    output:
    file('ome_split_*.tiff')

    script:
    """
    tiffcp ${ome_fn},${frame_index} ome_split_${global_frame_index}.tiff
    """
}

process rename_frames {
    label 'slurm'
    time { 5.minute * task.attempt }
    memory { 4.GB * task.attempt }

    input:
    path in_files

    output:
    file('frame_*.tiff')

    """
    #!/usr/bin/env python

    import os
    import shutil
    import pathlib

    raw_fns = "${in_files}".split(" ")
    for i, raw_fn in enumerate(sorted(raw_fns)):
        new_fn = f"frame_{i+1:05}.tiff"
        shutil.copy2(raw_fn, new_fn)
    """
}

process split_stacked_tiff {
    label 'slurm'
    time { 5.minute * task.attempt }
    memory { 4.GB * task.attempt }

    input:
    path(stacked_tiff) 

    output:
    path "part_*.tif"
 
    script:
    """
    tiffsplit "${stacked_tiff}" part_
    """
}

process create_tiff_stack {
    label 'slurm'
    time { 5.minute * task.attempt }
    memory { 4.GB * task.attempt }
    publishDir "../Datasets/${params.dataset}", mode: 'copy'

    input:
    path(frames) 
    val dummy

    output:
    path "frames_stacked.tiff"

    script:
    """
    tiffcp ${frames} frames_stacked.tiff
    """
}

process convert_jpeg {
    label 'local'

    input:
    path(infile) 

    output:
    path "*.tiff"

    script:
    """
    magick ${infile} -colorspace Gray -compress lzw -set filename:basename "%[basename]" "%[filename:basename].tiff"
    """
}

workflow {
    // Handle 4 possible inputs:
    //    1. OME.TIFF (identified by companion.ome XML file) - need splitting into frame per tiff
    //    2. JPEG per frame - need converting into TIFFs
    //    3. Single TIFF - TIFF stack that needs splitting into frame per tiff
    //    4. Multiple TIFFs - already in 1 frame per tiff
    // The outcome of this input processing is to get a set of TIFFs with 1 per frame named
    // as frame_<frameindex>.tiff. This is stored in the channel allFiles and will be used
    // for all downstream analyses

    ome_companion = file("../Datasets/${params.dataset}/raw/*companion.ome*")
    jpegs = files("../Datasets/${params.dataset}/raw/*.{jpg,jpeg,JPG,JPEG}")
    tiffs = files("../Datasets/${params.dataset}/raw/*.{tif,tiff,TIF,TIFF}")
    if (!ome_companion.isEmpty()) {
        // OME that needs splitting into 1 tiff per frame
        // Obtain a list of all the frames in the dataset in the format:
        // (ome filename, ome frame index, overall frame index)
        xml1 = ome_get_filename(ome_companion)
            | splitText()
            | map( it -> it.trim())
            | map( it -> file("../Datasets/${params.dataset}/raw/" + it) )
        xml2 = ome_get_frame_t(ome_companion)
                | splitText()
                | map( it -> it.trim())
        xml3 = ome_get_global_t(ome_companion)
                | splitText()
                | map( it -> it.trim())
        separate = xml1
            | merge(xml2)
            | merge(xml3)
            | split_ome_frames
        frameFiles = separate.collect()
    } else if (!jpegs.isEmpty()) {
        // JPEGs need converting to TIFF
        frameFiles = convert_jpeg(channel.fromList(jpegs)).collect()
    } else if (tiffs.size() == 1) {
        // TIFF stack that needs splitting into 1 tiff per frame
        frameFiles = split_stacked_tiff(tiffs[0])
    } else if (tiffs.size() > 1) {
        frameFiles = channel.fromList(tiffs).collect()
    } else {
        // Fallback, shouldn't get here
        println "No image files found!"
        frameFiles = channel.empty()
    }

    // Rename all frames to standard frame_<frameid>.<ext>
    allFiles = rename_frames(frameFiles).flatten()

    // Segment all images and track
    segment_image(allFiles)
      | collect
      | track_images
      | parse_trackmate_xml

    // TODO parse into CSV and ROIs - use xpath?

    // QC step, filter on size and number of observations
    //trackmate_feats = filter_size_and_observations(track_images.out.features)

    //// Generate CellPhe features on each frame separately
    //// Then combine and add the summary features (density, velocity etc..., then time-series features)
    //static_feats = cellphe_frame_features_image(
    //    allFiles,
    //    trackmate_feats,
    //    track_images.out.rois
    //)
    //  | collect
    //  | combine_frame_features

    //finished = create_frame_summary_features(static_feats, trackmate_feats)
    //  | cellphe_time_series_features

    //create_tiff_stack(allFiles.collect(), finished)
}
