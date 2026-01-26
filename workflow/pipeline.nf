#!/usr/bin/env nextflow

params.VERSION = '1.0.0'

// create a pipe for download communication
process CREATE_DL_COM {
    tag 'CREATE_DL_COM'
    cpus 1
    memory '200 MB'
    cache false
    stageInMode "symlink"

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
    // maxForks 1
    cpus 1
    memory '200 MB'
    stageInMode {workflow.resume ? 'copy': 'symlink'} 

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

process WATCH_STORAGE {
    tag "$accession"
    cpus 1
    memory '200 MB'
    maxForks 1
    cache false
    stageInMode "symlink"

    errorStrategy { task.exitStatus == 28 ? 'ignore' : 'terminate'}
    maxRetries 3

    container 'file://../images/sra-tools.sif'
    shell '/bin/bash'


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
    stageInMode {workflow.resume ? 'copy': 'symlink'} 

    cache 'lenient'
    maxRetries 3

    container "file://${workflow.projectDir}/../images/sra-tools.sif"
    shell "/bin/bash"

    input:
    val accession   // accession ID to be fetched
    val est_size    // estimated size of the accession

    output:
    path accession  // fetched accession file
    val accession   // pass through accession ID
    val est_size    // pass through estimated size

    script:
    """
    ${params.prefetch} --max-size ${params.max_disk_usage} ${accession}
    """
}

// register the downloaded accession in the communication file
process UPDATE_DL_COM {
    tag "$accession_id"
    cpus 1
    memory '200 MB'
    cache false
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
// update: create stats.csv to store evaluate.py results
process FASTERQ {
    tag "$accession"
    cpus 4
    memory '8 GB'
    stageInMode {workflow.resume ? 'copy': 'symlink'} 

    container 'file://../images/sra-tools.sif'
    shell '/bin/bash'


    input:
    val accession                                   // accession ID (string)

    output:
    path "${accession}_fastq"   // generated FASTQ files from the accession
    path "stats.csv"            // stats file
    path "readscount.csv"       // readscount file
    val accession               // pass through accession name

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
    path fastq          // generated FASTQ files
    path stats          // stats file
    path readscount     // readscount file
    val accession_id    // accession ID
    path dl_com         // communication pipe path for managing disk space (staged path)
    path sra_files      // prefetched sra files to free storage


    output:
    path fastq                  // pass through FASTQ files
    path stats
    path readscount

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
    #Uncomment line if we want to free storage. Will rerun FETCH_ACCESSION process 
    #This line breaks the caching nf rules
    #rm -r \$(readlink ${sra_files})
    """
}


// map FASTQ files against a reference database using BWA-MEM2
process MAPPING {
    tag "${fastq.baseName.replace('_fastq','')}"
    maxForks 1
    cpus params.cpu.mapping
    memory { params.mem.mapping * task.attempt }
    stageInMode {workflow.resume ? 'copy': 'symlink'} 

    errorStrategy { task.exitStatus in 137..140 ? 'retry' : 'terminate' }
    maxRetries 3

    container 'file://../images/bwa-mem.sif'
    shell '/bin/bash'
    
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


    // Update: use samtools 
    // Alternative without samtools: awk '($2 & 4) != 0' input.sam > unmapped.sam
    // move stats.csv to work dir (maybe output channel), so it does not append
    // samtools -f 12 (read unmapped + mate unmapped)
    /* Can control copies and symlink with StageInMode in nextflow.config */
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
    stageInMode {workflow.resume ? 'copy': 'symlink'} 

    errorStrategy { task.exitStatus in 137..140 ? 'retry' : 'terminate' }
    maxRetries 3

    container 'file://../images/kraken.sif'
    shell '/bin/bash'
    
    input:
    val kraken2_database   // Kraken2 database for classification
    path fastq              // Path to the FASTQ files for Kraken2 classification
    path stats
    path readcount

    output:
    path fastq              // Path to the modified FASTQ files
    path stats
    path readcount

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

        python3 ${workflow.projectDir}/templates/evaluate.py kraken results.txt ${fastq} -o ${stats} --keep-files
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
    stageInMode {workflow.resume ? 'copy': 'symlink'} 

    errorStrategy { task.exitStatus in 137..140 ? 'retry' : 'terminate' }
    maxRetries 3

    container 'file://../images/diamond.sif'
    shell '/bin/bash'

    input:
    val blastx_database
    val db_names
    path fastq
    path stats
    path readcount

    output:
    path fastq                          // Path to the modified FASTQ files
    path stats
    path readcount
    val(true)               // reference: https://nextflow-io.github.io/patterns/state-dependency/

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
    echo "blastx, \$(( \$(wc -l < ${fastq}/*_1.fastq) / 4 ))" >> ${readcount}
    """
}

// run BLASTN on FASTQ files for nucleotide sequence similarity search
process BLAST_N {
    tag "${fastq.baseName.replace('_fastq','')}"
    maxForks 1
    cpus params.cpu.blastn
    memory params.mem.blastn
    stageInMode {workflow.resume ? 'copy': 'symlink'} 

    errorStrategy { task.exitStatus in 137..140 ? 'retry' : 'terminate' }
    maxRetries 3

    container 'file://../images/blast.sif'
    shell '/bin/bash'
    
    input:
    val blastn_database
    val db_names
    path fastq
    path stats
    path readcount
    val mutex               // Mutex

    output:
    path fastq              // Path to the modified FASTQ files
    path stats
    path readcount
    val mutex

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
            blastn -db ${workflow.projectDir}/refseq/\${databases[i]}/\${file_names[i]} -outfmt "6 qseqid sseqid pident length evalue bitscore" -num_threads ${task.cpus} -query acc.fasta -out result.txt
            #rm acc.fasta
            python3 ${workflow.projectDir}/templates/evaluate.py blastn result.txt ${fastq} -o ${stats} --keep-files
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
    stageInMode {workflow.resume ? 'copy': 'symlink'} 

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
    path readcount
    val mutex

    output:
    path fastq
    path stats
    path readcount

    script:
    """
    for fastq_file in ${fastq}/*.fastq; do
        readseeker_fastq -q \$fastq_file -o preds.txt
        evaluate readseeker preds.txt ${fastq} -t ${params.readseeker.threshold} -o ${stats} --keep-files
    done
    echo "readseeker, \$(( \$(wc -l < ${fastq}/*_1.fastq) / 4 ))" >> ${readcount}
    """
}

// readseeker removes linecount - 2 (unsure)

process NN_CLASSIFIER {
    tag "${fastq.baseName.replace('_fastq','')}"
    maxForks 2 // not all cpus are used: for one job around 30 cpus are occupied => a second job fits in ... 
    cpus params.cpu.nn_cls
    memory params.mem.nn_cls 
    stageInMode {workflow.resume ? 'copy': 'symlink'} 

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
    """
}



// Todo: use samtools to create bam files ?

// compress the results into a tar.gz archive
process COMPRESS_RESULTS {
    tag "${fastq.baseName.replace('_fastq','')}"
    cpus 1
    memory '200 MB'
    cache false

    container "file://${workflow.projectDir}/../images/dummy.sif"
    shell "/bin/bash"

    stageInMode 'copy'    
    publishDir {                                    // final subfolder for each accession id stored with stats, readcount
        def name = fastq.getBaseName()
        def match = (name =~ /(SRR\d+)/)
        def accession = match ? match[0][1] : name
        return "${params.output}/${workflow.runName}/${accession}"
    }, mode: 'move'
    
    input:
    path fastq                                  // Path to the FASTQ files to be compressed
    path stats
    path readcount

    output:
    path "${fastq}.tar.gz"                      // A compressed tar.gz archive of the FASTQ files
    path stats
    path readcount

    script:
    """
    tar --use-compress-program="pigz" -cf ${fastq}.tar.gz ${fastq}/*
    #rm -r ${fastq}
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
    
    /* Fetch accession info about estimated download size*/
    ch_accession_info = FETCH_ACCESSION_INFO(ch_accession_list)

    /* 
        Checks accumulated storage size for 'D' noted SRR ids and
        calculates a summed size. 
        Process sets up a watch to check for file modification if
        params.max_disk_size is reached
     */
    
    ch_ready = WATCH_STORAGE(ch_accession_info, dl_com)
    
    /* Continue to prefetch accession data */
    ch_accession = FETCH_ACCESSION(ch_ready)
    
    /* Mark downloaded SRA as 'D' 'SRA' 'size' in dlCom.pipe */
    (ch_acc_path, ch_acc_id, ch_acc_est) = UPDATE_DL_COM(ch_accession, dl_com)
    
    /* Convert SRA to paired end reads */
    (ch_fastq_dir, ch_stats, ch_readscount, ch_acc_id_out) = FASTERQ(ch_acc_id)

    /* Mark sra entry in dlCom.pipe as 'C' (converted) and remove .sra file (triggers WATCH_STORAGE) */
    ch_fastq = MARK_CONVERSION(ch_fastq_dir, ch_stats, ch_readscount, ch_acc_id_out, dl_com, ch_acc_path)

    /* Begin analysis */
    ch_mapping = params.skip_mapping ? ch_fastq : MAPPING(get_parent_name(params.mapping_database), get_name(params.mapping_database), ch_fastq_dir, ch_stats, ch_readscount)
    ch_kraken = params.skip_kraken ? ch_fastq : KRAKEN(params.kraken2_database, ch_mapping)
    ch_blastx = params.skip_blastx ? ch_kraken : BLAST_X(get_parent_name(params.blastx_database), get_name(params.blastx_database), ch_kraken)
    /* 
        Scheduling helps with BlastN process memory usage (around 97%)
        BLAST_X emits a mutex object (boolean) to trigger BLAST_N process.
        Collecting all mutex objects before proceeding guarantees that, after the barrier, 
        the Blast_N processes run independently with no other process executing in parallel.
        Inputs in BLAST_X are strucured as follwed:
        input:
        path fastq      : channel[0]
        path stats      : channel[1]
        path readcount  : channel[2]
        val mutex       : channel[3]      -> the other processes don't accept this channel, therefore it is removed

        Since skipping processes is an option, inputs can be mixed up 
        with mutex object. Neural network + compression process only need 

        Mutex/ barrier (channel[3].collect()):
        collects a bool value/ mutex from prior process
        until all mutex vals are collected the next process starts
        Important for memory consuming jobs and helps with out-of-memory crashes
        side-effect: 
            BlastN task used to tend to failure which would skip this task and 
            rerun after Readseeker. This would break the chronological ordner of
            the toolset.


        correct way to resume: https://www.nextflow.io/docs/latest/cache-and-resume.html#resuming-from-a-specific-run
        nextflow run <.nf> -resume session-ID
    */


    barrier = ch_blastx[3].collect()
    ch_blastn = params.skip_blastn ? ch_blastx : BLAST_N(get_parent_name(params.blastn_database), get_name(params.blastn_database), ch_blastx[0], ch_blastx[1], ch_blastx[2], barrier) 
    
    barrier = ch_blastn[3].collect() 
    ch_readseeker = params.skip_readseeker ? ch_blastn : READSEEKER(ch_blastn[0], ch_blastn[1], ch_blastn[2], barrier)

    ch_nn = params.skip_nn ? ch_readseeker : NN_CLASSIFIER(ch_readseeker)
    COMPRESS_RESULTS(ch_nn[0], ch_nn[1], ch_nn[2])


    /* Code lines for without mutes. Remember to remove mutex as in/ output channel in each process */
    // ch_blastn = params.skip_blastn ? ch_blastx : BLAST_N(get_parent_name(params.blastn_database), get_name(params.blastn_database), ch_blastx) 
    // ch_readseeker = params.skip_readseeker ? ch_blastn : READSEEKER(ch_blastn)
    // ch_nn = params.skip_nn ? ch_readseeker : NN_CLASSIFIER(ch_readseeker)
    // COMPRESS_RESULTS(ch_nn)


}