#!/usr/bin/env -S ERL_FLAGS="+hms 1000000" elixir

defmodule Postings do
  defstruct docnos: [], terms: %{}
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

      result = %{result | docnos: [ docno | result.docnos]}

      if length(result.docnos) |> rem(1000) == 0 do
        IO.puts("#{length(result.docnos)} documents indexed")
      end

      parse(file, result)
    else
      consume_tag(file, result)
    end
  end

  def parse_number(file, result, val \\ <<>>)
  # TODO push final
  def parse_number(<<>>, result, _val), do: result
  def parse_number(<<head, tail::binary>> = file, result, val) do
    case head do
      # Numeric
      x when x in 48..57 -> parse_number(tail, result, val <> <<x>>)
      _ ->
        [ docno | _ ] = result.docnos
        result = %{result | terms: Map.update(result.terms, val, %{ docno => 1 },
          fn docnos -> Map.update(docnos, docno, 1, fn tf -> tf + 1 end) end) }
        parse(file, result)
    end
  end

  def parse_string(file, result, val \\ <<>>)
  # TODO push final
  def parse_string(<<>>, result, _val), do: result
  def parse_string(<<head, tail::binary>> = file, result, val) do
    case head do
      # Uppercase
      x when x in 65..90 -> parse_string(tail, result, val <> <<x+32>>)
      # Lowercase
      x when x in 97..122 -> parse_string(tail, result, val <> <<x>>)
      _ ->
        [ docno | _ ] = result.docnos
        result = %{result | terms: Map.update(result.terms, val, %{ docno => 1 },
          fn docnos -> Map.update(docnos, docno, 1, fn tf -> tf + 1 end) end) }
        parse(file, result)
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
end

if length(System.argv()) != 1 do
  IO.puts("Usage: ./JASSjr_index.exs <infile.xml>")
  System.halt()
end

[ filename | _ ] = System.argv()

file = File.read!(filename)

result = Indexer.parse(file)
IO.inspect(result)
