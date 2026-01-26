from argparse import FileType
import argparse
import os
import re
import csv

ANALYSE_TYPE_CHOICES = ['mapping','kraken','blastx', 'blastn', 'readseeker', 'nn']

def removeReadsFromFastq(fastq_files, remove_lines):
    """
    Removes specific reads from a list of FASTQ files.

    Parameters:
    fastq_files (list of str): List of paths to FASTQ files.
    remove_lines (set of str): Set of read identifiers to remove from the FASTQ files.

    Returns:
    None
    """
    for fastq_file in fastq_files:
        with open(fastq_file, 'r') as f:
            lines = f.readlines()
        with open(fastq_file, 'w') as f:
            delete_next = False
            for line in lines:
                if line.strip("\n").split(' ')[0][1:] in remove_lines:
                    delete_next = True
                elif delete_next:
                    delete_next = False
                else:
                    f.write(line)


def evaluate(path, analyse_type, keep_files, exclude_file):
    """
    Evaluates the analysis results from files within a given directory or a single file.

    Parameters:
    path (str): Path to a directory or a single file containing analysis results.
    analyse_type (str): Type of analysis (e.g., 'kraken', 'blastn', 'blastx', 'mapping', 'readseeker').
    keep_files (bool): Whether to keep or delete the analysis files after processing.
    exclude_file (file): Path to a text file (or a file object) containing sequences to exclude from filtering. If provided, these sequences will be ignored during analysis. 

    Returns:
    set: A set of matched accession lines based on the analysis type.
    """
    matched_lines = set()
    
    if args.type == 'kraken':
        analyse_function = evaluateKraken
    elif args.type == 'blastn':
        analyse_function = evaluateBlast
    elif args.type == 'blastx':
        analyse_function = evaluateBlast
    elif args.type == 'mapping':
        analyse_function = evaluateMapping
    elif args.type == 'readseeker':
        analyse_function = evaluateReadseeker
    else:
        raise Exception('Unsupported type choice: ' + analyse_type)
    
    analysis_results = []
    if os.path.isfile(path):
        analysis_results.append(path)
    else:
        for file in os.listdir(path):
            analysis_results.append(path + '/' + file)
    
    for file in analysis_results:
        with open(file, 'r') as f:
            for line in f:
                analyse_function(matched_lines, line)
        if not keep_files:
            os.remove(file)
            
        # will probably called in kraken2 filter step 
        if exclude_file:
            excluded_sequences = {line.strip() for line in args.exclude_file if line.strip()}
            matched_lines -= excluded_sequences
            args.exclude_file.close()
            
    return matched_lines


def evaluateKraken(matched_lines, line):
    """
    Evaluates if a line from a Kraken analysis output has been classified.

    Parameters:
    matched_lines (set): Set to which the matched sequence ids will be added.
    line (str): A single line from a Kraken output file.

    Returns:
    None
    """
    if line[0] == 'C':
        matched_lines.add(re.split(r'\t+', line)[1])


def evaluateBlast(matched_lines, line):
    """
    Evaluates if a line from a BLAST analysis output has been classified.

    Parameters:
    matched_lines (set): Set to which the matched sequence ids will be added.
    line (str): A single line from a BLAST output file.

    Returns:
    None
    """
    matched_lines.add(re.split(r'\t+', line)[0].strip("\n"))


def evaluateMapping(matched_lines, line):
    """
    Evaluates if a line from a mapping analysis output has been classified.

    Parameters:
    matched_lines (set): Set to which the matched sequence ids will be added.
    line (str): A single line from a mapping output file.

    Returns:
    None
    """
    if line[0] != '@':
        line_arr = re.split(r'\t+', line)
        bin_flag = bin(int(line_arr[1]))[2:].zfill(3)
        if bin_flag[-3] == '0':
            matched_lines.add(line_arr[0])


def evaluateReadseeker(matched_lines, line):
    """
    Evaluates the ReadSeeker model estimation value if a given read is inside cds or non-cds region.
    
    Parameters:
    matched_lines (set): Set to which the matched sequence ids will be added.
    line (str): A single line from a ReadSeeker predictions file.
    threshold (float): If ReadSeeker model prediction is smaller than the given threshold then the line gets removed.
    
    Returns:
    None
    """
    if float(line.split()[-1]) < args.threshold:
        matched_lines.add(re.split(r' ', line)[0].lstrip('@'))


def getFastQFiles(fastq_dir):
    """
    Retrieves all FASTQ files from a specified directory.

    Parameters:
    fastq_dir (str): Path to the directory containing FASTQ files.

    Returns:
    list: A list of paths to the FASTQ files in the directory.
    """
    fastq_files = []
    for file in os.listdir(fastq_dir):
        fastq_files.append(fastq_dir + '/' + file)
    return fastq_files


def writeOutputCSV(output_file, matched_acc, analyse_type):
    """
    Writes the matched accession numbers and their analysis type to a CSV file.

    Parameters:
    output_file (str): Path to the output CSV file.
    matched_acc (set of str): Set of matched accession lines to write to the file.
    analyse_type (str): Type of analysis (e.g., 'kraken', 'blastn', 'blastx', 'mapping', 'readseeker').

    Returns:
    None
    """
    typeNumber = ANALYSE_TYPE_CHOICES.index(analyse_type)
    with open(output_file, 'a') as csvfile:
        writer = csv.writer(csvfile, ['accession', 'analyseType'])
        for acc in matched_acc:
            writer.writerow([acc, typeNumber])

def main(args):
    fastq_files = getFastQFiles(args.fastq_dir)
    matched_acc = evaluate(args.analysis_results, args.type, args.keep_files, args.exclude_file)
    
    removeReadsFromFastq(fastq_files, matched_acc)
    
    if args.output:
        writeOutputCSV(args.output, matched_acc, args.type)
    
def restricted_float(x):
    x = float(x)
    if x < 0.0 or x > 1.0:
        raise argparse.ArgumentTypeError(f"{x} not in range [0.0, 1.0]")
    return x

if __name__ == "__main__":
    
    parser = argparse.ArgumentParser()
    
    parser.add_argument('type', choices=ANALYSE_TYPE_CHOICES, help='Program with which the analysis was performed.')
    parser.add_argument('analysis_results', type=str, help='Directory or File containing the analysis results that should be evaluated.')
    parser.add_argument('fastq_dir', type=str, help='Directory containing the fastq data to be trimmed.')
    parser.add_argument('-t', '--threshold', dest="threshold", type=restricted_float, help='Float threshold for filtering CDS estimations from Readseeker model [0.0, 1.0].')
    parser.add_argument('-o', '--output', type=str, help='Name of the output file containing the removed indexes.')
    parser.add_argument('--keep-files', action="store_true", help='Keeps the analysis results input file.')
    parser.add_argument('-e', '--exclude-file', type=FileType('r'), help="Exclude sequences from being filtered. Option requires a FILE object.")
    
    args = parser.parse_args()
    main(args)