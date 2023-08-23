#!/usr/bin/env python3

# JASSjr_index.py
# Copyright (c) 2023 Vaughan Kitchen
# Minimalistic BM25 search engine.

from array import array
from collections import defaultdict
import re
import struct
import sys

# Make sure we have one paramter, the filename
if len(sys.argv) != 2:
    sys.exit(f"Usage: {sys.argv[0]} <infile.xml>")

vocab = defaultdict(lambda: array('i')) # the in-memory index
doc_ids = [] # the primary keys
length_vector = array('i') # hold the length of each document

# A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
# TREC <DOCNO> primary keys have a hyphen in them
lexer = re.compile("[a-zA-Z0-9][a-zA-Z0-9-]*|<DOC>|<DOCNO>")

docid = -1
document_length = 0
push_next = False # is the next token the primary key?

with open(sys.argv[1], 'r') as file:
    for line in file:
        for token in lexer.findall(line):
            # If we see a <DOC> tag then we're at the start of the next document
            if token == "<DOC>":
                # Save the previous document length
                if docid != -1:
                    length_vector.append(document_length)
                # Move on to the next document
                docid += 1
                document_length = 0
                if docid % 1000 == 0:
                    print(f"{docid} documents indexed")
                continue
            # if the last token we saw was a <DOCNO> then the next token is the primary key
            if push_next:
                doc_ids.append(token)
                push_next = False
            if token == "<DOCNO>":
                push_next = True
                continue

            # lower case the string
            token = token.lower()

            # truncate any long tokens at 255 charactes (so that the length can be stored first and in a single byte)
            token = token[0:255]

            # add the posting to the in-memory index
            postings_list = vocab[token]
            if len(postings_list) == 0 or postings_list[-2] != docid:
                postings_list.append(docid)
                postings_list.append(1)
            else:
                postings_list[-1] += 1

            # Compute the document length
            document_length += 1

# If we didn't index any documents then we're done.
if docid == -1:
    sys.exit()

# tell the user we've got to the end of parsing
print(f"Indexed {docid + 1} documents. Serialising...")

# Save the final document length
length_vector.append(document_length)

# store the primary keys
with open("docids.bin", "w") as file:
    for doc in doc_ids:
        file.write(f"{doc}\n")

postings_fp = open("postings.bin", "wb")
vocab_fp = open("vocab.bin", "wb")

# serialise the in-memory index to disk
for term, postings in vocab.items():
    # write the postings list to one file
    where = postings_fp.tell()
    postings.tofile(postings_fp)

    # write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
    vocab_fp.write(struct.pack('B', len(term)))
    vocab_fp.write(term.encode())
    vocab_fp.write(b'\0') # string is null terminated
    vocab_fp.write(struct.pack('i', where))
    vocab_fp.write(struct.pack('i', len(postings) * 4)) # no. of bytes

# store the document lengths
with open("lengths.bin", "wb") as file:
    length_vector.tofile(file)

# clean up
postings_fp.close()
vocab_fp.close()
