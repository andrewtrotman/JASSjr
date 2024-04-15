#!/usr/bin/env -S ERL_FLAGS="+B +hms 1073741824" elixir
# +B disables interrupt handler
# +hms sets default heap size (8gb)

# Copyright (c) 2024 Vaughan Kitchen
# Minimalistic BM25 search engine.

defmodule Index do
  defstruct length: 0, # length of currently indexing document
  docno: 0, # cache last index into primary keys
  lengths: [], # hold the length of each document
  docnos: [], # the primary keys
  terms: %{} # the in-memory index (terms => <tf, docid>)

  # Add the posting to the in-memory index
  def append(index, term) do
      docid = index.docno - 1
      %Index{index | length: index.length + 1, terms: Map.update(index.terms, term, [ 1, docid ], fn [ tf | [ doc | tail ]] = docnos ->
        if doc != docid do
          # if the docno for this occurence has changed then create a new <d,tf> pair
          [ 1 | [ docid | docnos ]]
        else
          # else increase the tf
          [ tf + 1 | [ doc | tail ]]
        end
      end)
    }
  end
end

defmodule Indexer do
  def consume_tag(<<head, tail::binary>>, index) do
    case head do
      # '>'
      62 -> parse(tail, index)
      _ -> consume_tag(tail, index)
    end
  end

  def parse_tag(file, index) do
    if String.starts_with?(file, "<DOCNO>") do
      # If this is a <DOCNO> parse the primary key
      if index.docno |> rem(1000) == 0 do
        IO.puts("#{index.docno} documents indexed")
      end

      {_, file} = String.split_at(file, 7)
      [docno, file] = String.split(file, "</DOCNO>", parts: 2)
      docno = String.trim(docno)

      # Move on to the next document
      index = if index.docno > 0 do
        %Index{index | length: 0, lengths: [ index.length | index.lengths], docno: index.docno + 1, docnos: [ docno | index.docnos]}
      else
        %Index{index | docno: index.docno + 1, docnos: [ docno | index.docnos]}
      end

      # Include the primary key as a term to match the other indexers
      index = Index.append(index, docno)

      parse(file, index)
    else
      # Otherwise consume until end of tag
      consume_tag(file, index)
    end
  end

  def parse_alnum(file, index, val \\ <<>>)
  def parse_alnum(<<>>, index, val), do: Index.append(index, val)
  def parse_alnum(<<head, tail::binary>> = file, index, val) do
    case head do
      # Numeric
      x when x in 48..57 -> parse_alnum(tail, index, val <> <<x>>)
      # Uppercase
      x when x in 65..90 -> parse_alnum(tail, index, val <> <<x+32>>) # lower case the string
      # Lowercase
      x when x in 97..122 -> parse_alnum(tail, index, val <> <<x>>)
      # Hyphen is allowed after the initial character
      45 -> parse_alnum(tail, index, val <> <<head>>)
      _ -> parse(file, Index.append(index, val))
    end
  end

  # One-character lookahead lexical analyser
  def parse(file, index \\ %Index{})
  def parse(<<>>, index), do: index
  def parse(<<head, tail::binary>> = file, index) do
    # A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
    case head do
      # Tag '<'
      60 -> parse_tag(file, index)
      # Numeric
      x when x in 48..57 -> parse_alnum(file, index)
      # Uppercase
      x when x in 65..90 -> parse_alnum(file, index)
      # Lowercase
      x when x in 97..122 -> parse_alnum(file, index)
      # Skip over whitespace and punctuation
      _ -> parse(tail, index)
    end
  end

  # serialise the in-memory index to disk
  def serialise(index) do
    # Save the final document length
    index = %Index{index | lengths: [ index.length | index.lengths]}
    docnos = Enum.reverse(index.docnos)

    # store the primary keys
    File.open!("docids.bin", [:write], fn file ->
      Enum.each(docnos, fn docno ->
        IO.write(file, "#{docno}\n")
      end)
    end)
    vocab = File.open!("vocab.bin", [:write])
    postings = File.open!("postings.bin", [:write])
    Enum.each(index.terms, fn {term, posts} ->
      # write the postings list to one file
      posts = Enum.reverse(posts)
      posts = for x <- posts, do: <<x::native-32>>, into: <<>>
      {:ok, where} = :file.position(postings, {:cur, 0})
      IO.binwrite(postings, posts)
      # write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
      IO.binwrite(vocab, <<byte_size(term)::8, term::binary, 0::8, where::native-32, byte_size(posts)::native-32>>)
    end)
    # clean up
    :ok = File.close(postings)
    :ok = File.close(vocab)

    # store the document lengths
    lengths = Enum.reverse(index.lengths)
    lengths = for x <- lengths, do: <<x::native-32>>, into: <<>>
    File.open!("lengths.bin", [:write], fn file ->
      IO.binwrite(file, lengths)
    end)
  end
end

# Make sure we have one paramter, the filename
if length(System.argv()) != 1 do
  IO.puts("Usage: ./JASSjr_index.exs <infile.xml>")
  System.halt()
end

# Read the file to index
[ filename | _ ] = System.argv()
file = File.read!(filename)

index = Indexer.parse(file)
IO.puts("Indexed #{index.docno} documents. Serialising...") # tell the user we've got to the end of parsing
Indexer.serialise(index)
