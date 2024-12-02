params.dataset = ''


def get_mask_fn = { x -> x.getParent().getParent() / 'masks' / x.getBaseName() }


process segment_image {
    input:
    tuple path(input_fn, stageAs: "raw/*"), path(output_fn, stageAs: "masks/*")
 
    script:
    """
    segment_image.py $input_fn $output_fn
    """
}


workflow {
    allFiles = channel.fromPath("datasets/${params.dataset}/raw/*.tif")
    maskFiles = allFiles.map(get_mask_fn)
    allFiles
         .merge(maskFiles)
         .segment_image(both)
}
