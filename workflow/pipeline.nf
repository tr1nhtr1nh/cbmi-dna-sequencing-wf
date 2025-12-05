#!/usr/bin/env nextflow

params.VERSION = '1.0.0'

// create a pipe for download communication
process CREATE_DL_COM {
    tag 'CREATE_DL_COM'
    cpus 1
    memory '200 MB'

    container 'file://../images/blast.sif'
    shell '/usr/bin/bash'

    output:
    path ".dlCom.pipe"

    script:
    """
    rm -f .dlCom.pipe
    touch .dlCom.pipe
    """
}

// fetch accession information and estimate its size
process FETCH_ACCESSION_INFO {
    tag "$accession"
    maxForks 1
    cpus 1
    memory '200 MB'

    maxRetries 3
    
    container 'file://../images/sra-tools.sif'
    shell '/bin/bash'


    input:
    val accession   // accession ID for which information is to be fetched

    output:
    val accession   // same accession ID is passed through
    stdout          // estimated size of the accession based on the given estimation factor

    script:
    """
    accession_size=\$(${params.vdb_dump} $accession --info | grep size | awk -F': ' '{gsub(/,/,"",\$2); print \$2}')
    echo -n \$((accession_size * ${params.est_size_fact}))
    """
}

// fetch an accession, ensuring disk space is managed correctly
process FETCH_ACCESSION {
    tag "$accession"
    maxForks 1
    cpus 1
    memory '200 MB'

    errorStrategy { task.exitStatus == 28 ? 'ignore' : 'terminate'}
    maxRetries 3

    container 'file://../images/sra-tools.sif'
    shell '/bin/bash'


    input:
    val accession   // accession ID to be fetched
    val est_size    // estimated size of the accession
    path dl_com     // communication pipe for managing disk space

    output:
    path accession  // fetched accession file

    script:
    """
    get_reserved_space() {
        local sum_size=0
        declare -A downloaded_acc

        {
            flock -s 3

            while IFS=' ' read -r type accession size; do
                if [[ \$type == "D" ]]; then
                    downloaded_acc["\$accession"]=\$size
                elif [[ \$type == "C" ]]; then
                    unset downloaded_acc["\$accession"]
                fi
            done < "${dl_com}"
        
        } 3< ${dl_com}

        for accession in "\${!downloaded_acc[@]}"; do
            sum_size=\$((sum_size + downloaded_acc["\$accession"]))
        done

        echo \$sum_size
    }

    get_used_space() {
        local used_space=\$(du -b -s ${workflow.workDir} | awk '{printf "%s", \$1}')
        local reserved_space=\$(get_reserved_space)
        echo \$((used_space + reserved_space))
    }

    wait_for_change() {
        if [ ${params.file_mode} == 'event' ]; then
            inotifywait -r --exclude '/\\.' -e modify,delete ${workflow.workDir} | while read -r directory event filename; do
                break
            done
        else
            sleep ${params.pull_interval}
        fi
    }

    used_storagespace=\$(get_used_space)

    if [ ${est_size} -gt ${params.max_disk_usage} ]; then
        echo "Estimated Accession (${accession}) size is greater than params.max_disk_usage. Abort Process." && exit 28
    fi

    while [ \$((used_storagespace + ${est_size})) -gt ${params.max_disk_usage} ]; do
        \$(wait_for_change)
        used_storagespace=\$(get_used_space)
    done

    ${params.prefetch} --max-size ${params.max_disk_usage} ${accession}
    flock -x ${dl_com} echo 'D ${accession} ${est_size}' >> ${dl_com}
    """
}

// convert fetched accession data into FASTQ format
// update: create stats.csv to store evaluate.py results
process FASTERQ {
    tag "$accession"
    maxForks 2
    cpus 1
    memory '1 GB'

    container 'file://../images/sra-tools.sif'
    shell '/bin/bash'


    input:
    path accession              // fetched accession file
    path dl_com                 // communication pipe for managing disk space

    output:
    path "${accession}_fastq"   // generated FASTQ files from the accession
    path "stats.csv"

    script:
    """
    ${params.fasterq_dump} ${accession} -O ${accession}_fastq
    rm -r \$(readlink ${accession})
    rm -r ${accession}
    flock -x ${dl_com} echo 'C ${accession}' >> ${dl_com}
    touch stats.csv
    """
}

