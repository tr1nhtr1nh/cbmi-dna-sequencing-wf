import argparse
import os

def fasta2fastq(fastq_path: str, fasta_path: str, output_path: None, batch_size):
    """
    This function converts the taxonomic classification (cls) output from FASTA back to FASTQ to keep quality scores. 
    It replaces the meta (@) and comment (+) lines in FASTQ file from cls output.
    
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


def main():
    parser = argparse.ArgumentParser(
        prog="Fasta2fastq converter",
        description="This utility program converts the FASTQ Taxonomic Classification NGS NN output file back to FASTQ format."
    )

    parser.add_argument('-a', '--fasta', type=str, help="Filepath to input FASTA files.", required=True)
    parser.add_argument('-q', '--fastq', type=str, help="Filepath to input FASTQ files.", required=True)
    parser.add_argument('-o', '--output', type=str, help="Filepath to created FASTQ files. An additional directory path can be specified.", required=True)
    parser.add_argument('-bs', '--batchsize', type=int, help="Integer number of processed entries per batch (default=1024). ", default=1024)

if __name__ == "__main__":
    main()