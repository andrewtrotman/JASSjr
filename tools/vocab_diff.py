#!/usr/bin/env python3

# Copyright (c) 2024 Vaughan Kitchen

import struct
import sys

if len(sys.argv) != 3:
    sys.exit(f"Usage: {sys.argv[0]} <vocab.bin> <vocab.bin>")

def read_file(filename):
    with open(filename, mode='rb') as file:
            return file.read()

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

vocab_a = {}
vocab_b = {}

for word, offset, size in decode_vocab(read_file(sys.argv[1])):
    vocab_a[word] = size

for word, offset, size in decode_vocab(read_file(sys.argv[2])):
    vocab_b[word] = size

terms_a = set(vocab_a.keys())
terms_b = set(vocab_b.keys())

print(f"These terms are only in {sys.argv[1]}")
res = list(terms_a - terms_b)
if len(res) > 100:
    print(res[slice(100)], "...")
else:
    print(res)

print()
print(f"These terms are only in {sys.argv[2]}")
res = list(terms_b - terms_a)
if len(res) > 100:
    print(res[slice(100)], "...")
else:
    print(res)

set_a = set(vocab_a.items())
set_b = set(vocab_b.items())

print()
print(f"These terms have differing sizes")
res = []
if len(vocab_a) < len(vocab_b):
    for term in vocab_a:
        try:
            if vocab_a[term] != vocab_b[term]:
                res.append((term, vocab_a[term], vocab_b[term]))
        except:
            pass
else:
    for term in vocab_b:
        try:
            if vocab_a[term] != vocab_b[term]:
                res.append((term, vocab_a[term], vocab_b[term]))
        except:
            pass
if len(res) > 100:
    print(res[slice(100)], "...")
else:
    print(res)
