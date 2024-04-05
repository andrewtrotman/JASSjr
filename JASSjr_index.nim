#!/usr/bin/env -S nim r --hints:off

# Copyright (c) 2024 Vaughan Kitchen
# Minimalistic BM25 search engine.

import std/cmdline
import std/os
import std/re
import std/strformat
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

var docid = -1
var document_length = 0
var push_next = false # is the next token the primary key?

for line in lines(commandLineParams()[0]):
  for token in line.findall(re"[a-zA-Z0-9][a-zA-Z0-9-]*|<[^>]*>"):
    echo(token)
