#! /bin/python
# Load model directly
from transformers import AutoTokenizer, AutoModelForSequenceClassification
import torch
from fastq_batch_loader import FastqBatchLoader
import argparse
import sys


def erprint(*msgs, flush=False):
    sys.stderr.write(" ".join([str(x) for x in msgs]) + "\n")
    if flush:
        sys.stderr.flush()


def predict(model, data, sm=torch.nn.Softmax(dim=1), use_gpu=False):    # default: use_gpu=True, pumpkin03 has no nvidia gpu support
    with torch.no_grad():
        if use_gpu:
            model_output = model(input_ids=data["input_ids"].cuda(), attention_mask=data["attention_mask"].cuda())[0]
        else:
            model_output = model(input_ids=data["input_ids"], attention_mask=data["attention_mask"])[0]
        # Softmax and return prob of CDS Label
        return sm(model_output)[:, 1].cpu().numpy()


def main(model_path, fastq_path, gpu_flag, batch_size, outfile):
    erprint("_________ReadSeeker___________")
    erprint("Loading model...")
    model = AutoModelForSequenceClassification.from_pretrained(model_path)
    tokenizer = AutoTokenizer.from_pretrained(model_path)
    gpu_use = gpu_flag and torch.cuda.is_available()

    erprint("Model_Path:", model_path)
    erprint("FastQ_Path:", fastq_path)
    erprint("GPU_Flag:", gpu_flag)
    erprint("BatchSize:", batch_size)
    erprint("______________________________")

    if gpu_use:
        erprint("Using 'cuda' mode for inference.")
        model.to("cuda")
        erprint("Cuda - Devices:")
        erprint(torch.cuda.get_device_name())

    else:
        erprint("Using 'cpu' mode for inference.")
    erprint("______________________________", flush=True)

    fq_reader = FastqBatchLoader(fastq_path, batch_size)

    for header, sequences in fq_reader:
        a = tokenizer.batch_encode_plus(sequences, return_tensors="pt", max_length=295, padding="max_length",
                                        truncation=True)
        prediction = predict(model, a)
        buffer = ["{}\t{}\n".format(h, prob) for h, prob in zip(header, prediction)]
        outfile.writelines(buffer)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Readseeker Wrapper')
    parser.add_argument('-m', '--model', dest='modelpath', help='Path or model name',
                        default='bnwlf/ReadSeeker')
    parser.add_argument('-q', '--fastq', dest='fastq', required=True)
    parser.add_argument('-g', '--gpu', dest="gpuflag", default=True, action='store_true')
    parser.add_argument('-o', "--output", dest="outfile", type=argparse.FileType('w'), default=sys.stdout)
    parser.add_argument('-b', "--batchsize", dest="batchsize", type=int, default=100,
                        help="Batchsize for Dataset copied to GPU (2GB Video Mem per 100 Seq)")

    args = parser.parse_args()
    main(args.modelpath.strip("\"'"), args.fastq.strip("\"'"), args.gpuflag, args.batchsize, args.outfile)
