#!/usr/bin/env -S ERL_FLAGS="+B +hms 1000000" elixir

defmodule Postings do
  defstruct length: 0, lengths: [], docnos: [], terms: %{}

  def append(postings, term) do
      docid = length(postings.docnos) - 1
      %Postings{postings | length: postings.length + 1, terms: Map.update(postings.terms, term, %{ docid => 1 },
        fn docnos -> Map.update(docnos, docid, 1, fn tf -> tf + 1 end) end) }
  end
end

defmodule Indexer do
  def consume_tag(<<head, tail::binary>>, result) do
    case head do
      # '>'
      62 -> parse(tail, result)
      _ -> consume_tag(tail, result)
    end
  end

  def parse_tag(file, result) do
    if String.starts_with?(file, "<DOCNO>") do
      {_, file} = String.split_at(file, 7)
      [docno, file] = String.split(file, "</DOCNO>", parts: 2)
      docno = String.trim(docno)

      result = if length(result.docnos) > 0 do
        %Postings{result | length: 0, lengths: [ result.length | result.lengths], docnos: [ docno | result.docnos]}
      else
        %Postings{result | docnos: [ docno | result.docnos]}
      end

      if length(result.docnos) |> rem(1000) == 0 do
        IO.puts("#{length(result.docnos)} documents indexed")
      end

      parse(file, result)
    else
      consume_tag(file, result)
    end
  end

  def parse_number(file, result, val \\ <<>>)
  def parse_number(<<>>, result, val), do: Postings.append(result, val)
  def parse_number(<<head, tail::binary>> = file, result, val) do
    case head do
      # Numeric
      x when x in 48..57 -> parse_number(tail, result, val <> <<x>>)
      _ -> parse(file, Postings.append(result, val))
    end
  end

  def parse_string(file, result, val \\ <<>>)
  def parse_string(<<>>, result, val), do: Postings.append(result, val)
  def parse_string(<<head, tail::binary>> = file, result, val) do
    case head do
      # Uppercase
      x when x in 65..90 -> parse_string(tail, result, val <> <<x+32>>)
      # Lowercase
      x when x in 97..122 -> parse_string(tail, result, val <> <<x>>)
      _ -> parse(file, Postings.append(result, val))
    end
  end

  def parse(file, result \\ %Postings{})
  def parse(<<>>, result), do: result
  def parse(<<head, tail::binary>> = file, result) do
    case head do
      # Tag '<'
      60 -> parse_tag(file, result)
      # Numeric
      x when x in 48..57 -> parse_number(file, result)
      # Uppercase
      x when x in 65..90 -> parse_string(file, result)
      # Lowercase
      x when x in 97..122 -> parse_string(file, result)
      # Other
      _ -> parse(tail, result)
    end
  end

  def serialise(result) do
    result = %Postings{result | lengths: [ result.length | result.lengths]}

    File.open!("docids.bin", [:write], fn file ->
      Enum.each(result.docnos, fn docno ->
        IO.write(file, "#{docno}\n")
      end)
    end)
    vocab = File.open!("vocab.bin", [:write])
    postings = File.open!("postings.bin", [:write])
    Enum.each(result.terms, fn {k, v} ->
      posts = Enum.flat_map(Map.to_list(v), fn t -> Tuple.to_list(t) end)
      posts = for x <- posts, do: <<x::native-32>>, into: <<>>
      {:ok, where} = :file.position(postings, {:cur, 0})
      IO.binwrite(postings, posts)
      IO.binwrite(vocab, <<byte_size(k)::8, k::binary, 0::8, where::native-32, byte_size(posts)::native-32>>)
    end)
    :ok = File.close(postings)
    :ok = File.close(vocab)

    lengths = for x <- result.lengths, do: <<x::native-32>>, into: <<>>
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

result = Indexer.parse(file)
Indexer.serialise(result)
# IO.inspect(result)
