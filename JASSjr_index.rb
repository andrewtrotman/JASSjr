#!/usr/bin/env ruby

# Copyright (c) 2024 Vaughan Kitchen
# Minimalistic BM25 search engine.

# Make sure we have one parameter, the filename
abort("Usage: #{$0} <infile.xml>") if ARGV.length != 1

vocab = {} # the in-memory index
doc_ids = [] # the primary keys
doc_lengths = [] # hold the length of each document

docid = -1
document_length = 0
push_next = false # is the next token the primary key?

File.foreach(ARGV[0]) do |line|
  # A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
  # TREC <DOCNO> primary keys have a hyphen in them
  line.scan(/[a-zA-Z0-9][a-zA-Z0-9-]*|<[^>]*>/).each do |token|
    # If we see a <DOC> tag then we're at the start of the next document
    if token == "<DOC>"
      # Save the previous document length
      doc_lengths << document_length if docid != -1
      # Move on to the next document
      docid += 1
      document_length = 0
      puts("#{docid} documents indexed") if docid % 1000 == 0
    end
    # if the last token we saw was a <DOCNO> then the next token is the primary key
    if push_next
      doc_ids << token.dup # Duplicate so that the primary key doesn't get downcased
      push_next = false
    end
    push_next = true if token == "<DOCNO>"
    # Don't index XML tags
    next if token[0] == "<"

    # lower case the string
    token.downcase!

    # truncate any long tokens at 255 charactes (so that the length can be stored first and in a single byte)
    token = token.slice(0, 255)

    # add the posting to the in-memory index
    vocab[token] = [] if !vocab.key?(token) # if the term isn't in the vocab yet
    postings_list = vocab[token]
    if postings_list.length == 0 || postings_list[-2] != docid
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

# tell the user we've got to the end of parsing
puts("Indexed #{docid + 1} documents. Serialising...")

# store the primary keys
File.open("docids.bin", "w") { |file| file.puts(doc_ids) }

postings_fp = File.open("postings.bin", "wb")
vocab_fp = File.open("vocab.bin", "wb")

vocab.each do |term, postings|
  # write the postings list to one file
  where = postings_fp.pos
  postings_fp.write(postings.pack("l*"))

  # write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
  vocab_fp.write([term.length].pack("C"))
  vocab_fp.write(term)
  vocab_fp.write("\0")
  vocab_fp.write([where, postings.length * 4].pack("ll"))
end

# store the document lengths
File.open("lengths.bin", "w") { |file| file.write(doc_lengths.pack("l*")) }

# clean up
postings_fp.close
vocab_fp.close
