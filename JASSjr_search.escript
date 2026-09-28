#!/usr/bin/env -S ERL_FLAGS="+hms 1000000" escript
%% +hms sets default heap size (8mb)

%% Copyright (c) 2026 Vaughan Kitchen
%% Minimalistic BM25 search engine.

-module(jassjr_search).
-export([main/1]).

-record(index, {
    average_length = 0,
    docnos = [],
    doclengths = [],
    vocab = #{},
    postings_fh = undefined
}).

rsv(Index, NumResults, DocNo, Freq) ->
    K1 = 0.9, %% BM25 k1 parameter
    B = 0.4, %% BM25 b parameter

    %% Compute the IDF component of BM25 as log(N/n)
    IdF = math:log(array:size(Index#index.doclengths) / NumResults),

    IdF * ((Freq * (K1 + 1)) / (Freq + K1 * (1 - B + B * (array:get(DocNo, Index#index.doclengths) / Index#index.average_length)))).

%% Seek and read the postings list
read_postings(Index, {Where, Count}) ->
    {ok, Data} = file:pread(Index#index.postings_fh, Where, Count),
    read_postings(Data, Index, Count / 8, #{}).

read_postings(<<DocNo:32/native, Freq:32/native, Rest/binary>>, Index, Count, Results) ->
    Score = rsv(Index, Count, DocNo, Freq),
    read_postings(Rest, Index, Count, maps:put(DocNo, Score, Results));

read_postings(<<>>, _Index, _Count, Results) ->
    Results.

search(Index, Query) ->
    Results = lists:map(
        fun(Term) ->
            %% Does the term exist in the collection?
            case maps:find(Term, Index#index.vocab) of
                {ok, Entry} ->
                    read_postings(Index, Entry);
                error ->
                    #{}
            end
        end, Query
    ),

    lists:foldl(
        fun(X, Acc) ->
            maps:fold(
                fun(Key, Value, Acc2) ->
                    maps:update_with(Key, fun(OldValue) -> OldValue + Value end, Value, Acc2)
                end, Acc, X
            )
        end, #{}, Results
    ).

print(Results, Index, QueryId) ->
    List = maps:to_list(Results),

    %% Sort the results list
    Sorted = lists:sort(
        fun({DocId1, TF1}, {DocId2, TF2}) ->
            {TF1, DocId1} >= {TF2, DocId2}
        end,
        List
    ),

    Top = lists:sublist(Sorted, 1000),

    print_results(Top, Index, QueryId, 1).

%% Print the (at most) top 1000 documents in the results list in TREC eval format:
%% query-id Q0 document-id rank score run-name
print_results([{DocId, Score} | Rest], Index, QueryId, Rank) ->
    io:format("~p Q0 ~s ~p ~.4f JASSjr~n", [QueryId, array:get(DocId, Index#index.docnos), Rank, Score]),
    print_results(Rest, Index, QueryId, Rank + 1);

print_results([], _Index, _QueryId, _Rank) ->
    ok.

%% Search (one query per line)
accept_input(Index) ->
    case io:get_line("") of
        eof ->
            ok;
        Line ->
            Query = [list_to_binary(X) || X <- string:lexemes(Line, " \t\r\n")],

            [Head | Tail] = Query,

            %% If the first token is a number then assume a TREC query number, and skip it
            {QueryId, SearchQuery} =
                case string:to_integer(Head) of
                    {Id, _} ->
                        {Id, Tail};
                    error ->
                        {0, Query}
                end,

            Results = search(Index, SearchQuery),
            print(Results, Index, QueryId),

            accept_input(Index)
    end.

read_vocab(<<Len:8, Term:Len/binary, 0:8, PostWhere:32/native, PostLen:32/native, Rest/binary>>, Vocab) ->
    read_vocab(Rest, maps:put(Term, {PostWhere, PostLen}, Vocab));

read_vocab(<<>>, Vocab) ->
    Vocab.

%% Simple search engine ranking on BM25.
main([]) ->
    %% Read the document lengths
    {ok, LengthsData} = file:read_file("lengths.bin"),
    DocLengths = array:from_list([X || <<X:32/native>> <= LengthsData]),

    %% Compute the average document length for BM25
    AverageLength = array:foldl(fun(_, Val, Acc) -> Acc + Val end, 0, DocLengths) / array:size(DocLengths),

    %% Read the primary_keys
    {ok, DocIdsData} = file:read_file("docids.bin"),
    DocNos = array:from_list(string:lexemes(DocIdsData, "\n")),

    %% Build the vocabulary in memory
    {ok, VocabData} = file:read_file("vocab.bin"),
    Vocab = read_vocab(VocabData, #{}),

    %% Open the postings list file
    {ok, PostingsFH} = file:open("postings.bin", [read, binary]),

    accept_input(
        #index{
            average_length = AverageLength,
            docnos = DocNos,
            doclengths = DocLengths,
            vocab = Vocab,
            postings_fh = PostingsFH
        }
    ).
