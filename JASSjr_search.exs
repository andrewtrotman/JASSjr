#!/usr/bin/env -S ERL_FLAGS="+B +hms 1000000" elixir

# k1 = 0.9 # BM25 k1 parameter
# b = 0.4 # BM25 b parameter

defmodule Index do
  defstruct docnos: [], lengths: [], vocab: %{}, postings: nil
end

defmodule SearchEngine do
  def read_postings(postings, { where, count}) do
    {:ok, data} = :file.pread(postings, where, count)
    for <<docno::native-32, count::native-32 <- data>>, into: %{}, do: {docno, count}
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
        {:ok, loc} -> read_postings(index.postings, loc)
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
      IO.puts("0 Q0 #{docno} #{i+1} #{tf} JASSjr")
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
    vocab = for <<len::8, term::binary-size(len), 0::8, post_where::native-32, post_len::native-32 <- File.read!("vocab.bin")>>, into: %{}, do: {term, {post_where, post_len}}

    File.open!("postings.bin", fn postings ->
      accept_input(%Index{docnos: docnos, lengths: lengths, vocab: vocab, postings: postings})
    end)
  end
end

SearchEngine.start()
