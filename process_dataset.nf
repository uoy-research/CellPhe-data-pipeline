params.dataset = ''


def get_mask_fn(tif_fn) {
    return getParent(tif_fn) / 'masks' / getBaseName(tif_fn)
}


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
    maskFiles = allFiles.map({ x -> x.getParent().getParent() / 'masks' / x.getName() })
    both = allFiles.merge(maskFiles)
    both.view()
    segment_image(both)
}
