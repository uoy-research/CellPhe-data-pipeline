import groovy.json.JsonOutput
import java.nio.file.Paths
// Populated by params file
params.segmentation = ''
params.tracking = ''
params.QC = ''
params.folder_names = ''
params.run = ''
params.raw_dir = ''
params.output_dir = ''

// Folder paths
// TODO cellpose models need to be baked into the Apptainer image?
timelapse_id = ${params.folder_names.timelapse_id}
processed_dir = "${params.output_dir}/processed"
seg_dir = "${params.output_dir}/analysis/segmentation/${params.folder_names.segmentation}"
mask_dir = "${seg_dir}/masks/${timelapse_id}"
track_dir = "${seg_dir}/tracking/${params.folder_names.tracking}"
trackmate_dir = "${track_dir}/trackmate"
trackmate_outputs_dir = "${trackmate_dir}/${timelapse_id}"
cellphe_dir = "${track_dir}/cellphe"
cellphe_outputs_dir = "${cellphe_dir}/${timelapse_id}"

process segment_image {
    container "${params.segmentation.image}"
    publishDir "${mask_dir}", mode: 'copy'

    input:
    path input_fn

    output:
    path "*_mask.png"
 
    script:
    outName = input_fn.baseName 
    """
    segment_image.py ${input_fn} ${outName}_mask.png '${JsonOutput.toJson(params.segmentation.model)}' '${JsonOutput.toJson(params.segmentation.eval)}'
    """
}

process segment_image_gpu {
    container "${params.segmentation.image}"
    containerOptions '--nv'
    publishDir "${mask_dir}", mode: 'copy'

    input:
    path files

    output:
    path "*_mask.png"

    """
    segment_image_batch.py '${JsonOutput.toJson(params.segmentation.model)}' '${JsonOutput.toJson(params.segmentation.eval)}' '${files}'
    """
}

process save_segmentation_config {
    container 'ghcr.io/uoy-research/cellphe-jq:0.1.0'
    publishDir "${seg_dir}/config", mode: 'copy'
    label 'small'

    input:
    val config

    output:
    path "*.json"

    script:
    """
    jq <<< '${config}' '.' > "${timelapse_id}.json"
    """
}

process save_tracking_config {
    container 'ghcr.io/uoy-research/cellphe-jq:0.1.0'
    publishDir "${track_dir}/config", mode: 'copy'
    label 'small'

    input:
    val config

    output:
    path "*.json"

    script:
    """
    jq <<< '${config}' '.' > "${timelapse_id}.json"
    """
}


process segmentation_qc {
    container 'ghcr.io/uoy-research/cellphe-quarto:0.1.1'
    containerOptions '--env "XDG_CACHE_HOME=/tmp" --contain'
    publishDir "${seg_dir}/QC", mode: 'copy'

    input:
    path notebook
    path masks
    path images

    output:
    path "*.html"

    script:
    """
    quarto render ${notebook} -P masks:"${masks}" -P images:"${images}" -P highlight_method:"${params.QC.segmentation_highlight}" -o "${timelapse_id}.html"
    """
}

process track_images {
    container 'ghcr.io/uoy-research/cellphe-trackmate:0.1.1'
    containerOptions '-H /trackmate_libs'

    input:
    path mask_fns

    output:
    path "trackmate.xml"
 
    script:
    """
    mkdir -p masks
    mv *_mask.png masks
    track_images.py masks '$task.memory' '${JsonOutput.toJson(params.tracking)}' trackmate.xml
    """
}

process tracking_qc {
    container 'ghcr.io/uoy-research/cellphe-quarto:0.1.1'
    containerOptions '--env "XDG_CACHE_HOME=/tmp" --contain'
    publishDir "${track_dir}/QC", mode: 'copy'

    input:
    path notebook
    path trackmate_raw
    path trackmate_filtered

    output:
    path "*.html"

    script:
    """
    quarto render ${notebook} -P trackmate_fn:${trackmate_raw} -P trackmate_filtered_fn:${trackmate_filtered} -o "${timelapse_id}.html"
    """
}

