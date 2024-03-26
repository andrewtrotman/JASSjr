#!/usr/bin/env -S ERL_FLAGS="+B +hms 1000000" elixir

defmodule Index do
  defstruct average_length: 0, docnos: [], lengths: [], vocab: %{}, postings: nil
end

defmodule SearchEngine do
  def read_postings(index, { where, count}) do
    k1 = 0.9 # BM25 k1 parameter
    b = 0.4 # BM25 b parameter

    {:ok, data} = :file.pread(index.postings, where, count)
    postings = for <<docno::native-32, freq::native-32 <- data>>, into: %{}, do: {docno, freq}
    Map.new(postings, fn {docno, freq} ->
      idf = :math.log(length(index.lengths) / Enum.count(postings))
      rsv = idf * ((freq * (k1 + 1)) / (freq + k1 * (1 - b + b * (Enum.at(index.lengths, docno) / index.average_length))))
      {docno, rsv}
    end)
  end

  def search(index, query) do
    query = String.split(query)
    [ head | tail ] = query
    query = case Integer.parse(head) do
      :error -> query
      _ -> tail
    end
    results = Enum.map(query, fn term ->
      case Map.fetch(index.vocab, term) do
        {:ok, loc} -> read_postings(index, loc)
        :error -> %{}
      end
    end)
    Enum.reduce(results, fn x, acc ->
      Map.merge(acc, x, fn _k, v1, v2 -> v1 + v2 end)
    end)
  end

  def print(index, results) do
    results
    |> Map.to_list
    |> Enum.sort(fn {_, tf1}, {_, tf2} -> tf1 >= tf2 end)
    |> Enum.take(1000)
    |> Enum.with_index
    |> Enum.each(fn {{res, tf}, i} ->
      docno = Enum.at(index.docnos, res)
      IO.puts("0 Q0 #{docno} #{i+1} #{:io_lib.format("~.4f", [tf])} JASSjr")
    end)
  end

  def accept_input(index) do
    query = IO.gets("")
    if query != :eof do
      results = search(index, query)
      print(index, results)
      accept_input(index)
    end
  end

  def start() do
    docnos = File.read!("docids.bin") |> String.split
    lengths = for <<x::native-32 <- File.read!("lengths.bin")>>, do: x
    average_length = Enum.sum(lengths) / length(lengths)
    vocab = for <<len::8, term::binary-size(len), 0::8, post_where::native-32, post_len::native-32 <- File.read!("vocab.bin")>>, into: %{}, do: {term, {post_where, post_len}}

    File.open!("postings.bin", fn postings ->
      accept_input(%Index{average_length: average_length, docnos: docnos, lengths: lengths, vocab: vocab, postings: postings})
    end)
  end
end

SearchEngine.start()
