import csv
import pandas as pd
import os

from evaluate import removeReadsFromFastq, evaluate, writeOutputCSV, getFastQFiles

ANALYSE_TYPE_CHOICES = ['nn']

def evaluate(path, analyse_type, keep_files):
    """
    @override: handle pandas dataframe evaluation (filter) individually 
    Evaluates the analysis results from the neural network classification within a given directory or a single file.
    
    The evaluation for the neural network is seperated from the other tools, hence the analysis result file is of type h5/ hdf.
    Therefore pandas is needed, but the other singularity container don't have pandas installed and also don't need it. 


    Parameters:
    path (str): Path to a directory or a single file containing analysis results. Exception for neural network: result_file is a .h5 
    analyse_type (str): Type of analysis in neural network (nn) classification.
    keep_files (bool): Whether to keep or delete the analysis files after processing.

    Returns:
    set: A set of matched accession lines based on the analysis type.
    """
    matched_lines = set()

    if args.type == 'nn':
        analyse_function = evaluateNN
    else:
        raise Exception('Unsupported type choice: ' + analyse_type)

    analysis_results = []
    if os.path.isfile(path):
        analysis_results.append(path)
    else:
        for file in os.listdir(path):
            analysis_results.append(path + '/' + file)
    
    if args.type == 'nn':
        df = pd.read_hdf(path, columns=["seq_id", "species_pred"])
        df["seq_id"] = df["seq_id"].str.split().str[0].str.lstrip(">")
        # df.to_csv("cls_results.csv", index=False)                           # store cls results into csv
        for index, line in df.iterrows():
            analyse_function(matched_lines, line)
        if not keep_files:
            os.remove(file)
        return matched_lines
    

def evaluateNN(matched_lines, line):
    """
    Evaluates the Taxonomic NGS NN classification. 
    If the predicted species of a sequence equals 2 (classified as mammal), than this sequence gets removed.  
    
    Params:
    matched_lines (set): Set to which the matched sequence ids will be added.
    line (dataframe row): Dataframe line (row) from neural network result hdf file.
    
    Returns:
    None
    """
    
    if line["species_pred"] == 2:
        matched_lines.add(str(line["seq_id"]))
        
def writeOutputCSV(output_file, matched_acc):
    """
    @override: append int 5 for nn cls
    Writes the matched accession numbers and their analysis type to a CSV file.

    Parameters:
    output_file (str): Path to the output CSV file.
    matched_acc (set of str): Set of matched accession lines to write to the file.
    analyse_type (str): Type of analysis in neural network (nn) classification.

    Returns:
    None
    """
    typeNumber = 5
    with open(output_file, 'a') as csvfile:
        writer = csv.writer(csvfile, ['accession', 'analyseType'])
        for acc in matched_acc:
            writer.writerow([acc, typeNumber])
    
def main(args):
    fastq_files = getFastQFiles(args.fastq_dir)
    matched_acc = evaluate(args.analysis_results, args.type, args.keep_files)
    
    removeReadsFromFastq(fastq_files, matched_acc)
    
    if args.output:
        writeOutputCSV(args.output, matched_acc)

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser()
    
    parser.add_argument('type', choices=ANALYSE_TYPE_CHOICES, help='Program with which the analysis was performed.')
    parser.add_argument('analysis_results', type=str, help='Directory or File containing the analysis results that should be evaluated.')
    parser.add_argument('fastq_dir', type=str, help='Directory containing the fastq data to be trimmed.')
    parser.add_argument('-o', '--output', type=str, help='Name of the output file containing the removed indexes.')
    parser.add_argument('--keep-files', action="store_true", help='Keeps the analysis results input file.')
    
    args = parser.parse_args()
    main(args)