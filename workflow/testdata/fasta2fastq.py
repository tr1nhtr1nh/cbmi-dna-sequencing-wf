import os

def fasta2fastq(fastq_path: str, fasta_path: str, output_path: None, batch_size=1000):
    """
    This function converts the taxonomic classification (cls) output from FASTA back to FASTQ to keep quality scores. 
    Idea is to replace the header in FASTQ file from cls output.
    
    Params:
    fasta_path (str): (Set of) filepath to fasta file // Wollen wir einen Ordner übergeben oder eine einzelne Datei? 
    fastq_path (str): Filepath to fastq file
    output_path (str): Optional destination directory for output
    batch_size (int): Number of entries one batch processes
    
    Returns: 
    None
    """
    output_dir = os.path.dirname(output_path)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)

    with open(fasta_path, 'r') as fasta, \
         open(fastq_path, 'r') as fastq, \
         open(output_path, 'w') as out:

        while True:
            fasta_headers = []
            while len(fasta_headers) < batch_size:
                line = fasta.readline()
                if not line:
                    break
                if line.startswith(">"):
                    fasta_headers.append(line.strip().replace('>', '@'))

            if not fasta_headers:
                break

            for new_header in fasta_headers:

                header = fastq.readline()
                seq    = fastq.readline()
                plus   = fastq.readline()
                qual   = fastq.readline()

                if not (header and seq and plus and qual):
                    return
                
                new_plus = "+" + new_header[1:]
                out.write(f"{new_header}\n{seq}{new_plus}\n{qual}")
