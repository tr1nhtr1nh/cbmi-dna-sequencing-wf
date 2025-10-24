import argparse
import os

def preprocessing(src, dest):
    """
    Reads a FASTQ file from src, extracts only the sequences and their headers, 
    converts each sequence into overlapping 6-mers (sliding window), 
    and writes the result to dest as space-separated 6-mers followed by the original header.

    input: 
        src: read from fastq source file
        dest: write into fastq destination file

    return: 
        result None 
    """

    k = 6
    with open(src, "r") as input, open(dest, "w") as output:
        while True:
            header = input.readline().strip()
            if not header:
                break
            seq = input.readline().strip()
            input.readline()
            input.readline()
            
            kmers = [seq[i:i+k] for i in range(len(seq) - k + 1)]
            kmers_line = " ".join(kmers)
            
            filename = os.path.basename(input.name)
            
            output.write(f"{kmers_line}\t{header} {filename}\n")
    return

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
                        prog='Usage: python preprocessing.py --pre -f <src.fastq> -o <dest.fastq>',
                        description='Process fastq file before and after the ReadSeeker tool.')

    mode_group = parser.add_mutually_exclusive_group(required=True)
    mode_group.add_argument("--pre", action="store_true", help="pre process readseeker input data")
    mode_group.add_argument("--post", action="store_true", help="post process readseeker input data")
    parser.add_argument("-f", "--file", type=str, help="source file path", required=True)
    parser.add_argument("-o", "--out", type=str, help="destination file path", required=True)
    args = parser.parse_args()

    # In case custom directories are specified
    outdir = os.path.dirname(args.out)
    if outdir:
        os.makedirs(outdir, exist_ok=True)

    preprocessing(args.file, args.out)