#!/usr/bin/env -S nim r --hints:off -d:release

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

# Read the primary_keys
let doc_ids = readFile("docids.bin").strip().splitLines()

# Read the document lengths
var doc_lengths: seq[int32]
let doc_lengths_strm = newFileStream("lengths.bin", fmRead)

while not doc_lengths_strm.atEnd():
  let length = doc_lengths_strm.readInt32()
  doc_lengths.add(length)

doc_lengths_strm.close()

# Compute the average document length for BM25
let average_length = doc_lengths.foldl(a + b) / len(doc_lengths)

var postings: seq[tuple[docid: int32, tf: int32]]

# decode the vocabulary (one byte length, string, '\0', 4 byte where, 4 byte size)
var vocab = initTable[string, tuple[where: int32, length: int32]]()
let vocab_strm = newFileStream("vocab.bin", fmRead)

while not vocab_strm.atEnd():
  let term_length = vocab_strm.readUint8()
  let term = vocab_strm.readStr(int(term_length))
  discard vocab_strm.readUint8()
  let where = vocab_strm.readInt32()
  let length = vocab_strm.readInt32()
  vocab[term] = (where, length)

vocab_strm.close()

# array of rsv values
var accumulators = newSeq[(float, int)](len(doc_ids))

# Search (one query per line)
try:
  while true:
    var query_id = 0

    let query = readLine(stdin)

    var terms = query.splitWhitespace()
    if len(terms) == 0:
      continue

    # If the first token is a number then assume a TREC query number, and skip it
    try:
      query_id = parseInt(terms[0])
      terms.delete(0)
    except ValueError:
      discard

    for i, _ in accumulators:
      accumulators[i] = (0, i)

    for term in terms:
      # Does the term exist in the collection?
      try:
        let (where, length) = vocab[term]

        # Seek and read the postings list
        postings.setLen(0)

        let postings_fh = open("postings.bin")
        postings_fh.setFilePos(where)

        let postings_strm = newFileStream(postings_fh)

        for i in 0 .. length div 8 - 1:
          let docid = postings_strm.readInt32()
          let tf = postings_strm.readInt32()
          postings.add((docid, tf))

        postings_strm.close() # strm owns fh

        # Compute the IDF component of BM25 as log(N/n).
        let idf = ln(len(doc_lengths) / len(postings))

        for (docid, tf) in postings:
          # Process the postings list by simply adding the BM25 component for this document into the accumulators array
          let rsv = idf * float(tf) * (k1 + 1) / (float(tf) + k1 * (1 - b + b * (float(doc_lengths[docid]) / average_length)))
          accumulators[docid][0] += rsv
      except KeyError:
        discard

    # Sort the results list. Tie break on the document ID.
    accumulators.sort(Descending)

    # Print the (at most) top 1000 documents in the results list in TREC eval format which is:
    # query-id Q0 document-id rank score run-name
    for i, (rsv, docid) in accumulators:
      if rsv == 0 or i == 1000:
        break
      echo(fmt"{query_id} Q0 {doc_ids[docid]} {i+1} {rsv:.4f} JASSjr")
except EOFError:
  discard
