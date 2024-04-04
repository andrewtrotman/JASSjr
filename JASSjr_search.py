#!/usr/bin/env python3

# JASSjr_search.py
# Copyright (c) 2023 Vaughan Kitchen
# Minimalistic BM25 search engine.

from array import array
from collections import deque
import math
import struct
import sys

k1 = 0.9 # BM25 k1 parameter
b = 0.4 # BM25 b parameter

def read_file(filename):
    with open(filename, mode='rb') as file:
            return file.read()

def read_lines(filename):
    with open(filename) as file:
            return file.readlines()

# decode the vocabulary (one byte length, string, '\0', 4 byte where, 4 byte size)
def decode_vocab(buffer):
    offset = 0
    while offset < len(buffer):
        length, = struct.unpack_from('B', buffer, offset=offset)
        offset += 1

        word, = struct.unpack_from(f'{length}s', buffer, offset=offset)
        offset += length + 1 # Null terminated

        where, size = struct.unpack_from('ii', buffer, offset=offset)
        offset += 8

        yield word.decode(), where, size

contents_vocab = read_file('vocab.bin')
contents_postings = read_file('postings.bin')
doc_lengths = array('i', read_file('lengths.bin')) # Read the document lengths
doc_ids = read_lines('docids.bin') # Read the primary_keys

# Compute the average document length for BM25
average_length = sum(doc_lengths) / len(doc_lengths)
vocab = {}

# Build the vocabulary in memory
for word, offset, size in decode_vocab(contents_vocab):
    vocab[word] = (offset, size)

# Search (one query per line)
for query in sys.stdin:
    query_id = 0
    accumulators = [(0, 0)] * len(doc_lengths) # array of rsv values

    # If the first token is a number then assume a TREC query number, and skip it
    terms = deque(query.split())
    if terms[0].isnumeric():
        query_id = terms.popleft()

    for term in terms:
        # Does the term exist in the collection?
        try:
            offset, size = vocab[term]

            postings_length = size / 8
            # Compute the IDF component of BM25 as log(N/n).
            # if IDF == 0 then don't process this postings list as the BM25 contribution of this term will be zero.
            idf = math.log(len(doc_lengths) / (postings_length))

            # Seek and read the postings list
            for docid, freq in struct.iter_unpack('ii', contents_postings[offset:offset+size]):
                # Process the postings list by simply adding the BM25 component for this document into the accumulators array
                rsv = idf * ((freq * (k1 + 1)) / (freq + k1 * (1 - b + b * (doc_lengths[docid] / average_length))))
                current_rsv = accumulators[docid][0]
                accumulators[docid] = (current_rsv + rsv, docid)
        except KeyError:
            pass

    # Sort the results list. Tie break on the document ID.
    accumulators.sort(reverse=True)

    # Print the (at most) top 1000 documents in the results list in TREC eval format which is:
    # query-id Q0 document-id rank score run-name
    for i, (rsv, docid) in enumerate(accumulators, start=1):
        if rsv == 0 or i == 1001:
            break
        print("{} Q0 {} {} {:.4f} JASSjr".format(query_id, doc_ids[docid][:-1], i, rsv))
