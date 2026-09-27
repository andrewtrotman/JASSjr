# JASSjr #
JASSjr, the minimalistic BM25 search engine for indexing and searching the TREC WSJ collection.

Copyright (c) 2019, 2023, 2024, 2026 Andrew Trotman, Kat Lilly, Vaughan Kitchen, Katelyn Harlan \
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
| JASSjr_index.c3 | C3 source code to indexer |
| JASSjr_search.c3 | C3 source code to search engine |
| JASSjr_index.py | Python source code to indexer |
| JASSjr_search.py | Python source code to search engine |
| JASSjr_index.js | JavaScript source code to indexer |
| JASSjr_search.js | JavaScript source code to search engine |
| JASSjr_index.jl | Julia source code to indexer |
| JASSjr_search.jl | Julia source code to search engine |
| JASSjr_index.exs | Elixir source code to indexer |
| JASSjr_search.exs | Elixir source code to search engine |
| JASSjr_index.escript | Erlang source code to indexer |
| JASSjr_search.escript | Erlang source code to search engine |
| JASSjr_index.rb | Ruby source code to indexer |
| JASSjr_search.rb | Ruby source code to search engine |
| JASSjr_index.pl | Perl source code to indexer |
| JASSjr_search.pl | Perl source code to search engine |
| JASSjr_index.go | Go source code to indexer |
| JASSjr_search.go | Go source code to search engine |
| JASSjr_index.ha | Hare source code to indexer |
| JASSjr_search.ha | Hare source code to search engine |
| JASSjr_index.raku | Raku source code to indexer |
| JASSjr_search.raku | Raku source code to search engine |
| JASSjr_index.nim | Nim source code to indexer |
| JASSjr_search.nim | Nim source code to search engine |
| JASSjr_index.odin | Odin source code to indexer |
| JASSjr_search.odin | Odin source code to search engine |
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
| JASSjr_index.vala | Vala source code to indexer |
| JASSjr_search.vala | Vala source code to search engine |
| JASSjr_index.scm | Chicken Scheme source code to indexer |
| JASSjr_search.scm | Chicken Scheme source code to search engine |
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

These are for example purposes only. Each implementation is intending to be idiomatic in its source language rather than to eek out every last bit of performance. That being said if there are equal implementation choices the faster version is preferred when possible. Benchmarking was done on an Intel Core i7-7700k @ 4.20GHz with 64GiB 3000MT/s DDR4 running Chimera Linux

| Language   | Version               | Parser | Accumulators | Indexing | Search | Search 50 |
| ---------- | --------------------- | ------ | ------------ | -------- | ------ | --------- |
| C++        | clang 22.1.8          | Lexer  | Array        | 13.73s   | 0.17s  | 0.75s     |
| C3         | 0.8.3/22.1.8          | Lexer  | Array        | _        | _      | _         |
| Crystal    | 1.12.1/20.1.8         | Regex  | Array        | 31.46s   | 0.20s  | 0.92s     |
| D          | v2.108.1              | Lexer  | Array        | _        | _      | _         |
| Dart       | 3.13.4                | Regex  | Array        | 84.88s   | 0.56s  | 3.04s     |
| Elixir     | 1.19.5/28             | Lexer  | HashMap      | 136.57s  | 1.19s  | 2.87s     |
| Fortran    | f2003/gfortran 16.1.0 | Lexer  | Array        | 21.70s   | 0.51s  | 1.06s     |
| Go         | 1.26.3                | Lexer  | Array        | 15.46s   | 0.17s  | 0.66s     |
| Hare       | 0.26.0.1              | Lexer  | Array        | 384.68s  | 0.44s  | 2.16s     |
| Java       | 25.0.2                | Lexer  | Array        | 16.54s   | 0.29s  | 1.18s     |
| JavaScript | node v25.9.0          | Regex  | Array        | 34.96s   | 0.75s  | 2.76s     |
| Julia      | 1.11.6                | Regex  | Array        | 59.63s   | 2.49s  | 44.60s    |
| Lua        | LuaJIT 2.1.1737090214 | Regex  | HashMap      | 72.87s   | 0.46s  | 1.20s     |
| Nim        | 2.2.12                | Regex  | Array        | _        | 0.36s  | 1.20s     |
| Odin       | dev-2026-08           | Lexer  | Array        | 28.41s   | 0.18s  | 1.55s     |
| Perl       | v5.42.0               | Regex  | Array        | 121.93s  | 0.87s  | 3.49s     |
| PHP        | 8.3.33/Zend v4.3.33   | Regex  | HashMap      | 34.12s   | 0.39s  | 0.87s     |
| Python     | 3.14.6                | Regex  | HashMap      | 73.47s   | 0.78s  | 1.81s     |
| Raku       | v6.d/v2024.04         | Regex  | Array        | _        | _      | _         |
| Ruby       | 3.4.7                 | Regex  | HashMap      | 139.54s  | 1.12s  | 4.96s     |
| Rust       | 1.96.0                | Lexer  | Array        | 16.62s   | 0.14s  | 0.28s     |
| Scheme     | csc 6.0.0             | Regex  | Array        | _        | _      | _         |
| Tcl        | 8.6.16                | Regex  | HashMap      | 424.75s  | 2.92s  | 13.18s    |
| Vala       | 0.56.19               | Lexer  | Array        | -        | -      | -         |
| Zig        | 0.16.0                | Lexer  | Array        | 7.37s    | 0.10s  | 0.85s     |

D and Raku don't have musl releases. The nim indexer uses the outdated and unavailable libpcre1

Times are recorded as median of 11 iterations

Where Parser is one of
* Lexer being a hand written single token look-ahead lexer
* Regex being an equivalent regex to the lexer

Search is the time to startup, read the index file, and produce results for a single query. Search 50 is a single startup and then produce results for 50 queries. Times for both of these are the median of 11 iterations

# Tests #

There is a small test suite which works by running the programs and checking the output powered by bats. Currently it can be run with `./tests/10_index.bats` and `./tests/10_search.bats`. You will need to install `bats` and the `bats-assert` packages to access it

Copyright (c) 2019, 2023, 2024, 2026 Andrew Trotman, Kat Lilly, Vaughan Kitchen, Katelyn Harlan