// map FASTQ files against a reference database using BWA-MEM2
process MAPPING {
    tag "${fastq.baseName.replace('_fastq','')}"
    maxForks 1
    cpus params.cpu.mapping
    memory { params.mem.mapping * task.attempt }

    errorStrategy { task.exitStatus in 137..140 ? 'retry' : 'terminate' }
    maxRetries 3

    container 'file://../images/bwa-mem.sif'
    shell '/bin/bash'
    
    input:
    path mapping_databases  // Reference databases for mapping
    val index_files         // Index files associated with the reference databases
    path fastq              // Path to the FASTQ files to be mapped
    path stats

    output:
    path fastq              // Path to the modified FASTQ files
    path stats


    // Update: use samtools 
    // Alternative without samtools: awk '($2 & 4) != 0' input.sam > unmapped.sam
    // move stats.csv to work dir (maybe output channel), so it does not append
    // samtools -f 12 (read unmapped + mate unmapped)
    script:
    """
    databases=(\$(echo "${mapping_databases}" | tr " " "\n"))
    file_names=(\$(echo "${index_files}" | sed "s/^\\[\\(.*\\)\\]\$/\\1/" | sed -e "s/, */,/g" | tr "," "\n"))
    for i in "\${!databases[@]}"; do
        fastq_files=\$(ls ${fastq}/*.fastq)
        echo "ALIGNMENT: Start aligning reads to a reference genome: ${index_files}..."
        ${params.bwa} mem -t ${task.cpus} \${databases[i]}/\${file_names[i]} \$fastq_files > aln.sam
        echo "FILTER: Start filtering aligned sam file..."
        # samtools view -f 4 -h aln.sam > unmapped.sam
        python3 ${workflow.projectDir}/templates/evaluate.py mapping aln.sam ${fastq} -o ${stats} --keep-files
    done
    """
}

// run Kraken2 on FASTQ files for taxonomic classification
// Discuss which data format is needed
// Add filtering options: kraken2 --threads ${task.cpus} --db \$database --paired --unclassified-out \$fastq_files  > results.txt 
process KRAKEN {
    tag "${fastq.baseName.replace('_fastq','')}"
    maxForks 1
    cpus params.cpu.kraken
    memory { params.mem.kraken * task.attempt }

    errorStrategy { task.exitStatus in 137..140 ? 'retry' : 'terminate' }
    maxRetries 3

    container 'file://../images/kraken.sif'
    shell '/bin/bash'
    
    input:
    path kraken2_database   // Kraken2 database for classification
    path fastq              // Path to the FASTQ files for Kraken2 classification
    path stats

    output:
    path fastq              // Path to the modified FASTQ files
    path stats

    script:
    """
    databases=(\$(echo "${kraken2_database}" | tr " " "\n"))
    for database in "\${databases[@]}"; do
        fastq_files=\$(ls ${fastq}/*.fastq)
        count=\$(ls ${fastq}/*.fastq | wc -l )

        if [[ \$count -gt 1 ]]; then
            kraken2 --threads ${task.cpus} --db \$database --paired \$fastq_files > results.txt
        else
            kraken2 --threads ${task.cpus} --db \$database \$fastq_files > results.txt
        fi

        python3 ${workflow.projectDir}/templates/evaluate.py kraken results.txt ${fastq} -o ${stats}
    done
    """
}

// run BLASTX on FASTQ files for protein sequence similarity search
process BLAST_X {
    tag "${fastq.baseName.replace('_fastq','')}"
    maxForks 1
    cpus params.cpu.blastx
    memory { params.mem.blastx * task.attempt }

    errorStrategy { task.exitStatus in 137..140 ? 'retry' : 'terminate' }
    maxRetries 3

    container 'file://../images/diamond.sif'
    shell '/bin/bash'

    input:
    path blastx_database                // BLASTX database for similarity search (needs protein db as file, which is of type *.faa)
    val db_names                        // Names of the BLASTX database files
    path fastq                          // Path to the FASTQ files for BLASTX processing
    path stats

    output:
    path fastq                          // Path to the modified FASTQ files
    path stats

    script:
    """
    databases=(\$(echo ${blastx_database} | tr " " "\n"))
    file_names=(\$(echo "${db_names}" | sed "s/^\\[\\(.*\\)\\]\$/\\1/" | sed -e "s/, */,/g" | tr "," "\n"))
    for i in "\${!databases[@]}"; do
        for fastq_file in ${fastq}/*.fastq; do
            diamond blastx -d \${databases[i]}/\${file_names[i]} -q \$fastq_file --very-sensitive --outfmt 6 qseqid -p ${task.cpus} --out result.txt
            python3 ${workflow.projectDir}/templates/evaluate.py blastx result.txt ${fastq} -o ${stats} --keep-files
        done
    done
    """
}

