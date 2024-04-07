# JASSjr #
JASSjr, the minimalistic BM25 search engine for indexing and searching the TREC WSJ collection.

Copyright (c) 2019 Andrew Trotman and Kat Lilly \
Copyright (c) 2023, 2024 Vaughan Kitchen \
Released under the 2-clause BSD licence.

Please fork our repo.  Please report any bugs.

### Please Cite Our Paper ###
A. Trotman, K. Lilly (2020), JASSjr: The Minimalistic BM25 Search Engine for Teaching and Learning Information Retrieval, Proceedings of SIGIR 2020

## Why? ##
JASSjr is the little-brother to all other search engines, especially [JASSv2](https://github.com/andrewtrotman/JASSv2) and [ATIRE](http://atire.org).  The purpose of this code base is to demonstrate how easy it is to write a search engine that will perform BM25 on a TREC collection.

This particular code was originally written as a model answer to the University of Otago COSC431 Information Retrieval assignment requiring the students to write a search engine that can index the TREC WSJ collection, search in less than a second, and can rank.

As an example ranking function this code implements the ATIRE version of BM25 with k1= 0.9 and b=0.4

## Gotchas ##
* If the first word in a query is a number it is assumed to be a TREC query number

* There are many variants of BM25, JASSjr uses the ATIRE BM25 function which ignores the k3 query component.  It is assumed that each term is unique and occurs only once (and so the k3 clause is set to 1.0).

# Usage #
To build simply use

	make

To index use

	JASSjr_index <filename>
	
where `<filename>` is the name of the TREC encoded file.  The example file test_documents.xml shows the required file format.  Documents can be split over multiple lines, but whitespace is needed around `<DOC>` and `<DOCNO>` tags.

To search use

	JASSjr_search

Queries a sequences of words.  If the first token is a number it is assumed to the a TREC query number and is used in the output (and not searched for).

JASSjr will produce (on stdout) a [trec_eval](https://github.com/usnistgov/trec_eval) compatible results list.

## Java ##
The Java version is build in the same way, but run with 

	java JASSjr_index <filename>

and

	java JASSjr_search

## Elixir ##
The Elixir version can also be built manually to reduce startup times when searching

	echo 'null' | elixirc JASSjr_search.exs > /dev/null

and then run with

	elixir -e 'SearchEngine.start'

## Ruby ##
It is recommended to run the Ruby implementation with yjit where available. As this is not currently the default run with

	ruby --yjit JASSjr_index.rb <filename>

and then run with

	ruby --yjit JASSjr_search.rb

## Go ##
To index use

    go run JASSjr_index.go <filename>

To search use

    go run JASSjr_search.go

Alternatively `go build` can be used to produce binaries. Though the names of these will conflict with the C++ versions

## Other ##
The interpreted languages include a shebang and can be executed directly e.g.

    ./JASSjr_index.py <filename>

and

    ./JASSjr_search.py

# Evaluation #
* Indexing the TREC WSJ collection of 173,252 documents takes less than 20 seconds on my Mac (3.2 GHz Intel Core i5).

* Searching and generating a [trec_eval](https://github.com/usnistgov/trec_eval) compatible output for TREC queries 51-100 (top k=1000) takes 1 second on my Mac.

* [trec_eval](https://github.com/usnistgov/trec_eval) reports:

---
	runid                 	all	JASSjr
	num_q                 	all	50
	num_ret               	all	46725
	num_rel               	all	6228
	num_rel_ret           	all	3509
	map                   	all	0.2080
	gm_map                	all	0.0932
	Rprec                 	all	0.2563
	bpref                 	all	0.2880
	recip_rank            	all	0.5974
	iprec_at_recall_0.00  	all	0.6456
	iprec_at_recall_0.10  	all	0.4286
	iprec_at_recall_0.20  	all	0.3451
	iprec_at_recall_0.30  	all	0.3005
	iprec_at_recall_0.40  	all	0.2399
	iprec_at_recall_0.50  	all	0.1864
	iprec_at_recall_0.60  	all	0.1561
	iprec_at_recall_0.70  	all	0.1002
	iprec_at_recall_0.80  	all	0.0665
	iprec_at_recall_0.90  	all	0.0421
	iprec_at_recall_1.00  	all	0.0089
	P_5                   	all	0.4320
	P_10                  	all	0.4040
	P_15                  	all	0.3813
	P_20                  	all	0.3660
	P_30                  	all	0.3407
	P_100                 	all	0.2484
	P_200                 	all	0.1846
	P_500                 	all	0.1125
	P_1000                	all	0.0702
---

So JASSjr is not as fast as JASSv2, and not quite as good at ranking as JASSv2, but that isn't the point.  JASSjr is a minimalistic code base demonstrating how to write a search engine from scratch.  It performs competatively well.


# Manifest #

| Filename | Purpose |
|------------|-----------|
| README.md | This file |
| JASSjr_index.cpp | C/C++ source code to indexer |
| JASSjr_search.cpp | C/C++ source code to search engine |
| JASSjr_index.java | Java source code to indexer |
| JASSjr_search.java | Java source code to search engine |
| JASSjr_index.py | Python source code to indexer |
| JASSjr_search.py | Python source code to search engine |
| JASSjr_index.js | JavaScript source code to indexer |
| JASSjr_search.js | JavaScript source code to search engine |
| JASSjr_index.exs | Elixir source code to indexer |
| JASSjr_search.exs | Elixir source code to search engine |
| JASSjr_index.rb | Ruby source code to indexer |
| JASSjr_search.rb | Ruby source code to search engine |
| JASSjr_index.pl | Perl source code to indexer |
| JASSjr_search.pl | Perl source code to search engine |
| JASSjr_index.go | Go source code to indexer |
| JASSjr_search.go | Go source code to search engine |
| JASSjr_index.raku | Raku source code to indexer |
| JASSjr_search.raku | Raku source code to search engine |
| GNUmakefile | GNU make makefile for macOS / Linux |
| makefile | NMAKE makefile for Windows |
| test_documents.xml | Example of how documents should be layed out for indexing | 
| 51-100.titles.txt | TREC topics 51-100 titles as queries |
| 51-100.qrels.txt | TREC topics 51-100 human judgments |

# Benchmarks #

There are lies, damned lies, and benchmarks

These are for example purposes only. Each implementation is intending to be idiomatic in its source language rather than to eek out every last bit of performance. That being said if there are equal implementation choices the faster version is preferred when possible. Benchmarking was done on an Intel Core i7-7700k @ 4.20GHz with 64GiB 3000MHz DDR4 running Musl Void Linux 6.6.23 or newer.

| Language | Version            | Parser | Accumulators | Indexing | Search |
| -------- | -------            |------- | ------------ | -------- | ------ |
| C++      | gcc 13.2           | Lexer  | Array        | 15s      | 280ms  |
| Elixir   | 1.15.7/erts-14.2.3 | Lexer  | HashMap      | 125s     | 850ms  |
| Go       | 1.22.0             | Lexer  | Array        | 18s      | 250ms  |
| Java     | 1.8.0_332          | Lexer  | Array        | 18s      | 330ms  |
| JS       | node v18.19.1      | Regex  | Array        | 35s      | 750ms  |
| Nim      | 2.0.0              | Regex  | Array        | 19s      | 950ms  |
| Perl     | v5.38.2            | Regex  | Array        | 115s     | 900ms  |
| Python   | 3.12.2             | Regex  | Array        | 74s      | 850ms  |
| Raku     | v6.d/2023.11       | Regex  | Array        | 140min   | 8s     |
| Ruby     | 3.3.2              | Regex  | Array        | 160s     | 2.3s   |

Where Parser is one of
* Lexer being a hand written single token look-ahead lexer
* Regex being an equivalent regex to the lexer

And search is the time to startup, read the index file, and produce results for a single query

Copyright (c) 2019 Andrew Trotman and Kat Lilly
