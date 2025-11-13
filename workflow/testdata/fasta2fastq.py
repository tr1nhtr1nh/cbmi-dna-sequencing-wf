import os

def fasta2fastq(fasta_path: str, fastq_path: str, output_path: str, batch_size: int=1000):      # Wie sind die Dateien im Verzeichnis abgespeichert? 
    """
    This function converts the taxonomic classification (cls) output from FASTA back to FASTQ to keep quality scores. 
    Idea is to replace the header in FASTQ file from cls output.
    
    Params:
    fasta_path (str): (Set of) filepath to fasta file // Wollen wir einen Ordner übergeben oder eine einzelne Datei? 
    fastq_path (str): filepath to fastq file
    
    Returns: 
    None
    
    fasta:
    >SRR35359598.8 A00627:451:H5CKGDSX5:1:1101:16749:20697:N:0:GCTTGTGTAG+ATCATGGAGG length=150|False|0|1
    ACCACCCCTGTTGAACCGGTCAAGGTCGGCGACTGCATCTCGTGTCTCCCGAATGATGCTGACCCTGAACGGTTGGCTCAGAAGCGCCGCGAACTGGATGCGAACATTGTTCGGAACACAGCAACCGCGTTGCATGACTTCATTTTC
    
    fastq:
    @SRR35359598.8 A00627:451:H5CKGDSX5:1:1101:16749:20697:N:0:GCTTGTGTAG+ATCATGGAGG length=150
    CACCACCCCTGTTGAACCGGTCAAGGTCGGCGACTGCATCTCGTGTCTCCCGAATGATGCTGACCCTGAACGGTTGGCTCAGAAGCGCCGCGAACTGGATGCGAACATTGTTCGGAACACAGCAACCGCGTTGCATGACTTCATTTTCGC
    +SRR35359598.8 A00627:451:H5CKGDSX5:1:1101:16749:20697:N:0:GCTTGTGTAG+ATCATGGAGG length=150
    FFF,FFFFFFF:FFFF:FF,,FFFF:F:FFF:F,:FF:F,:::FFFFFF:::FFFFF:FF,FFF,FFFFF::F:::FF,F:FFF:FF,FF,FFFFF::FFFFFFFFF,:F,FFF:FFFFF,F:FFFFFF,FFFFFFF,FFFFFF,FF,FF


    Note: die Sequenzen stimmen nicht überein, am Anfang und Ende .. 2,3 Sequenzen zu viel 

    out: 
    @SRR35359598.8 A00627:451:H5CKGDSX5:1:1101:16749:20697:N:0:GCTTGTGTAG+ATCATGGAGG length=150|False|0|1
    CACCACCCCTGTTGAACCGGTCAAGGTCGGCGACTGCATCTCGTGTCTCCCGAATGATGCTGACCCTGAACGGTTGGCTCAGAAGCGCCGCGAACTGGATGCGAACATTGTTCGGAACACAGCAACCGCGTTGCATGACTTCATTTTCGC
    +SRR35359598.8 A00627:451:H5CKGDSX5:1:1101:16749:20697:N:0:GCTTGTGTAG+ATCATGGAGG length=150|False|0|1
    FFF,FFFFFFF:FFFF:FF,,FFFF:F:FFF:F,:FF:F,:::FFFFFF:::FFFFF:FF,FFF,FFFFF::F:::FF,F:FFF:FF,FF,FFFFF::FFFFFFFFF,:F,FFF:FFFFF,F:FFFFFF,FFFFFFF,FFFFFF,FF,FF
    """

# pseudo code: 
#     batch size is number of lines 
#     read batch size of fasta headers                # 10 headers = 10 entires
#     write batch size of fasta headers in fastq      # process 10 entires 




    

def fasta2fastq(fastq_path, fasta_path, output_path, batch_size: int=1000):
    """
    Params:
    batch_size(int): Number of entries processed
    """
    output_dir = os.path.dirname(output_path)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)
         
    i = 0
    with open(fasta_path, 'r') as fasta, open(fastq_path, 'r') as fastq:
        while True:
            fasta_headers = []
            while len(fasta_headers) < batch_size:
                line = fasta.readline()
                if not line:
                    break
                if line.startswith('>'):
                    fasta_headers.append(line.strip().replace('>', '@'))
                    # fasta_headers.append(line[1:].split()[0])
                i += 1
            if not fasta_headers:
                break
            # print(fasta_headers)
    
    
if __name__ == "__main__":
    fasta = "../TaxonomicClassification-NGS-NN/nn-fasta-results/test_1.fasta"
    fastq = "SRR35359598_fastq/test_1.fastq"
    out = "cls-fastq/test_1_cls.fastq"
    fasta2fastq(fastq, fasta, out, batch_size=110)
    
    
    
    # with open(fasta_path, 'r') as fasta:
    #     with open(fastq_path, 'r') as fastq:
    #         with open(output_path, 'w') as out:
    #             while True:
    #                 fasta_headers = []
    #                 while len(fasta_headers) < batch_size:
    #                     line = fasta.readline()
    #                     if not line:
    #                         print("Error: Header is empty string")
    #                         break
    #                     if line.startswith('>'):
    #                         fasta_headers.append(line.strip().replace('>', '@'))

    #                 if not fasta_headers:
    #                     print("Could not collect fasta headers")
    #                     break

    #                 batch_entries = []
    #                 for _ in range(len(fasta_headers)):
    #                     header = fastq.readline()
    #                     if not header:
    #                         break
    #                     seq = fastq.readline()
    #                     plus = fastq.readline()
    #                     qual = fastq.readline()
    #                     if not (seq and plus and qual):
    #                         break
    #                     batch_entries.append((header.strip(), seq, plus.strip(), qual))

    #                 for j, entry in enumerate(batch_entries):
    #                     header, seq, plus, qual = entry
    #                     new_header = fasta_headers[j] if j < len(fasta_headers) else header
    #                     new_plus = "+" + new_header[1:]
    #                     out.write(f"{new_header}{seq}{new_plus}{qual}")
    #                     i += 1
