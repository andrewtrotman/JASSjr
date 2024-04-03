#!/usr/bin/env -S nim r --hints:off

# Copyright (c) 2024 Vaughan Kitchen
# Minimalistic BM25 search engine.

import std/streams
import std/strformat
import std/strutils
import std/tables

const k1 = 0.9 # BM25 k1 parameter
const b = 0.4 # BM25 b parameter

let doc_ids = readFile("docids.bin").strip.splitLines

var doc_lengths: seq[int32]
let doc_lengths_strm = newFileStream("lengths.bin", fmRead)

while not doc_lengths_strm.atEnd:
  let length = doc_lengths_strm.readInt32
  doc_lengths.add(length)

doc_lengths_strm.close()

var postings: seq[tuple[docid: int32, tf: int32]]
let postings_strm = newFileStream("postings.bin", fmRead)

while not postings_strm.atEnd:
  let docid = postings_strm.readInt32
  let tf = postings_strm.readInt32
  postings.add((docid, tf))

postings_strm.close()

var vocab = initTable[string, tuple[where: int32, length: int32]]()
let vocab_strm = newFileStream("vocab.bin", fmRead)
while not vocab_strm.atEnd:
  let term_length = vocab_strm.readUint8
  let term = vocab_strm.readStr(int(term_length))
  discard vocab_strm.readUint8
  let where = vocab_strm.readInt32
  let length = vocab_strm.readInt32
  vocab[term] = (where div 8, length div 8)

vocab_strm.close()

let query = readLine(stdin).strip
let (where, length) = vocab[query]
for i, (docid, tf) in postings[where..where+length-1]:
  echo(fmt"0 Q0 {doc_ids[docid]} {i+1} {tf} JASSjr")
