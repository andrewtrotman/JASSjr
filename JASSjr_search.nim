#!/usr/bin/env -S nim r --hints:off

# Copyright (c) 2024 Vaughan Kitchen
# Minimalistic BM25 search engine.

import std/algorithm
import std/math
import std/sequtils
import std/streams
import std/strformat
import std/strutils
import std/tables

const k1 = 0.9 # BM25 k1 parameter
const b = 0.4 # BM25 b parameter

let doc_ids = readFile("docids.bin").strip().splitLines()

var doc_lengths: seq[int32]
let doc_lengths_strm = newFileStream("lengths.bin", fmRead)

while not doc_lengths_strm.atEnd():
  let length = doc_lengths_strm.readInt32()
  doc_lengths.add(length)

doc_lengths_strm.close()

let average_length = doc_lengths.foldl(a + b) / len(doc_lengths)

var postings: seq[tuple[docid: int32, tf: int32]]

var vocab = initTable[string, tuple[where: int32, length: int32]]()
let vocab_strm = newFileStream("vocab.bin", fmRead)

while not vocab_strm.atEnd():
  let term_length = vocab_strm.readUint8()
  let term = vocab_strm.readStr(int(term_length))
  discard vocab_strm.readUint8()
  let where = vocab_strm.readInt32()
  let length = vocab_strm.readInt32()
  vocab[term] = (where, length div 8)

vocab_strm.close()

var accumulators = newSeq[(float, int)](len(doc_ids))
for i, _ in accumulators:
  accumulators[i][1] = i

try:
  while true:
    let query = readLine(stdin)

    let terms = query.splitWhitespace()
    if len(terms) == 0:
      continue

    for i, _ in accumulators:
      accumulators[i][0] = 0

    for term in terms:
      try:
        let (where, length) = vocab[term]

        postings.setLen(0)

        let postings_fh = open("postings.bin")
        postings_fh.setFilePos(where)

        let postings_strm = newFileStream(postings_fh)

        for i in 0 .. length:
          let docid = postings_strm.readInt32()
          let tf = postings_strm.readInt32()
          postings.add((docid, tf))

        postings_strm.close() # strm owns fh

        let idf = ln(len(doc_lengths) / len(postings))

        for (docid, tf) in postings:
          let rsv = idf * float(tf) * (k1 + 1) / (float(tf) + k1 * (1 - b + b * (float(doc_lengths[docid]) / average_length)))
          accumulators[docid][0] += rsv
      except KeyError:
        discard

    accumulators.sort(Descending)

    for i, (rsv, docid) in accumulators:
      if rsv == 0 or i == 10:
        break
      echo(fmt"0 Q0 {doc_ids[docid]} {i+1} {rsv} JASSjr")
except EOFError:
  discard