// run BLASTN on FASTQ files for nucleotide sequence similarity search
process BLAST_N {
    tag "${fastq.baseName.replace('_fastq','')}"
    maxForks 1
    cpus params.cpu.blastn
    memory { params.mem.blastn * task.attempt }

    errorStrategy { task.exitStatus in 137..140 ? 'retry' : 'terminate' }
    maxRetries 3

    container 'file://../images/blast.sif'
    shell '/bin/bash'
    
    input:
    path blastn_database    // BLASTN database for similarity search
    val db_names            // Names of the BLASTN database files
    path fastq              // Path to the FASTQ files for BLASTN processing
    path stats

    output:
    path fastq              // Path to the modified FASTQ files
    path stats

    /*
        Info in line calling blastn -db ... : You're directory structure might look different. 
        Make sure you're setting the correct path relative from the nextflow project directory to the blast databases.
        The project directory is the folder where the main *.nf Nextflow file resides.
    */

    script:
    """
    databases=(\$(echo ${blastn_database} | tr " " "\n"))
    file_names=(\$(echo "${db_names}" | sed "s/^\\[\\(.*\\)\\]\$/\\1/" | sed -e "s/, */,/g" | tr "," "\n"))
    for i in "\${!databases[@]}"; do
        echo "Starting Basic Local Alignment Search Tool on ${workflow.projectDir}/refseq/\${databases[i]}/\${file_names[i]} database ..."
        for fastq_file in ${fastq}/*.fastq; do
            sed -n '1~4s/^@/>/p;2~4p' \$fastq_file > acc.fasta
            blastn -db ${workflow.projectDir}/refseq/\${databases[i]}/\${file_names[i]} -outfmt "7 qseqid sseqid pident length evalue bitscore" -num_threads ${task.cpus} -query acc.fasta -out result.txt
            #rm acc.fasta
            python3 ${workflow.projectDir}/templates/evaluate.py blastn result.txt ${fastq} -o ${stats} --keep-files
        done
    done
    """
}



process READSEEKER {
    tag "${fastq.baseName.replace('_fastq','')}"
    maxForks 1
    cpus params.cpu.readseeker
    memory { params.mem.readseeker * task.attempt }

    errorStrategy { task.exitStatus in 137..140 ? 'retry' : 'terminate' }
    maxRetries 3

    container "file://ReadSeekerWrapper/readseeker_fastq.sif"
    shell '/usr/bin/bash'

    /*
        containerOptions: Need to bind multiple dirs, because 
        we have symlink to project dir on /data/ and 
        huggingface download stores data on /home/ dir...
    */

    containerOptions '-B /data/,/home/:/home'

    input:
    path fastq
    path stats

    output:
    path fastq
    path stats

    script:
    """
    for fastq_file in ${fastq}/*.fastq; do
        python3 ${workflow.projectDir}/ReadSeekerWrapper/Readseeker_fastq.py -q \$fastq_file -o preds.txt        
        python3 ${workflow.projectDir}/templates/evaluate.py readseeker preds.txt ${fastq} -t ${params.readseeker.threshold} -o ${stats} --keep-files
    done
    """
}



// Todo: use samtools to create bam files ?

