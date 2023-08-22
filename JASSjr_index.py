#!/usr/bin/env python3

from collections import defaultdict
import struct
import sys

if len(sys.argv) != 2:
    sys.exit(f"Usage: {sys.argv[0]} <infile.xml>")

docid = -1
document_length = 0
length_vector = []
doc_ids = []
push_next = False
vocab = defaultdict(lambda: [])

with open(sys.argv[1], 'r') as file:
    for line in file:
        for token in line.split():
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
            if len(postings_list) == 0 or postings_list[-1][0] != docid:
                postings_list.append((docid, 1))
            else:
                pair = postings_list[-1]
                postings_list[-1] = (docid, pair[1] + 1)

            document_length += 1

if docid == -1:
    sys.exit()

print(f"Indexed {docid + 1} documents. Serialising...")

length_vector.append(document_length)

with open("docids.bin", "w") as file:
    for doc in doc_ids:
        file.write(f"{doc}\n")

with open("lengths.bin", "wb") as file:
    for length in length_vector:
        file.write(struct.pack('i', length))

postings_fp = open("postings.bin", "wb")
vocab_fp = open("vocab.bin", "wb")

for term, postings in vocab.items():
    where = postings_fp.tell()
    for pair in postings:
        postings_fp.write(struct.pack('ii', pair[0], pair[1]))

    vocab_fp.write(struct.pack('B', len(term)))
    vocab_fp.write(term.encode())
    vocab_fp.write(struct.pack('B', 0)) # null termination
    vocab_fp.write(struct.pack('i', where))
    vocab_fp.write(struct.pack('i', len(postings) * 8))

postings_fp.close()
vocab_fp.close()
