#!/usr/bin/env -S ERL_FLAGS="+hms 1000000" escript
%% +hms sets default heap size (8mb)

%% Copyright (c) 2026 Vaughan Kitchen
%% Minimalistic BM25 search engine.

-module(jassjr_index).
-export([main/1]).

-record(index, {
    length = 0, %% length of currently indexing document
    docno = 0, %% cache last index into primary keys
    doclengths = [], %% hold the length of each document
    docnos = [], %% the primary keys
    terms = #{} %% the in-memory index (terms => <tf, docid>)
}).

integers_to_binary(Integers) ->
    iolist_to_binary(
        [<<X:32/native>> || X <- Integers]
    ).

%% Add the posting to the in-memory index
append(Index, Term) ->
    DocId = Index#index.docno - 1,
    Terms = Index#index.terms,
    NewTerms =
        case maps:find(Term, Terms) of
            error ->
                maps:put(Term, [1, DocId], Terms);
            {ok, [TF, Doc | Tail] = DocNos} ->
                NewPosts =
                    case Doc =/= DocId of
                        true ->
                            %% if the docno for this occurrence has changed
                            %% then create a new <d,tf> pair
                            [1, DocId | DocNos];
                        false ->
                            %% else increase the tf
                            [TF + 1, Doc | Tail]
                    end,
                maps:put(Term, NewPosts, Terms)
        end,
    Index#index{
        length = Index#index.length + 1,
        terms = NewTerms
    }.

consume_tag(<<Head, Tail/binary>>, Index) ->
    case Head of
        %% '>'
        62 ->
            parse(Tail, Index);
        _ ->
            consume_tag(Tail, Index)
    end.

%% If this is a <DOCNO> parse the primary key
parse_tag(<<"<DOCNO>", File/binary>>, Index) ->
    case Index#index.docno rem 1000 of
        0 ->
            io:format("~p documents indexed~n",
                      [Index#index.docno]);
        _ ->
            ok
    end,

    [DocNo0, File1] = binary:split(File, <<"</DOCNO>">>, []),
    DocNo = string:trim(DocNo0),

    %% Move on to the next document
    Index1 =
        case Index#index.docno > 0 of
            true ->
                Index#index{
                    length = 0,
                    doclengths = [Index#index.length | Index#index.doclengths],
                    docno = Index#index.docno + 1,
                    docnos = [DocNo | Index#index.docnos]
                };
            false ->
                Index#index{
                    docno = Index#index.docno + 1,
                    docnos = [DocNo | Index#index.docnos]
                }
        end,

    %% Include the primary key as a term to match the other indexers
    Index2 = append(Index1, string:lowercase(DocNo)),

    parse(File1, Index2);

%% Otherwise consume until end of tag
parse_tag(File, Index) ->
    consume_tag(File, Index).

parse_alnum(File, Index) ->
    parse_alnum(File, Index, <<>>).

parse_alnum(<<>>, Index, Val) ->
    append(Index, Val);

parse_alnum(<<Head, Tail/binary>> = File, Index, Val) ->
    case Head of
        %% Numeric
        X when X >= 48, X =< 57 ->
            parse_alnum(Tail, Index, <<Val/binary, X>>);

        %% Uppercase
        X when X >= 65, X =< 90 ->
            %% lower case the string
            parse_alnum(Tail, Index, <<Val/binary, (X + 32)>>);

        %% Lowercase
        X when X >= 97, X =< 122 ->
            parse_alnum(Tail, Index, <<Val/binary, X>>);

        %% Hyphen is allowed after the initial character
        45 ->
            parse_alnum(Tail, Index, <<Val/binary, Head>>);

        _ ->
            parse(File, append(Index, Val))
    end.


%% One-character lookahead lexical analyser
parse(File) ->
    parse(File, #index{}).

parse(<<>>, Index) ->
    Index;

parse(<<Head, Tail/binary>> = File, Index) ->
    %% A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
    case Head of
        %% Tag '<'
        60 ->
            parse_tag(File, Index);

        %% Numeric
        X when X >= 48, X =< 57 ->
            parse_alnum(File, Index);

        %% Uppercase
        X when X >= 65, X =< 90 ->
            parse_alnum(File, Index);

        %% Lowercase
        X when X >= 97, X =< 122 ->
            parse_alnum(File, Index);

        %% Skip over whitespace and punctuation
        _ ->
            parse(Tail, Index)
    end.


%% Serialise the in-memory index to disk
serialise(Index) ->
    %% Save the final document length
    Index1 = Index#index{
        doclengths = [Index#index.length | Index#index.doclengths]
    },

    DocNos = lists:reverse(Index1#index.docnos),

    %% Store the primary keys
    {ok, DocIdsFile} = file:open("docids.bin", [write]),
    lists:foreach(
        fun(DocNo) ->
            file:write(DocIdsFile, <<DocNo/binary, $\n>>)
        end,
        DocNos
    ),
    ok = file:close(DocIdsFile),

    {ok, Vocab} = file:open("vocab.bin", [write, binary]),
    {ok, Postings} = file:open("postings.bin", [write, binary]),

    maps:fold(
        fun(Term, Posts, ok) ->
            %% Write the postings list to one file
            Posts1 = lists:reverse(Posts),
            PostsBinary = integers_to_binary(Posts1),

            {ok, Where} = file:position(Postings, {cur, 0}),
            ok = file:write(Postings, PostsBinary),

            %% Write the vocabulary to a second file
            %% (one byte length, string, '\0', 4 byte where, 4 byte size)
            ok = file:write(
                Vocab,
                <<(byte_size(Term)):8,
                  Term/binary,
                  0:8,
                  Where:32/native,
                  (byte_size(PostsBinary)):32/native>>
            ),
            ok
        end,
        ok,
        Index1#index.terms
    ),

    %% Clean up
    ok = file:close(Postings),
    ok = file:close(Vocab),

    %% Store the document doclengths
    DocLengths = lists:reverse(Index1#index.doclengths),
    DocLengthsBinary = integers_to_binary(DocLengths),

    {ok, LengthsFile} = file:open("lengths.bin", [write, binary]),
    ok = file:write(LengthsFile, DocLengthsBinary),
    ok = file:close(LengthsFile),

    ok.

main(Args) ->
    %% Make sure we have one parameter, the filename
    case length(Args) of
        1 ->
            ok;
        _ ->
            io:format("Usage: ./JASSjr_index.erl <infile.xml>~n"),
            halt()
    end,

    %% Read the file to index
    [Filename | _] = Args,
    {ok, File} = file:read_file(Filename),

    Index = parse(File),

    %% Tell the user we've got to the end of parsing
    io:format("Indexed ~p documents. Serialising...~n", [Index#index.docno]),

    serialise(Index).
