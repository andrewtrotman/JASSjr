#!/usr/bin/env python3

import struct

def read_file(filename):
    with open(filename, mode='rb') as file:
            return file.read()

def read_lines(filename):
    with open(filename, mode='rb') as file:
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

        yield word, where, size

contents_vocab = read_file('vocab.bin')
contents_lengths = read_file('lengths.bin')
contents_postings = read_file('postings.bin')

docids = read_lines('docids.bin')

vocab = {}
for word, offset, size in decode_vocab(contents_vocab):
    vocab[word.decode()] = (offset, size)

query = input('> ')

offset, size = vocab[query]

for pair in struct.iter_unpack('ii', contents_postings[offset:offset+size]):
    print(docids[pair[0]], pair[1])
