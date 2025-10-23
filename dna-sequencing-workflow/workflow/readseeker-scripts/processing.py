# (Preprocess)
# ReadSeeker braucht 6-mere (sliding Window), aber FASTQ hat Metadaten. 

# Skript schreiben; Aus den FASTQ-Datein die Sequenzen rausziehen und darüber eine Liste von 6-mer Mengen erstellen mit Leerzeichen separiert und mit Tab separiert den Header dahinter schreiben 
# Für neuen Eintrag 

# BSP: 
# (sliding windows von 6, jeweils 1 stelle weiterrücken, 5 überlappend jeweils)
# (pro FASTQ Eintrag)
# CGCCAC GCCACG CCACGT CACGTT… 	bis ende	@SRR35359594.398942 A00627:451:H5CKGDSX5:2:1551:22661:27743:N:0:GACAATCCAC+ACGGTCTTGT length=150
# Tipp eigenen Parser (Skript) schreiben, weil das schneller geht 

# usage: python3 --pre or --post options <fastq-file> 
# process blastn will be input 

import argparse
import os

def preprocessing(src, dest):
    """
    Read 6-mers from 
    Remember nextflow input and output channels
    
    input: 
        filepath: filepath to fastq file

    return: 
        result. file descriptor to 
    """
    with open(src, "r") as input, open(dest, "w") as output:
        while True:
            header = input.readline().strip()
            if not header:
                break
            seq = input.readline().strip()
            input.readline()
            input.readline()
            
            kmers = seq_to_kmers(seq, 6)
            kmers_line = " ".join(kmers)

            output.write(f"{kmers_line}\t\t{header}\n")    
    return

# helpers
def seq_to_kmers(seq, k=6):
    return [seq[i:i+k] for i in range(len(seq) - k + 1)]

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
                        prog='ReadSeeker pre- and post-processing script',
                        description='(pre) Turn fastq output from bioinformatic pipeline tools (last one is blast) to custom 6-mers format. (post) Do something else.',
                        epilog='Example: python preprocessing.py --pre -f src.fastq -o dest.fastq')

    mode_group = parser.add_mutually_exclusive_group(required=True)
    mode_group.add_argument("--pre", action="store_true", help="pre process readseeker input data")
    mode_group.add_argument("--post", action="store_true", help="post process readseeker input data")
    parser.add_argument("-f", "--file", type=str, help="source file path", required=True)
    parser.add_argument("-o", "--out", type=str, help="destination file path", required=True)
    args = parser.parse_args()

    outdir = os.path.dirname(args.out)
    if outdir:
        os.makedirs(outdir, exist_ok=True)

    preprocessing(args.file, args.out)