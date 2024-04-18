#!/usr/bin/env python3

# index_stats.py
# Copyright (c) 2024 Vaughan Kitchen
# Minimalistic BM25 search engine.

from array import array
import struct

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
doc_lengths = array('i', read_file('lengths.bin')) # Read the document lengths
doc_ids = read_lines('docids.bin') # Read the primary_keys

# Compute the average document length for BM25
average_length = sum(doc_lengths) / len(doc_lengths)
vocab = {}

# Build the vocabulary in memory
for word, offset, size in decode_vocab(contents_vocab):
    vocab[word] = (offset, size)

print("Num documents: ", len(doc_ids))
print("Average doc len: ", average_length)
print("Shortest doc: ", min(doc_lengths))
print("Longest doc: ", max(doc_lengths))
print("Num terms: ", len(vocab))

best_key = ""
best_so_far = 0
for key, value in vocab.items():
    if (value[1] > best_so_far):
        best_key = key
        best_so_far = value[1]

print("Most common term:", best_key)
