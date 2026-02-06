#!/usr/bin/env nextflow

params.VERSION = '1.0.1'

// create a pipe for download communication
process CREATE_DL_COM {
    tag 'CREATE_DL_COM'
    cpus 1
    memory '200 MB'
    cache false
    stageInMode "symlink"

    container "file://${workflow.projectDir}/../images/dummy.sif"
    shell "/usr/bin/env bash"

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
    cpus 1
    memory '200 MB'

    maxRetries 3
    
    container "file://${workflow.projectDir}/../images/sra-tools.sif"
    shell "/bin/bash"

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

process WATCH_STORAGE {
    tag "$accession"
    cpus 1
    memory '200 MB'
    maxForks 1
    cache false
    stageInMode "symlink"

    maxRetries 3
    errorStrategy { task.exitStatus == 28 ? 'ignore' : 'terminate'}

    container "file://${workflow.projectDir}/../images/sra-tools.sif"
    shell "/bin/bash"

    input:
    val accession   // accession ID
    val est_size    // estimated size of the accession
    path dl_com      // communication pipe path for managing disk space (staged path)


    output:
    val accession   // accession ID passed through
    val est_size    // estimated size passed through

    script:
    """
    get_reserved_space() {
        local sum_size=0
        declare -A downloaded_acc

        {
            flock -s 3

            while IFS=' ' read -r type accession size; do
                if [[ \$type == "D" ]]; then
                    if [ ! -e "${workflow.workDir}/\$accession" ]; then
                        downloaded_acc["\$accession"]=\$size
                    fi
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
        echo \$((used_storagespace + ${est_size})) -gt ${params.max_disk_usage}
        echo ${est_size}
        \$(wait_for_change)
        used_storagespace=\$(get_used_space)
    done
    """
}


process FETCH_ACCESSION {
    tag "$accession"
    cpus 1
    memory '200 MB'

    cache 'lenient'
    maxRetries 3

    container "file://${workflow.projectDir}/../images/sra-tools.sif"
    shell "/bin/bash"

    input:
    val accession   // accession ID to be fetched
    val est_size    // estimated size of the accession

    output:
    path accession  // fetched accession file

    script:
    """
    ${params.prefetch} --max-size ${params.max_disk_usage} ${accession}
    """
}

// register the downloaded accession in the communication file
process UPDATE_DL_COM {
    cache false
    tag "$accession_id"
    cpus 1
    memory '200 MB'
    stageInMode "symlink"

    container "file://${workflow.projectDir}/../images/sra-tools.sif"
    shell "/bin/bash"

    input:
    path accession      // fetched accession file
    val accession_id    // accession ID that was downloaded
    val est_size        // estimated size of the accession
    val dl_com_path     // communication pipe path for managing disk space

    output:
    path accession      // pass through accession file path
    val accession_id    // pass through accession ID
    val est_size        // pass through estimated size
    val(true)

        script:
        """
        (
            flock -x 200
            if awk -v acc="${accession_id}" '(\$1=="D"||\$1=="C") && \$2==acc{exit 0} END{exit 1}' "${dl_com_path}"; then
                echo "Already registered ${accession_id}"
            else
                echo "D ${accession_id} ${est_size}" >> "${dl_com_path}"
            fi
        ) 200>> "${dl_com_path}"
        """
}


// convert fetched accession data into FASTQ format
process FASTERQ {
    tag "$accession"
    cpus 4
    memory '8 GB'

    container "file://${workflow.projectDir}/../images/sra-tools.sif"
    shell "/bin/bash"

    input:
    path accession              // accession ID (string)
    val update_done             // wait for UPDATE_DL_COM to write into .dlCom.pipe 

    output:
    path "${accession}_fastq"   // generated FASTQ files from the accession
    path "stats.csv"            // stats file
    path "readscount.csv"       // readscount file

    script:
    """
    fastq="${accession}_fastq"
    ${params.fasterq_dump} ${accession} -O \$fastq
    touch stats.csv
    echo "raw, \$(( \$(wc -l < \$fastq/*_1.fastq) / 4))" > readscount.csv
    """
}

process MARK_CONVERSION {
    tag "$accession_id"
    cpus 1
    memory '200 MB'
    cache false
    stageInMode "symlink"

    container "file://${workflow.projectDir}/../images/sra-tools.sif"
    shell "/bin/bash"

    input:
    path fastq
    path stats
    path readscount
    val accession_id    // accession ID
    path dl_com         // communication pipe path for managing disk space
    path sra_files      // Path to prefetched .sra file for deletion

    script:
    """
    (
        flock -x 200
        if awk -v acc="${accession_id}" '(\$1=="D"||\$1=="C") && \$2==acc{exit 0} END{exit 1}' "${dl_com}"; then
            echo "Already registered ${accession_id}"
        else
            echo "C ${accession_id}" >> "${dl_com}"
        fi
    ) 200>> "${dl_com}"
#    Uncomment "rm -r ... " line if you want to free storage. This forces FETCH_ACCESSION to rerun
#    Only uncomment when you don't need NF caching
#    Enable caching                : set StageInMode = "copy" in nextflow.config
#    Disable caching + save storage: set StageInMode = "symlink"

#    rm -r \$(readlink ${sra_files})
    """
}


process MAPPING {
    tag "${fastq.baseName.replace('_fastq','')}"
    maxForks 1
    cpus params.cpu.mapping
    memory { params.mem.mapping * task.attempt }

    errorStrategy { task.exitStatus in 137..140 ? 'retry' : 'terminate' }
    maxRetries 3

    container "file://${workflow.projectDir}/../images/bwa-mem.sif"
    containerOptions "-B /data/"
    shell "/bin/bash"
    
    input:
    val mapping_databases  // Reference databases for mapping
    val index_files         // Index files associated with the reference databases
    path fastq              // Path to the FASTQ files to be mapped
    path stats
    path readcount

    output:
    path fastq              // Path to the modified FASTQ files
    path stats
    path readcount

    script:
    """
    set -euo pipefail

    databases=(\$(echo "${mapping_databases}" | tr -d '[],' | tr " " "\n"))
    file_names=(\$(echo "${index_files}" | sed "s/^\\[\\(.*\\)\\]\$/\\1/" | sed -e "s/, */,/g" | tr "," "\n"))
    for i in "\${!databases[@]}"; do
        fastq_files=\$(ls ${fastq}/*.fastq)
        ${params.bwa} mem -t ${task.cpus} \${databases[i]}/\${file_names[i]} \$fastq_files > aln.sam
#        samtools view -f 4 -h aln.sam > unmapped.sam
        evaluate mapping aln.sam ${fastq} -o ${stats} --keep-files
    done
    echo "mapping, \$(( \$(wc -l < ${fastq}/*_1.fastq) / 4 ))" >> ${readcount}
    """
}

// run Kraken2 on FASTQ files for taxonomic classification
// Discuss which data format is needed
// Add filtering options: kraken2 --threads ${task.cpus} --db \$database --paired --unclassified-out \$fastq_files  > results.txt 
process KRAKEN {
    tag "${fastq.baseName.replace('_fastq','')}"
    maxForks 1
    cpus params.cpu.kraken
    memory params.mem.kraken
    // stageInMode {workflow.resume ? 'copy': 'symlink'} 

    errorStrategy { task.exitStatus in 137..140 ? 'retry' : 'terminate' }
    maxRetries 3

    container "file://${workflow.projectDir}/../images/kraken.sif"
    containerOptions "-B /data/"
    shell "/bin/bash"

    input:
    val kraken2_database    // Kraken2 database for classification
    path fastq              // Path to the FASTQ files for Kraken2 classification
    path stats
    path readcount

    output:
    path fastq              // Path to the modified FASTQ files
    path stats
    path readcount

    script:
    """
    set -euo pipefail

    databases=(\$(echo "${kraken2_database}" | tr -d '[](),"' | tr " " "\n"))
    for database in "\${databases[@]}"; do
        fastq_files=\$(ls ${fastq}/*.fastq)
        count=\$(ls ${fastq}/*.fastq | wc -l )

        if [[ \$count -gt 1 ]]; then
            kraken2 --db \$database --paired \$fastq_files --threads ${task.cpus} --quick --out out-kraken2.txt
        else
            kraken2 --db \$database \$fastq_files --threads ${task.cpus} --out out-kraken2.txt
        fi

        evaluate kraken out-kraken2.txt ${fastq} -o ${stats} --keep-files
    done
    echo "kraken2, \$(( \$(wc -l < ${fastq}/*_1.fastq) / 4 ))" >> ${readcount}
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

    container "file://${workflow.projectDir}/../images/diamond.sif"
    containerOptions "-B /data/"
    shell "/bin/bash"

    input:
    val blastx_database
    val db_names
    path fastq
    path stats
    path readcount

    output:
    path fastq      // Path to the modified FASTQ files
    path stats
    path readcount
    val(true)       // reference: https://nextflow-io.github.io/patterns/state-dependency/

    script:
    """
    set -euo pipefail

    databases=(\$(echo ${blastx_database} | tr -d '[],' | tr " " "\n"))
    file_names=(\$(echo "${db_names}" | sed "s/^\\[\\(.*\\)\\]\$/\\1/" | sed -e "s/, */,/g" | tr "," "\n"))
    for i in "\${!databases[@]}"; do
        for fastq_file in ${fastq}/*.fastq; do
            suffix=\$(basename "\${fastq_file##*_}" .fastq)
            diamond blastx -d \${databases[i]}/\${file_names[i]} -q \$fastq_file --very-sensitive --outfmt 6 qseqid sseqid pident length evalue bitscore -p ${task.cpus} --out out-diamond-\$suffix.txt
            evaluate blastx out-diamond-\$suffix.txt ${fastq} -o ${stats} --keep-files
        done
    done
    echo "diamond, \$(( \$(wc -l < ${fastq}/*_1.fastq) / 4 ))" >> ${readcount}
    """
}

process BLAST_N {
    tag "${fastq.baseName.replace('_fastq','')}"
    maxForks 1
    cpus params.cpu.blastn
    memory params.mem.blastn

    errorStrategy { task.exitStatus in 137..140 ? 'retry' : 'terminate' }
    maxRetries 3

    container "file://${workflow.projectDir}/../images/blast.sif"
    containerOptions "-B /data/"
    shell "/bin/bash"

    input:
    val blastn_database
    val db_names
    path fastq
    path stats
    path readcount
    val mutex               // Collect mutex object from prior process

    output:
    path fastq              // Path to the modified FASTQ files
    path stats
    path readcount
    val mutex               // Emit mutex object to next process

    /*
        Info in line calling blastn -db ... : You're directory structure might look different. 
        Make sure you're setting the correct path relative from the nextflow project directory to the blast databases.
        The project directory is the folder where the main *.nf Nextflow file resides.
    */

    script:
    /*
        BlastN Warning: [blastn] Examining 5 or more matches is recommended for -max_targets_seq 1: update to 5
        Notice: this code only works with fragmented databases. If you want to use custom 
    */    
    """
    set -euo pipefail

    databases=(\$(echo "${blastn_database}" | tr -d '[],' | tr " " "\n"))
    file_names=(\$(echo "${db_names}" | sed "s/^\\[\\(.*\\)\\]\$/\\1/" | sed -e "s/, */,/g" | tr "," "\n"))
    for i in "\${!databases[@]}"; do
        for fastq_file in ${fastq}/*.fastq; do
            suffix=\$(basename "\${fastq_file##*_}" .fastq)

#            for robust analysis we run blast on a custom database, which is not fragmented
#            sed -n '1~4s/^@/>/p;2~4p' \$fastq_file > acc.fasta
#            blastn -db \${databases[i]}/\$file_names -max_target_seqs 1 -outfmt "6 qseqid sseqid pident length evalue bitscore" -num_threads ${task.cpus} -query acc.fasta >> out-blastn-\$suffix.txt

#           it we run nf-test only take two fragments from nt collection for speed
            if [[ ${workflow.configFiles.size()} -ne 1 ]]; then
                num_fragments=2
            else
                num_fragments=\$(( \$(ls \${databases[i]}/nt.* | grep -oP 'nt\\.\\d+' | sort -u | wc -l) - 1 ))
            fi

            echo "number of database fragments: \$num_fragments"
            for j in \$(seq 0 \$num_fragments); do
                db=\$(printf "nt.%03d" "\$j")
                echo "Running BLAST \$db partition on \$fastq_file"

                sed -n '1~4s/^@/>/p;2~4p' \$fastq_file > acc.fasta

                blastn -db \${databases[i]}/\$db -max_target_seqs 1 -evalue 1e-5 \
                    -outfmt "6 qseqid sseqid pident length evalue bitscore" \
                    -num_threads ${task.cpus} -query acc.fasta >> out-blastn-\$suffix.txt

                evaluate blastn out-blastn-\$suffix.txt ${fastq} -o ${stats} --keep-files
            done
        done
    done
    echo "blastn, \$(( \$(wc -l < ${fastq}/*_1.fastq) / 4 ))" >> ${readcount}
    """
}

process READSEEKER {
    tag "${fastq.baseName.replace('_fastq','')}"
    maxForks 1
    cpus params.cpu.readseeker
    memory { params.mem.readseeker * task.attempt }

    errorStrategy { task.exitStatus in 137..140 ? 'retry' : 'terminate' }
    maxRetries 3

    container "file://${workflow.projectDir}/ReadSeekerWrapper/readseeker_fastq.sif"
    containerOptions "-B /data/,/home/:/home/"
    shell "/usr/bin/bash"

    input:
    path fastq
    path stats
    path readcount
    val mutex

    output:
    path fastq
    path stats
    path readcount

    script:
    """
    set -euo pipefail

    for fastq_file in ${fastq}/*.fastq; do
        readseeker_fastq -q \$fastq_file -o preds.txt
        evaluate readseeker preds.txt ${fastq} -t ${params.readseeker.threshold} -o ${stats} --keep-files
    done
    echo "readseeker, \$(( \$(wc -l < ${fastq}/*_1.fastq) / 4 ))" >> ${readcount}
    """
}

process NN_CLASSIFIER {
    tag "${fastq.baseName.replace('_fastq','')}"
    maxForks 2 // not all cpus are used: for one job around 30 cpus are occupied => a second job fits in ... 
    cpus params.cpu.nn_cls
    memory params.mem.nn_cls 

    errorStrategy { task.exitStatus in 137..140 ? 'retry' : 'terminate' }
    maxRetries 3
    

    container "file://${workflow.projectDir}/../images/nn.sif"
    containerOptions "-B /data/,/home/:/home/"
    shell "/usr/bin/bash"

    input:
    path fastq
    path stats
    path readcount

    output:
    path fastq
    path stats
    path readcount

    script:
    """
    set -euo pipefail

    for fastq_file in ${fastq}/*.fastq; do
        filename=\$(basename \$fastq_file)
        filename=\${filename%%.*}
        sed -n '1~4s/^@/>/p;2~4p' \$fastq_file > \$filename.fasta
        classification --input \$filename.fasta --cpu --verbose
        evaluate-nn nn results/result_dataframe.h5 ${fastq} -o ${stats} --keep-files 
    done
#    rm -r results/
    echo "nn-classifier, \$(( \$(wc -l < ${fastq}/*_1.fastq) / 4 ))" >> ${readcount}
    """
}

// compress the results into a tar.gz archive
process COMPRESS_RESULTS {
    tag "${fastq.baseName.replace('_fastq','')}"
    cpus 1
    memory '200 MB'
    cache false

    container "file://${workflow.projectDir}/../images/dummy.sif"
    shell "/bin/bash"

    stageInMode 'copy'    
    publishDir {                    // final subfolder for each accession id stored with stats, readcount
        def name = fastq.getBaseName()
        def match = (name =~ /(SRR\d+)/)
        def accession = match ? match[0][1] : name
        return "${params.output}/${workflow.runName}/${accession}"
    }, mode: 'move'
    
    input:
    path fastq                      // Path to the FASTQ files to be compressed
    path stats
    path readcount

    output:
    path "${fastq}.tar.gz"          // A compressed tar.gz archive of the FASTQ files
    path stats
    path readcount

    script:
    """
    tar --use-compress-program="pigz" -cf ${fastq}.tar.gz ${fastq}/*
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
            input from      : ${params.input_file}
            output to       : ${params.output}
            --
            run as          : ${workflow.commandLine}
            started at      : ${workflow.start}
            config files    : ${workflow.configFiles}
            ---
            used databases
            bwa             : ${params.mapping_database.collect { db -> new File(db).getName() }.join(', ')}
            kraken          : ${params.kraken2_database.collect { db -> new File(db).getName() }.join(', ')}
            diamond         : ${params.blastx_database.collect { db -> new File(db).getName() }.join(', ')}
            blastn          : ${params.blastn_database.collect { db -> new File(db).getName() }.join(', ')}
            """
            .stripIndent()

    // setup
    channel
        .fromPath(params.input_file)
        .splitCsv()
        .flatten()
        .set { ch_accession_list }

    /* Create download pipe file (dlCom.pipe) to watch for free storage space */
    dl_com = CREATE_DL_COM()
    
    // Fetch accession info about estimated download size
    ch_accession_info = FETCH_ACCESSION_INFO(ch_accession_list)
    
    ch_ready = WATCH_STORAGE(ch_accession_info, dl_com)
    
    // Continue to prefetch accession data
    ch_sra = FETCH_ACCESSION(ch_ready)
    
    // Mark downloaded SRA as 'D' dlCom.pipe 
    (ch_acc_path, ch_acc_id, ch_acc_est, update_done) = UPDATE_DL_COM(ch_sra, ch_ready, dl_com)
    
    // Convert SRA to paired end reads 
    ch_fastq = FASTERQ(ch_sra, update_done)

    // Mark sra entry in dlCom.pipe as 'C' (converted) and remove (optionally) .sra file (triggers WATCH_STORAGE) 
    MARK_CONVERSION(ch_fastq, ch_acc_id, dl_com, ch_sra)

    // Begin analysis 
    ch_mapping = params.skip_mapping ? ch_fastq : MAPPING(get_parent_name(params.mapping_database), get_name(params.mapping_database), ch_fastq)
    ch_kraken = params.skip_kraken ? ch_fastq : KRAKEN(params.kraken2_database, ch_mapping)
    ch_blastx = params.skip_blastx ? ch_kraken : BLAST_X(get_parent_name(params.blastx_database), get_name(params.blastx_database), ch_kraken)

    barrier = params.skip_blastx ? channel.of(true).collect() : ch_blastx[3].collect()
    ch_blastn = params.skip_blastn ? ch_blastx : BLAST_N(get_parent_name(params.blastn_database), get_name(params.blastn_database), ch_blastx[0], ch_blastx[1], ch_blastx[2], barrier) 
    
    barrier = params.skip_blastn ? channel.of(true).collect() : ch_blastn[3].collect()
    ch_readseeker = params.skip_readseeker ? ch_blastn : READSEEKER(ch_blastn[0], ch_blastn[1], ch_blastn[2], barrier)

    ch_nn = params.skip_nn ? ch_readseeker : NN_CLASSIFIER(ch_readseeker)
    COMPRESS_RESULTS(ch_nn[0], ch_nn[1], ch_nn[2])
}