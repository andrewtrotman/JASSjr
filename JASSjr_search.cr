#!/usr/bin/env crystal

# Copyright (c) 2024 Vaughan Kitchen
# Minimalistic BM25 search engine.

k1 = 0.9 # BM25 k1 parameter
b = 0.4 # BM25 b parameter

doc_ids = File.read_lines("docids.bin", chomp: true) # Read the primary_keys

# Read the document lengths
doc_lengths = [] of Int32
File.open("lengths.bin") do |file|
  loop do
    doc_lengths << file.read_bytes(Int32)
  rescue IO::EOFError
    break
  end
end

# Compute the average document length for BM25
average_length = doc_lengths.sum.to_f / doc_lengths.size

vocab = {} of String => Tuple(Int32, Int32)

# decode the vocabulary (unsigned byte length, string, '\0', 4 byte signed where, 4 signed byte size)
File.open("vocab.bin") do |file|
  loop do
    length = file.read_byte
    break if length.nil?

    term = file.read_string(length)
    file.read_byte # Null terminated

    where = file.read_bytes(Int32)
    size = file.read_bytes(Int32)

    vocab[term] = {where, size}
  rescue IO::EOFError
    break
  end
end

# Open the postings list file
postings_fh = File.open("postings.bin")

# Search (one query per line)
loop do
  query = gets
  break if query.nil?

  query = query.split

  query_id = 0
  accumulators = Array.new(doc_ids.size) { |i| {0.0, i} }

  # If the first token is a number then assume a TREC query number, and skip it
  begin
    query_id = query[0].to_i
    query.shift
  rescue ArgumentError
  end

  query.each do |term|
    offset, size = vocab[term]
    next if offset.nil? # Does the term exist in the collection?

    # Seek and read the postings list
    postings = [] of Int32
    postings_fh.read_at(offset, size) do |io|
      loop do
        postings << io.read_bytes(Int32)
      rescue IO::EOFError
        break
      end
    end

    # Compute the IDF component of BM25 as log(N/n).
    idf = Math.log(doc_ids.size.to_f / (postings.size / 2))

    # Process the postings list by simply adding the BM25 component for this document into the accumulators array
    postings.each_slice(2) do |pair|
      docid, tf = pair
      rsv = idf * ((tf * (k1 + 1)) / (tf + k1 * (1 - b + b * (doc_lengths[docid] / average_length))))
      prev = accumulators[docid]
      accumulators[docid] = {prev[0] + rsv, prev[1]}
    end
  end

  # Sort the results list. Tie break on the document ID.
  accumulators.sort!.reverse!

  # Print the (at most) top 1000 documents in the results list in TREC eval format which is:
  # query-id Q0 document-id rank score run-name
  accumulators.take_while { |pair| pair[0] > 0 }.each_with_index do |(rsv, docid), i|
    break if i == 1000
    puts("#{query_id} Q0 #{doc_ids[docid]} #{i+1} #{"%.4f" % rsv} JASSjr")
  end
end
