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

def preprocessing(fd, args):
    """
    Read 6-mers from 
    Remember nextflow input and output channels
    
    input: 
        fd          : file descriptor (number) to fastaq

    return: 
        result      : preprocessed fastq files
    """
    return

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
                        prog='ReadSeeker pre- and post-processing script',
                        description='(pre) Turn fastq output from bioinformatic pipeline tools (last one is blast) to custom 6-mers format. (post) Do something else.',
                        epilog='Text at the bottom of help')    
    
    parser.add_argument("--pre", type=str, help="run processing prior to readseeker process")