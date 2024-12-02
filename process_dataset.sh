ml load Python/3.11.5-GCCcore-13.2.0
ml load Nextflow/23.10.0
source ~/venvs/cellphe/bin/activate

nextflow run process_dataset.nf --dataset $1

deactivate

