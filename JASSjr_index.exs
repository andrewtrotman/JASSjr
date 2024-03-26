#!/usr/bin/env -S ERL_FLAGS="+B +hms 1000000" elixir

defmodule Postings do
  defstruct length: 0, docno: 0, lengths: [], docnos: [], terms: %{}

  def append(postings, term) do
      docid = postings.docno - 1
      %Postings{postings | length: postings.length + 1, terms: Map.update(postings.terms, term, %{ docid => 1 },
        fn docnos -> Map.update(docnos, docid, 1, fn tf -> tf + 1 end) end) }
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
      if index.docno |> rem(1000) == 0 do
        IO.puts("#{index.docno} documents indexed")
      end

      {_, file} = String.split_at(file, 7)
      [docno, file] = String.split(file, "</DOCNO>", parts: 2)
      docno = String.trim(docno)

      index = if index.docno > 0 do
        %Postings{index | length: 0, lengths: [ index.length | index.lengths], docno: index.docno + 1, docnos: [ docno | index.docnos]}
      else
        %Postings{index | docno: index.docno + 1, docnos: [ docno | index.docnos]}
      end

      index = Postings.append(index, docno)

      parse(file, index)
    else
      consume_tag(file, index)
    end
  end

  def parse_number(file, index, val \\ <<>>)
  def parse_number(<<>>, index, val), do: Postings.append(index, val)
  def parse_number(<<head, tail::binary>> = file, index, val) do
    case head do
      # Numeric
      x when x in 48..57 -> parse_number(tail, index, val <> <<x>>)
      _ -> parse(file, Postings.append(index, val))
    end
  end

  def parse_string(file, index, val \\ <<>>)
  def parse_string(<<>>, index, val), do: Postings.append(index, val)
  def parse_string(<<head, tail::binary>> = file, index, val) do
    case head do
      # Uppercase
      x when x in 65..90 -> parse_string(tail, index, val <> <<x+32>>)
      # Lowercase
      x when x in 97..122 -> parse_string(tail, index, val <> <<x>>)
      _ -> parse(file, Postings.append(index, val))
    end
  end

  def parse(file, index \\ %Postings{})
  def parse(<<>>, index), do: index
  def parse(<<head, tail::binary>> = file, index) do
    case head do
      # Tag '<'
      60 -> parse_tag(file, index)
      # Numeric
      x when x in 48..57 -> parse_number(file, index)
      # Uppercase
      x when x in 65..90 -> parse_string(file, index)
      # Lowercase
      x when x in 97..122 -> parse_string(file, index)
      # Other
      _ -> parse(tail, index)
    end
  end

  def serialise(index) do
    index = %Postings{index | lengths: [ index.length | index.lengths]}
    docnos = Enum.reverse(index.docnos)

    File.open!("docids.bin", [:write], fn file ->
      Enum.each(docnos, fn docno ->
        IO.write(file, "#{docno}\n")
      end)
    end)
    vocab = File.open!("vocab.bin", [:write])
    postings = File.open!("postings.bin", [:write])
    Enum.each(index.terms, fn {k, v} ->
      posts = Enum.flat_map(Map.to_list(v), fn t -> Tuple.to_list(t) end)
      posts = for x <- posts, do: <<x::native-32>>, into: <<>>
      {:ok, where} = :file.position(postings, {:cur, 0})
      IO.binwrite(postings, posts)
      IO.binwrite(vocab, <<byte_size(k)::8, k::binary, 0::8, where::native-32, byte_size(posts)::native-32>>)
    end)
    :ok = File.close(postings)
    :ok = File.close(vocab)

    lengths = Enum.reverse(index.lengths)
    lengths = for x <- lengths, do: <<x::native-32>>, into: <<>>
    File.open!("lengths.bin", [:write], fn file ->
      IO.binwrite(file, lengths)
    end)
  end
end

if length(System.argv()) != 1 do
  IO.puts("Usage: ./JASSjr_index.exs <infile.xml>")
  System.halt()
end

[ filename | _ ] = System.argv()

file = File.read!(filename)

index = Indexer.parse(file)
IO.puts("Indexed #{index.docno} documents. Serialising...")
Indexer.serialise(index)
