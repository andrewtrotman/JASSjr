#!/usr/bin/env crystal

# Copyright (c) 2024 Vaughan Kitchen
# Minimalistic BM25 search engine.

# Make sure we have one parameter, the filename
abort("Usage: #{PROGRAM_NAME} <infile.xml>") if ARGV.size != 1

vocab = {} of String => Array(Int32) # the in-memory index
doc_ids = [] of String # the primary keys
doc_lengths = [] of Int32 # hold the length of each document

docid = -1
document_length = 0
push_next = false # is the next token the primary key?

File.each_line(ARGV[0]) do |line|
  # A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
  # TREC <DOCNO> primary keys have a hyphen in them
  line.scan(/[a-zA-Z0-9][a-zA-Z0-9-]*|<[^>]*>/).each do |token|
    token = token.to_s
    # If we see a <DOC> tag then we're at the start of the next document
    if token == "<DOC>"
      # Save the previous document length
      doc_lengths << document_length if docid != -1
      # Move on to the next document
      docid += 1
      document_length = 0
      puts("#{docid} documents indexed") if docid % 1000 == 0
    end
    # If the last token we saw was a <DOCNO> then the next token is the primary key
    if push_next
      doc_ids << token
      push_next = false
    end
    push_next = true if token == "<DOCNO>"
    # Don't index XML tags
    next if token[0] == '<'

    # Lower case the string
    token = token.downcase

    # Truncate any long tokens at 255 charactes (so that the length can be stored first and in a single byte)
    token = token[0, 255]

    # Add the posting to the in-memory index
    vocab[token] = [] of Int32 if !vocab[token]? # if the term isn't in the vocab yet
    postings_list = vocab[token]
    if postings_list.size == 0 || postings_list[-2] != docid
      postings_list << docid << 1 # if the docno for this occurence has changed then create a new <d,tf> pair
    else
      postings_list[-1] += 1 # else increase the tf
    end

    # Compute the document length
    document_length += 1
  end
end

# If we didn't index any documents then we're done.
exit if docid == -1

# Save the final document length
doc_lengths << document_length

# Tell the user we've got to the end of parsing
puts("Indexed #{docid + 1} documents. Serialising...")

# Store the primary keys
File.open("docids.bin", "w") do |file|
  doc_ids.each { |docid| file.puts(docid) }
end

postings_fp = File.open("postings.bin", "wb")
vocab_fp = File.open("vocab.bin", "wb")

vocab.each do |term, postings|
  # Write the postings list to one file
  where = postings_fp.pos
  postings_fp.write(postings.to_unsafe.as(UInt8*).to_slice(postings.size * sizeof(Int32)))

  # Write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
  vocab_fp.write_byte(term.size.to_u8)
  vocab_fp.write_string(term.to_slice)
  vocab_fp.write_byte(0)
  vocab_fp.write_bytes(where.to_i32)
  vocab_fp.write_bytes((postings.size * 4).to_i32)
end

# Store the document lengths
File.open("lengths.bin", "w") { |file| file.write(doc_lengths.to_unsafe.as(UInt8*).to_slice(doc_lengths.size * sizeof(Int32))) }

# Clean up
postings_fp.close
vocab_fp.close