// compress the results into a tar.gz archive
process COMPRESS_RESULTS {
    tag "${fastq.baseName.replace('_fastq','')}"
    maxForks 1
    cpus 1
    memory '200 MB'

    container 'file://../images/blast.sif'
    shell '/usr/bin/bash'

    // publishDir params.output, mode: 'copy'      // BUG: this just moves a symlink to the output folder. It's broken, because the original fastq files are being deleted 
    
    publishDir {
        def name = fastq.getBaseName()
        def match = (name =~ /(SRR\d+)/)
        def accession = match ? match[0][1] : name
        return "data/${accession}"
    }, mode: 'move'
    
    input:
    path fastq                                  // Path to the FASTQ files to be compressed
    path stats

    output:
    path "${fastq}.tar.gz"                      // A compressed tar.gz archive of the FASTQ files
    path stats

    script:
    """
    tar --use-compress-program="pigz " -cf ${fastq}.tar.gz ${fastq}/*
    rm -r ${fastq}
    """
}

// extracting name of the parent dir
def get_parent_name(files) {
    def parent_dirs = []
    files.each { filename ->
        File f = new File(filename)
        parent_dirs.add(f.getParentFile().toString())
    }
    return parent_dirs
}

// extracting file name of a path
def get_name(files) {
    def names = []
    files.each { filename ->
        File f = new File(filename)
        names.add(f.getName().toString())
    }
    return names
}

// workflow definition
workflow {

    if ( params.help ) {
        help = """pipeline.nf: This pipeline processes DNA sequencing data through a series of steps
                |                including fetching accession data, converting to FASTQ format, mapping
                |                sequences to reference databases and performing taxonomic classification.
                |                Use --help command to view all available options and their defaults.
                |Arguments:
                |  --input_file        Location of the input file file.
                |                      [default: ${params.input_file}]
                |  --output            Location of the output directory.
                |                      [default: ${params.output}]
                |  --max_disk_usage    Specifies the maximum amount of disk space (in bytes) the application may use.
                |                      [default: ${params.max_disk_usage}]
                |  --file_mode         Defines when the application should check the available disk space. The options are 'event' or 'pull'.
                |                      The 'event' mode monitors all files and only checks the available memory when changes are made. The 'pull'
                |                      mode checks the memory at regular intervals. The 'pull' mode is recommended when using NFS file systems.
                |                      [default: ${params.file_mode}]
                |  --pull_interval     Defines the interval for the disk space check. Only used when --file_mode = 'pull'.
                |                      [default: ${params.pull_interval}]
                |  --est_size_fact     Estimated factor of how much more storage space is required for each Accession.
                |                      [default: ${params.est_size_fact}]
                |  --prefetch          Location of the prefetch tool, that is part of the SRA Toolkit.
                |                      [default: ${params.prefetch}]
                |  --fasterq_dump      Location of the fasterq-dump tool, that is part of the SRA Toolkit.
                |                      [default: ${params.fasterq_dump}]
                |  --vdb_dump          Location of the vdb-dump tool, that is part of the SRA Toolkit.
                |                      [default: ${params.vdb_dump}]
                |  --bwa               Location of the BWA-MEM2 tool.
                |                      [default: ${params.bwa}]""".stripMargin()
        println(help)
        exit(0)
    }

    log.info """\
            DNA-Sequencing-Workflow v${params.VERSION}
            ==========================
            input from   : ${params.input_file}
            output to    : ${params.output}
            --
            run as       : ${workflow.commandLine}
            started at   : ${workflow.start}
            config files : ${workflow.configFiles}
            """
            .stripIndent()

    // setup
    channel
        .fromPath(params.input_file)
        .splitCsv()
        .flatten()
        .set { ch_accession_list }
    
    dl_com = CREATE_DL_COM()

    // fetch the sequencing data
    ch_accession_info = FETCH_ACCESSION_INFO(ch_accession_list)
    ch_accession = FETCH_ACCESSION(ch_accession_info, dl_com)
    ch_fastq = FASTERQ(ch_accession, dl_com)

    // analyse the sequencing data
    ch_mapping = params.skip_mapping ? ch_fastq : MAPPING(get_parent_name(params.mapping_database), get_name(params.mapping_database), ch_fastq)
    ch_kraken = params.skip_kraken ? ch_mapping : KRAKEN(params.kraken2_database, ch_mapping)
    ch_blastx = params.skip_blastx ? ch_kraken : BLAST_X(get_parent_name(params.blastx_database), get_name(params.blastx_database), ch_kraken)
    ch_blastn = params.skip_blastn ? ch_blastx : BLAST_N(get_parent_name(params.blastn_database), get_name(params.blastn_database), ch_blastx)
    COMPRESS_RESULTS(ch_blastn)
}
