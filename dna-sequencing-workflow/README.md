# DNA sequencing workflow

This Nextflow-based pipeline is designed to process DNA sequencing data through various bioinformatics tools and identify those sequences that cannot be detected by conventional methods. The pipeline automates the retrieval, conversion, mapping, classification, and analysis of sequencing data. It is containerized, ensuring reproducibility and ease of deployment across different environments. The pipeline also includes mechanisms for managing disk space and handling errors, making it robust and adaptable for a wide range of sequencing analysis tasks.


## Features

- **Automated Workflow:** Fetches sequencing data, converts it to FASTQ format, performs mapping, taxonomic classification, and sequence similarity searches.
- **Disk Space Management:** Monitors and controls disk usage during execution to prevent exceeding specified limits.
- **Containerized Tools:** Utilizes containerized bioinformatics tools (e.g., SRA Toolkit, BWA-MEM2, Kraken2) to ensure consistency across environments.
- **Modular Design:** Each analysis step is encapsulated in a separate process, allowing easy customization and extension.
- **Error Handling:** Includes retry mechanisms and strategies to handle potential errors during execution.

## Installation

1. **Install Nextflow:** Ensure that Nextflow is installed on your system. [Nextflow installation instructions](https://www.nextflow.io/docs/latest/install.html)

2. **Install Singularity (Optional):** If you plan to use Singularity containers, install Singularity following the instructions [here](https://docs.sylabs.io/guides/latest/admin-guide/installation.html).

3. **Clone the Repository:**
```
git clone https://gitlab.rz.htw-berlin.de/s0574698/dna-sequencing-workflow.git
cd dna-sequencing-workflow
```

### Singularity

Optionally, it is possible to run the processes in a singularity container. The definition files required to build these images are included in the images directory of the project. To use Singularity, you need to build the images as follows:

```
cd images
```

Build each Singularity image using the definition files provided. For example:
```
singularity build --fakeroot sra-tools.sif sra-tools.def
singularity build --fakeroot bwa-mem.sif bwa-mem.def
singularity build --fakeroot kraken.sif kraken.def
singularity build --fakeroot diamond.sif diamond.def
singularity build --fakeroot blast.sif blast.def
```

## Usage

To run the pipeline, use the following command:

```
nextflow run pipeline.nf --input_file <input_file> --output <output_directory> [other options]
```

## Reference Databases

The pipeline uses several reference databases for various analysis steps. These databases need to be specified in the configuration file (nextflow.config). You can always specify multiple databases, and the pipeline will map the FASTQ files against each one. The paths to these databases should be adjusted according to your environment:

- **Mapping Database (params.mapping_database):** A list of directories containing the reference databases for sequence mapping using BWA-MEM2. 

- **Kraken2 Database (params.kraken2_database):** A list of directories containing the Kraken2 database used for taxonomic classification.

- **BLASTX Database (params.blastx_database):** A list of directories containing the protein sequence databases used for BLASTX similarity searches.

- **BLASTN Database (params.blastn_database):** A list of directories containing the nucleotide sequence databases used for BLASTN similarity searches.

## Command-Line Options

- **--input_file:** Path to the input file containing the list of accession numbers.
- **--output:** Path to the output directory where results will be stored.
- **--max_disk_usage:** Maximum allowed disk space usage (in bytes) during pipeline execution.
- **--file_mode:** Disk space monitoring mode ('event' or 'pull').
- **--pull_interval:** Interval for disk space checks when file_mode is set to 'pull'.
- **--est_size_fact:** Estimated factor for calculating additional storage space needed per accession.
- **--prefetch:** Path to the prefetch tool from the SRA Toolkit.
- **--fasterq_dump:** Path to the fasterq-dump tool from the SRA Toolkit.
- **--vdb_dump:** Path to the vdb-dump tool from the SRA Toolkit.

### Input File

The input file for this pipeline should contain a list of accession numbers (SRA), one per line. These accession numbers correspond to the sequencing files you want to retrieve and process.

Example Input File (accessions.txt):
```
SRR1234567
SRR2345678
SRR3456789
SRR4567890
```

In this example:

- SRR1234567 is the accession number for the first sequencing file.
- SRR2345678 is the accession number for the second file.
- And so on.

### Example Command

```
nextflow run pipeline.nf --input_file accessions.txt --output results/ --max_disk_usage 500000000000
```

This command will process the accession numbers listed in accessions.txt, performing all analysis steps, and storing the results in the results/ directory, while ensuring that disk usage does not exceed 500 GB.


## Configuration File

The pipeline can be configured using a Nextflow configuration file (nextflow.config). This file allows you to set default parameters and define different execution profiles.

- **Input/Output Paths:**
    - **params.input_file:** Default path to the input file.
    - **params.output:** Default path to the output directory.

- **Resource Management:**
    - **params.max_disk_usage:** Maximum disk space allowed during execution.
    - **params.cpu.mapping**, **params.cpu.kraken**, etc.: CPU allocations for different processes.
    - **params.mem.mapping**, **params.mem.kraken**, etc.: Memory allocations for different processes.

- **Container Management:**
    - **singularity.enabled:** Controls whether Singularity is used (true or false).
    - **singularity.autoMounts:** Automatically mount necessary paths inside the container.

- **Skip Processes:**
    - **params.skip_mapping, params.skip_kraken**, etc.: Boolean flags to skip specific steps in the pipeline. Set to `true` if you want to skip the corresponding analysis step.

- **Execution Profiles:**
    - **standard:** Runs processes locally with caching enabled.
    - **cluster:** Configures the pipeline to run on a SLURM cluster with lenient caching.

You can switch between profiles and customize the pipeline behavior by modifying the nextflow.config file or by passing parameters directly via the command line.

## Troubleshooting

- **Memory Issues:** If the pipeline runs out of memory, consider increasing the memory parameter for the affected processes.
- **Disk Space Issues:** Adjust `--max_disk_usage` or clean up unnecessary files in the working directory to free up space.

## License

This project is licensed under the MIT License. See the LICENSE file for details.

