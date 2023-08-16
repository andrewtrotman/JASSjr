#!/usr/bin/env python3

from array import array
from collections import deque
import math
import struct

k1 = 0.9 # BM25 k1 parameter
b = 0.4 # BM25 b parameter

def read_file(filename):
    with open(filename, mode='rb') as file:
            return file.read()

def read_lines(filename):
    with open(filename) as file:
            return file.readlines()

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
doc_lengths = array('i', read_file('lengths.bin'))
doc_ids = read_lines('docids.bin')

average_length = sum(doc_lengths) / len(doc_lengths)
vocab = {}

for word, offset, size in decode_vocab(contents_vocab):
    vocab[word] = (offset, size)

try:
    query = input()
    while query:
        query_id = 0
        accumulators = [(0, 0)] * len(doc_lengths)

        terms = deque(query.split())
        if terms[0].isnumeric():
            query_id = terms.popleft()

        for term in terms:
            try:
                offset, size = vocab[term]

                postings_length = size / 8
                idf = math.log(len(doc_lengths) / (postings_length))

                for docid, freq in struct.iter_unpack('ii', contents_postings[offset:offset+size]):
                    rsv = idf * ((freq * (k1 + 1)) / (freq + k1 * (1 - b + b * (doc_lengths[docid] / average_length))))
                    current_rsv = accumulators[docid][1]
                    accumulators[docid] = (docid, current_rsv + rsv)
            except KeyError:
                pass

        accumulators.sort(key=lambda x: x[1], reverse=True)

        for i, (docid, rsv) in enumerate(accumulators, start=1):
            if rsv == 0 or i == 1001:
                break
            print("{} Q0 {} {} {:.4f} JASSjr".format(query_id, doc_ids[docid][:-1], i, rsv))

        query = input()
except EOFError:
    pass
