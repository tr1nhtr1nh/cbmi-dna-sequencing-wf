from tqdm import tqdm as tqdmn


class FastqBatchLoader(object):
    def __init__(self, fastq_file, batch_size):
        self.fastq_file_handler = open(fastq_file, "r")
        self.batch_size = batch_size
        self.line = 0
        self.entry_count = sum(1 for line in self.fastq_file_handler if line) // 4
        self.fastq_file_handler.seek(0)

    def __del__(self):
        self.fastq_file_handler.close()

    def __read_entry__(self):
        header = self.fastq_file_handler.readline().strip()
        seq = self.fastq_file_handler.readline().strip()
        comment = self.fastq_file_handler.readline().strip()
        qual = self.fastq_file_handler.readline().strip()
        self.line += 4
        if not qual:
            return None
        if header[0] != "@":
            raise ValueError(f"Header does not start with '@' at line {self.line - 3} {header}")
        if comment[0] != "+":
            raise ValueError(f"Comment does not start with '+' at line {self.line - 2} {comment}")
        kmerseq = " ".join([seq[i:i + 6] for i in range(0, len(seq) - 5)])
        return header, kmerseq

    def __iter__(self):

        with tqdmn(total=self.entry_count) as pbar:
            batch = [result for _ in range(self.batch_size) if (result := self.__read_entry__()) is not None]
            while batch:
                pbar.update(len(batch))
                yield zip(*batch)
                batch = [result for _ in range(self.batch_size) if (result := self.__read_entry__()) is not None]

