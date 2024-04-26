#!/usr/bin/env ruby

# Copyright (c) 2024 Vaughan Kitchen
# Minimalistic BM25 search engine.

k1 = 0.9 # BM25 k1 parameter
b = 0.4 # BM25 b parameter

doc_ids = File.readlines("docids.bin", chomp: true) # Read the primary_keys
doc_lengths = File.binread("lengths.bin").unpack("l*") # Read the document lengths
average_length = doc_lengths.sum.to_f / doc_lengths.length
vocab = {}

vocab_raw = File.binread("vocab.bin")
offset = 0

# decode the vocabulary (unsigned byte length, string, '\0', 4 byte signed where, 4 signed byte size)
while offset < vocab_raw.length do
  length = vocab_raw.unpack("C", offset: offset)[0]
  offset += 1

  term = vocab_raw[offset...offset+length]
  offset += length + 1 # Null terminated

  postings_pair = vocab_raw.unpack("ll", offset: offset)
  offset += 8

  vocab[term] = postings_pair
end

# Search (one query per line)
loop do
  query = gets&.split
  break if query.nil?

  query_id = 0
  accumulators = Array.new(doc_ids.length) { |i| [0, i] }

  # If the first token is a number then assume a TREC query number, and skip it
  begin
    query_id = Integer(query[0])
    query.shift
  rescue ArgumentError
  end

  query.each do |term|
    offset, size = vocab[term]
    next if offset.nil? # Does the term exist in the collection?

    # Seek and read the postings list
    postings = File.binread("postings.bin", size, offset).unpack("l*")

    # Compute the IDF component of BM25 as log(N/n).
    idf = Math.log(doc_ids.length.to_f / (postings.length / 2))

    # Process the postings list by simply adding the BM25 component for this document into the accumulators array
    postings.each_slice(2) do |docid, tf|
      rsv = idf * ((tf * (k1 + 1)) / (tf + k1 * (1 - b + b * (doc_lengths[docid] / average_length))))
      accumulators[docid][0] += rsv
    end
  end

  # Sort the results list. Tie break on the document ID.
  accumulators.sort! { |a, b| a[0] == b[0] ? b[1] <=> a[1] : b[0] <=> a[0] }

  # Print the (at most) top 1000 documents in the results list in TREC eval format which is:
  # query-id Q0 document-id rank score run-name
  accumulators.take_while { |rsv, | rsv > 0 }.take(1000).each_with_index do |(rsv, docid), i|
    puts("#{query_id} Q0 #{doc_ids[docid]} #{i+1} #{'%.4f' % rsv} JASSjr")
  end
end
