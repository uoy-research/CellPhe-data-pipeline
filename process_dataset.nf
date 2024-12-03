params.dataset = ''


def get_mask_fn = { x -> x.getParent().getParent() / 'masks' / x.getName() }


process segment_image {
    executor 'slurm'
    cpus 1
    time '2 min'
    memory '4 GB'

    input:
    tuple path(input_fn, stageAs: "raw/*"), path(output_fn, stageAs: "masks/*")
 
    script:
    """
    segment_image.py $input_fn $output_fn
    """
}


workflow {
    allFiles = channel.fromPath("datasets/${params.dataset}/raw/*.tif*")
    maskFiles = allFiles.map(get_mask_fn)
    both = allFiles.merge(maskFiles)
    segment_image(both)
}