process parse_trackmate_xml {
    container 'ghcr.io/uoy-research/cellphe-cellphepy:0.1.1'
    publishDir "${trackmate_outputs_dir}", mode: 'copy'

    input:
    path xml_file

    output:
    path "rois.zip", emit: rois, optional: true
    path "trackmate_features.csv", emit: features, optional: true

    script:
    """
    parse_xml.py ${xml_file} rois.zip trackmate_features.csv
    """
}

process filter_size_and_observations {
    container 'ghcr.io/uoy-research/cellphe-r:0.1.1'
    publishDir "${trackmate_outputs_dir}", mode: 'copy'

    input:
    path features_original

    output:
    path "trackmate_features_filtered.csv", arity: '1', optional: true

    """
    #!/usr/bin/env Rscript
    library(dplyr)
    df <- read.csv("${features_original}")
    feats <- df |>
        filter(
          AREA >= as.integer(${params.QC.minimum_cell_size})
        ) |>
        group_by(TRACK_ID) |>
        filter(n() >= as.integer(${params.QC.minimum_observations})) |>
        ungroup()
    if (nrow(feats) > 0) {
        write.csv(feats, "trackmate_features_filtered.csv", row.names=FALSE)
    }
    """
}

process cellphe_frame_features_image {
    container 'ghcr.io/uoy-research/cellphe-cellphepy:0.1.1'

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
    container 'ghcr.io/uoy-research/cellphe-linux-utils:0.1.1'

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
    container 'ghcr.io/uoy-research/cellphe-cellphepy:0.1.1'
    publishDir "${cellphe_outputs_dir}", mode: 'copy'

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
    container 'ghcr.io/uoy-research/cellphe-cellphepy:0.1.1'
    publishDir "${cellphe_outputs_dir}", mode: 'copy'

    input:
    path(frame_features) 

    output:
    path "time_series_features.csv", optional: true
 
    script:
    """
    time_series_features.py $frame_features time_series_features.csv
    """
}

process ome_get_global_t {
    container 'ghcr.io/uoy-research/cellphe-xpath:0.1.1'
    label 'small'

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
    container 'ghcr.io/uoy-research/cellphe-xpath:0.1.1'
    label 'small'

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
    container 'ghcr.io/uoy-research/cellphe-xpath:0.1.1'
    label 'small'

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
    container 'ghcr.io/uoy-research/cellphe-linux-utils:0.1.1'
    label 'small'

    input:
    tuple path(ome_fn), val(frame_index), val(global_frame_index)
    
    output:
    file('ome_split_*.tiff')

    script:
    """
    printf -v i "%05d" ${global_frame_index}
    tiffcp ${ome_fn},${frame_index} "ome_split_\${i}.tiff"
    """
}

process remove_spaces {
  container 'ghcr.io/uoy-research/cellphe-linux-utils:0.1.1'
  label 'small'

  input:
  path in_file

  output:
  file('*.{tif,tiff,TIF,TIFF}')

  script:
  """
  out_file=\$(echo ${in_file} | sed 's/ /_/g')
  mv $in_file \$out_file
  """
}

process rename_frames {
    container 'ghcr.io/uoy-research/cellphe-cellphepy:0.1.1'

    input:
    path in_files

    output:
    file('frame_*.tiff')

    """
    #!/usr/bin/env python

    import shutil
    from natsort import natsorted

    raw_fns = "${in_files}".split(" ")
    for i, raw_fn in enumerate(natsorted(raw_fns)):
        new_fn = f"frame_{i+1:05}.tiff"
        shutil.move(raw_fn, new_fn)
    """
}

