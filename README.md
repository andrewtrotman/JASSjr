# JASSjr #
JASSjr, the minimalistic BM25 search engine for indexing and searching the TREC WSJ collection.

Copyright (c) 2019, 2023, 2024 Andrew Trotman, Kat Lilly, Vaughan Kitchen, Katelyn Harlan \
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
To build for all installed languages run

	make -k

To build for a specific language use make and the language name e.g.

	make cpp

To index use

	JASSjr_index <filename>
	
where `<filename>` is the name of the TREC encoded file.  The example file test_documents.xml shows the required file format.  Documents can be split over multiple lines, but whitespace is needed around `<DOC>` and `<DOCNO>` tags.

To search use

	JASSjr_search

Queries a sequences of words.  If the first token is a number it is assumed to the a TREC query number and is used in the output (and not searched for).

JASSjr will produce (on stdout) a [trec_eval](https://github.com/usnistgov/trec_eval) compatible results list.

## Java ##
The Java version is built in the same way, but run with

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
Many languages include a shebang and can be executed directly e.g.

    ./JASSjr_index.py <filename>

and

    ./JASSjr_search.py

for languages in which a binary is also produced this will typically run an unoptimised developer build. A full list can be obtained by running `git grep --no-recursive '^#!/usr/bin/env'`

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
| LICENSE.txt | A copy of the 2-clause BSD license |
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
| JASSjr_index.nim | Nim source code to indexer |
| JASSjr_search.nim | Nim source code to search engine |
| JASSjr_index.zig | Zig source code to indexer |
| JASSjr_search.zig | Zig source code to search engine |
| JASSjr_index.f90 | Fortran source code to indexer |
| JASSjr_search.f90 | Fortran source code to search engine |
| JASSjr_index.d | D source code to indexer |
| JASSjr_search.d | D source code to search engine |
| JASSjr_index.php | PHP source code to indexer |
| JASSjr_search.php | PHP source code to search engine |
| JASSjr_index.cr | Crystal source code to indexer |
| JASSjr_search.cr | Crystal source code to search engine |
| JASSjr_index.lua | Lua source code to indexer |
| JASSjr_search.lua | Lua source code to search engine |
| JASSjr_index.rs | Rust source code to indexer |
| JASSjr_search.rs | Rust source code to search engine |
| JASSjr_index.tcl | Tcl source code to indexer |
| JASSjr_search.tcl | Tcl source code to search engine |
| JASSjr_index.dart | Dart source code to indexer |
| JASSjr_search.dart | Dart source code to search engine |
| GNUmakefile | GNU make makefile for macOS / Linux |
| makefile | NMAKE makefile for Windows |
| test_documents.xml | Example of how documents should be layed out for indexing | 
| 51-100.titles.txt | TREC topics 51-100 titles as queries |
| 51-100.qrels.txt | TREC topics 51-100 human judgments |
| tools/GNUmakefile | GNU make makefile for macOS / Linux |
| tools/index_stats.py | Print general index stats |
| tools/show_document.cpp | Print document from collection when given a docid |
| tools/verify_indexer.sh | Verifies an indexer matches the reference implementation |
| tools/verify_search.sh | Verifies a search engine matches the reference implementation |
| tools/vocab_diff.py | Debug vocab file differences |

# Benchmarks #

There are lies, damned lies, and benchmarks

These are for example purposes only. Each implementation is intending to be idiomatic in its source language rather than to eek out every last bit of performance. That being said if there are equal implementation choices the faster version is preferred when possible. Benchmarking was done on an Intel Core i7-13700 @ 5.20GHz with 32GiB 4400MT/s DDR5 running openSUSE Tumbleweed with Linux 6.8.9.

| Language | Version                   | Parser | Accumulators | Indexing | Search  | Search 50 |
| -------- | -------                   | ------ | ------------ | -------- | ------  | --------- |
| C++      | c++11/gcc 13.2.1          | Lexer  | Array        | 8.68s    | 100ms   | 500ms     |
| Crystal  | 1.12.1/15.0.7             | Regex  | Array        | 17.15s   | 70ms    | 670ms     |
| D (dmd)  | v2.108.1                  | Lexer  | Array        | 32.22s   | 130ms   | 1.16s     |
| D (ldc)  | 1.32.0/15.0.7             | Lexer  | Array        | 19.25s   | 100ms   | 680ms     |
| Dart     | 3.4.0                     | Regex  | Array        | 43.91s   | 330ms   | 1.80s     |
| Elixir   | 1.16.2                    | Lexer  | HashMap      | 97.48s   | 850ms   | 1.91s     |
| Fortran  | f2003/gfortran 13.2.1     | Lexer  | Array        | 13.01s   | 310ms   | 790ms     |
| Go       | 1.21.10                   | Lexer  | Array        | 10.99s   | 270ms   | 670ms     |
| Java     | 1.8.0_412                 | Lexer  | Array        | 13.68s   | 250ms   | 910ms     |
| JS       | node v21.7.2              | Regex  | Array        | 25.86s   | 780ms   | 2.16s     |
| Lua      | LuaJIT 2.1.1707061634     | Regex  | HashMap      | 50.36s   | 340ms   | 910ms     |
| Nim      | 2.0.4                     | Regex  | Array        | 11.66s   | 860ms   | 1.50s     |
| Perl     | v5.38.2                   | Regex  | Array        | 81.77s   | 680ms   | 2.11s     |
| PHP      | 8.3.7/Zend v4.3.7         | Regex  | HashMap      | 23.99s   | 180ms   | 520ms     |
| Python   | 2.7.18                    | Regex  | HashMap      | 50.22s   | 470ms   | 1.08s     |
| Raku     | v6.d/v2024.02             | Regex  | Array        | 140min   | 6.22s   | 130.22s   |
| Ruby     | 3.3.1                     | Regex  | HashMap      | 150.7s   | 840ms   | 2.06s     |
| Rust     | 1.77.2                    | Lexer  | Array        | 10.06s   | 120ms   | 640ms     |
| Tcl      | 8.6.14                    | Regex  | HashMap      | 271.73s  | 1.82s   | 8.00s     |
| Zig      | 0.12.0                    | Lexer  | Array        | 5.04s    | 70ms    | 480ms     |

Times are recorded as median of 11 iterations

Where Parser is one of
* Lexer being a hand written single token look-ahead lexer
* Regex being an equivalent regex to the lexer

Search is the time to startup, read the index file, and produce results for a single query. Search 50 is a single startup and then produce results for 50 queries. Times for both of these are the median of 11 iterations

# Tests #

There is a small test suite which works by running the programs and checking the output powered by bats. Currently it can be run with `./tests/10_index.bats` and `./tests/10_search.bats`. You will need to install `bats` and the `bats-assert` packages to access it

Copyright (c) 2019, 2023, 2024 Andrew Trotman, Kat Lilly, Vaughan Kitchen, Katelyn Harlan

