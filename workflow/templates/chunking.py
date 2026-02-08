import argparse
from pathlib import Path
from math import ceil

def chunk_fastq_files(input_folder, output_folder, reads_per_chunk=100000):
    """
    Split paired-end FASTQ files into chunks and store in subfolders.

    Params:
    input_folder: Path to folder containing paired-end FASTQ files
    output_folder: Path to output folder for chunks
    reads_per_chunk: Number of reads per chunk (default: 100000)
    """
    input_path = Path(input_folder)
    output_path = Path(output_folder)
    output_path.mkdir(parents=True, exist_ok=True)
        
    # Find paired-end FASTQ files (search root)
    fastq_files = sorted(input_path.glob("*.fastq"))
    if not fastq_files:
        raise ValueError("No FASTQ files found in input folder")
    
    # Group into pairs using `_1` and `_2` suffixes only
    pairs = {}
    for file in fastq_files:
        base = file.stem.replace("_1", "").replace("_2", "")
        if base not in pairs:
            pairs[base] = {}
        if file.stem.endswith("_1"):
            pairs[base]["1"] = file
        elif file.stem.endswith("_2"):
            pairs[base]["2"] = file
    
    # Count reads in first file to determine lines per chunk
    with open(list(pairs.values())[0]["1"]) as f:
        total_lines = sum(1 for _ in f)
    total_reads = total_lines // 4

    # Determine number of chunks based on reads_per_chunk
    if reads_per_chunk <= 0:
        raise ValueError("'reads_per_chunk' must be a positive integer")
    num_chunks = ceil(total_reads / reads_per_chunk)
    
    # Determine width for binary chunk names
    bin_width = max(1, (num_chunks - 1).bit_length())
    
    # Create top-level chunks directory
    chunks_root = output_path / "chunks"
    chunks_root.mkdir(parents=True, exist_ok=True)
    
    # Create chunk folders with binary names
    for sample_id in pairs.keys():
        for chunk_id in range(num_chunks):
            chunk_bin = format(chunk_id, f"0{bin_width}b")
            chunk_dir = chunks_root / f"{sample_id}_{chunk_bin}"
            chunk_dir.mkdir(parents=True, exist_ok=True)
    
    # Split files by streaming sequentially
    for sample_id, file_dict in pairs.items():
        for i in ["1", "2"]:
            if i not in file_dict:
                continue

            input_file = file_dict[i]

            # Open all chunk files for this read type
            chunk_files = {}
            for chunk_id in range(num_chunks):
                chunk_bin = format(chunk_id, f"0{bin_width}b")
                chunk_dir = chunks_root / f"{sample_id}_{chunk_bin}"
                output_file = chunk_dir / f"{sample_id}_{i}.fastq"
                chunk_files[chunk_id] = open(output_file, "w")
            
            try:
                # Stream through input file and distribute to chunks
                with open(input_file) as f_in:
                    chunk_id = 0
                    reads_in_chunk = 0
                    
                    while True:
                        lines = [f_in.readline() for _ in range(4)]
                        if not lines[0]:  # EOF
                            break
                        
                        chunk_files[chunk_id].writelines(lines)
                        reads_in_chunk += 1
                        
                        # Move to next chunk if current one is full
                        if reads_in_chunk >= reads_per_chunk and chunk_id < num_chunks - 1:
                            chunk_id += 1
                            reads_in_chunk = 0
            finally:
                for f in chunk_files.values():
                    f.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Split paired-end FASTQ files into chunks")
    parser.add_argument("--input_folder", "-i", required=True, help="Path to folder containing paired-end FASTQ files (input directory)")
    parser.add_argument("--output_folder", "-o", required=True, help="Path to output folder where chunks will be written")
    parser.add_argument("--reads_per_chunk", "-s", type=int, default=100000, help="Number of reads per chunk (default: 100000)")

    args = parser.parse_args()
    chunk_fastq_files(args.input_folder, args.output_folder, reads_per_chunk=args.reads_per_chunk)