process split_stacked_tiff {
    container 'ghcr.io/uoy-research/cellphe-linux-utils:0.1.1'

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
    container 'ghcr.io/uoy-research/cellphe-linux-utils:0.1.1'
    publishDir "${processed_dir}", mode: 'move'

    input:
    path(frames) 

    output:
    path "${timelapse_id}.zip"

    script:
    """
    zip "${timelapse_id}.zip" ${frames}
    """
}

process convert_jpeg {
    container 'ghcr.io/uoy-research/cellphe-linux-utils:0.1.1'
    label 'small'

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

    ome_companion = file("${params.raw_dir}/*companion.ome*")
    jpegs = files("${params.raw_dir}/*.{jpg,jpeg,JPG,JPEG}")
    tiffs = files("${params.raw_dir}/*.{tif,tiff,TIF,TIFF}")
    if (!ome_companion.isEmpty()) {
        // OME that needs splitting into 1 tiff per frame
        // Obtain a list of all the frames in the dataset in the format:
        // (ome filename, ome frame index, overall frame index)
        xml1 = ome_get_filename(ome_companion)
            | splitText()
            | map( it -> it.trim())
            | map( it -> file("${params.raw_dir}/" + it) )
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
        frameFiles = separate
    } else if (!jpegs.isEmpty()) {
        // JPEGs need converting to TIFF
        frameFiles = convert_jpeg(channel.fromList(jpegs))
    } else if (tiffs.size() == 1) {
        // TIFF stack that needs splitting into 1 tiff per frame
        frameFiles = split_stacked_tiff(tiffs[0]).flatten()
    } else if (tiffs.size() > 1) {
        frameFiles = channel.fromList(tiffs)
    } else {
        // Fallback, shouldn't get here
        println "No image files found!"
        frameFiles = channel.empty()
    }

    // Remove spaces as that messes up collecting
    // Then rename images to standard frame_XXXX.tiff format
    frameFiles
        .branch { f ->
            has_space: f.getBaseName().contains(" ")
            no_space: true
        }
        .set { filesBranched }

    allFiles = filesBranched.has_space
      | remove_spaces
      | concat(filesBranched.no_space)
      | collect
      | rename_frames
      | flatten

    if (params.run.segmentation) {

        // Save config
	save_segmentation_config(JsonOutput.toJson(['segmentation': params.segmentation]))

        // Segment all images and track
        // NB: if not specified otherwise, will segment in parallel across CPU cores
        // For GPU, this isn't feasible owing to longer queue times, so instead segment
        // every image in one batch
        if (params.segmentation.model.gpu) {
            masks = segment_image_gpu(allFiles.collect())
        } else {
            masks = segment_image(allFiles)
              | collect
        }
        segmentation_qc(
            file("${projectDir}/bin/segmentation_qc.qmd"),
            masks,
            allFiles.collect()
        )
        if (params.run.tracking) {

	    // Save config
	    save_tracking_config(JsonOutput.toJson(['tracking': params.tracking, 'QC': params.QC]))

            track_images(masks)
              | parse_trackmate_xml

            // QC step, filter on size and number of observations
            trackmate_feats = filter_size_and_observations(parse_trackmate_xml.out.features)
            // Hacky way of getting Nextflow to find the Quarto markdown, since it can't be run with
            // a shebang like all the other files in bin/
            tracking_qc(
                file("${projectDir}/bin/tracking_qc.qmd"),
                parse_trackmate_xml.out.features,
                trackmate_feats
            )
            if (params.run.cellphe) {

                // Generate CellPhe features on each frame separately
                // Then combine and add the summary features (density, velocity etc..., then time-series features)
                static_feats = cellphe_frame_features_image(
                    allFiles,
                    trackmate_feats,
                    parse_trackmate_xml.out.rois
                )
                  | collect
                  | combine_frame_features

                create_frame_summary_features(static_feats, trackmate_feats)
                  | cellphe_time_series_features
            }
        }
    }
    create_tiff_stack(allFiles.collect())
}
