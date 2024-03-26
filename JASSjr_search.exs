#!/usr/bin/env -S ERL_FLAGS="+B +hms 1000000" elixir

defmodule Index do
  defstruct average_length: 0, docnos: [], lengths: [], vocab: %{}, postings: nil
end

defmodule SearchEngine do
  def rsv(index, num_results, docno, freq) do
    k1 = 0.9 # BM25 k1 parameter
    b = 0.4 # BM25 b parameter

    idf = :math.log(:array.size(index.lengths) / num_results)
    idf * ((freq * (k1 + 1)) / (freq + k1 * (1 - b + b * (:array.get(docno, index.lengths) / index.average_length))))
  end

  def read_postings(index, { where, count}) do
    {:ok, data} = :file.pread(index.postings, where, count)
    for <<docno::native-32, freq::native-32 <- data>>, into: %{}, do: {docno, rsv(index, count / 8, docno, freq)}
  end

  def search(index, query) do
    Enum.map(query, fn term ->
      case Map.fetch(index.vocab, term) do
        {:ok, loc} -> read_postings(index, loc)
        :error -> %{}
      end
    end)
    |> Enum.reduce(fn x, acc ->
      Map.merge(acc, x, fn _k, v1, v2 -> v1 + v2 end)
    end)
  end

  def print(results, index, query_id) do
    results
    |> Map.to_list
    |> Enum.sort_by(fn {docid, tf} -> {tf, docid} end, :desc)
    |> Enum.take(1000)
    |> Enum.with_index
    |> Enum.each(fn {{res, tf}, i} ->
      docno = :array.get(res, index.docnos)
      IO.puts("#{query_id} Q0 #{docno} #{i+1} #{:io_lib.format("~.4f", [tf])} JASSjr")
    end)
  end

  def accept_input(index) do
    query = IO.gets("")
    if query != :eof do
      query = String.split(query)
      [ head | tail ] = query
      { query_id, query } = case Integer.parse(head) do
        :error -> { 0, query }
        { id, _ } -> { id, tail }
      end
      search(index, query)
      |> print(index, query_id)
      accept_input(index)
    end
  end

  def start() do
    docnos = :array.from_list(File.read!("docids.bin") |> String.split)
    lengths = :array.from_list(for <<x::native-32 <- File.read!("lengths.bin")>>, do: x)
    average_length = :array.foldl(fn _, val, acc -> acc + val end, 0, lengths) / :array.size(lengths)
    vocab = for <<len::8, term::binary-size(len), 0::8, post_where::native-32, post_len::native-32 <- File.read!("vocab.bin")>>, into: %{}, do: {term, {post_where, post_len}}

    File.open!("postings.bin", fn postings ->
      accept_input(%Index{average_length: average_length, docnos: docnos, lengths: lengths, vocab: vocab, postings: postings})
    end)
  end
end

SearchEngine.start()
