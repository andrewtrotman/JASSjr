#!/usr/bin/env -S nim r --hints:off -d:release

# Copyright (c) 2024 Vaughan Kitchen
# Minimalistic BM25 search engine.

import std/cmdline
import std/os
import std/re
import std/streams
import std/strformat
import std/strutils
import std/tables

# Make sure we have one parameter, the filename
if paramCount() != 1:
  echo(fmt"Usage: { getAppFilename() } <infile.xml>")
  quit()

var vocab = initTable[string, seq[int32]]() # the in-memory index
var doc_ids: seq[string] # the primary keys
var length_vector: seq[int32] # hold the length of each document

# A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
# TREC <DOCNO> primary keys have a hyphen in them

var docid: int32 = -1
var document_length: int32 = 0
var push_next = false # is the next token the primary key?

for line in lines(commandLineParams()[0]):
  for token in line.findall(re"[a-zA-Z0-9][a-zA-Z0-9-]*|<[^>]*>"):
    # If we see a <DOC> tag then we're at the start of the next document
    if token == "<DOC>":
      # Save the previous document length
      if docid != -1:
        length_vector.add(document_length)
      # Move on to the next document
      docid += 1
      document_length = 0
      if docid mod 1000 == 0:
        echo(fmt"{docid} documents indexed")
    # if the last token we saw was a <DOCNO> then the next token is the primary key
    if push_next:
      doc_ids.add(token)
      push_next = false
    if token == "<DOCNO>":
      push_next = true
    # Don't index XML tags
    if token[0] == '<':
      continue

    # lower case the string
    var token2 = token.toLowerAscii()

    # truncate any long tokens at 255 charactes (so that the length can be stored first and in a single byte)
    if len(token2) > 255:
      token2 = token2[0..<255]

    # add the posting to the in-memory index
    if not (token2 in vocab):
      vocab[token2] = newSeq[int32]()

    let postings_list = addr(vocab[token2])
    if len(postings_list[]) == 0 or postings_list[][^2] != docid:
      postings_list[].add(docid)
      postings_list[].add(1)
    else:
      postings_list[][^1] += 1

    # Compute the document length
    document_length += 1

# If we didn't index any documents then we're done.
if docid == -1:
  quit()

# Save the final document length
length_vector.add(document_length)

# tell the user we've got to the end of parsing
echo(fmt"Indexed { docid + 1 } documents. Serialising...")

# store the primary keys
let docids_fh = open("docids.bin", fmWrite)
for docid in doc_ids:
  docids_fh.writeLine(docid)

# serialise the in-memory index to disk
let postings_strm = newFileStream("postings.bin", fmWrite)
let vocab_strm = newFileStream("vocab.bin", fmWrite)
for term, postings in vocab.pairs():
  # write the postings list to one file
  let where = postings_strm.getPosition()
  postings_strm.writeData(addr(postings[0]), len(postings) * sizeof(postings[0]))

  # write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
  vocab_strm.write(uint8(len(term)))
  vocab_strm.write(term)
  vocab_strm.write('\0') # string is null terminated
  vocab_strm.write(int32(where))
  vocab_strm.write(int32(len(postings) * sizeof(postings[0])))

# store the document lengths
let doc_lengths_strm = newFileStream("lengths.bin", fmWrite)
doc_lengths_strm.writeData(addr(length_vector[0]), len(length_vector) * sizeof(length_vector[0]))

# clean up
docids_fh.close()
postings_strm.close()
vocab_strm.close()
doc_lengths_strm.close()
