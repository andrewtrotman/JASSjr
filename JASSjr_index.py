#!/usr/bin/env python3

from array import array
from collections import defaultdict
import re
import struct
import sys

if len(sys.argv) != 2:
    sys.exit(f"Usage: {sys.argv[0]} <infile.xml>")

docid = -1
document_length = 0
length_vector = array('i')
doc_ids = []
push_next = False
vocab = defaultdict(lambda: array('i'))

with open(sys.argv[1], 'r') as file:
    for line in file:
        for token in re.findall("[a-zA-Z0-9][a-zA-Z0-9-]*|<[^>]*>", line):
            if token == "<DOC>":
                if docid != -1:
                    length_vector.append(document_length)
                docid += 1
                document_length = 0
                if docid % 1000 == 0:
                    print(f"{docid} documents indexed")
            if push_next:
                doc_ids.append(token)
                push_next = False
            if token == "<DOCNO>":
                push_next = True
            if token[0] == "<":
                continue

            token = token.lower()

            token = token[0:255]

            postings_list = vocab[token]
            if len(postings_list) == 0 or postings_list[-2] != docid:
                postings_list.append(docid)
                postings_list.append(1)
            else:
                postings_list[-1] += 1

            document_length += 1

if docid == -1:
    sys.exit()

print(f"Indexed {docid + 1} documents. Serialising...")

length_vector.append(document_length)

with open("docids.bin", "w") as file:
    for doc in doc_ids:
        file.write(f"{doc}\n")

with open("lengths.bin", "wb") as file:
    length_vector.tofile(file)

postings_fp = open("postings.bin", "wb")
vocab_fp = open("vocab.bin", "wb")

for term, postings in vocab.items():
    where = postings_fp.tell()
    postings.tofile(postings_fp)

    vocab_fp.write(struct.pack('B', len(term)))
    vocab_fp.write(term.encode())
    vocab_fp.write(b'\0') # null termination
    vocab_fp.write(struct.pack('i', where))
    vocab_fp.write(struct.pack('i', len(postings) * 4)) # no. bytes

postings_fp.close()
vocab_fp.close()
