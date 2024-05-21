#!/usr/bin/env bash

# Copyright (c) 2024 Vaughan Kitchen

iters=11

if [ $# -ne 1 ]; then
	echo "Usage: $0 <infile>"
	exit
fi

infile="$1"

table=`cat << EOF
C++    ,c++ --version | head -n 1,Lexer,Array,./JASSjr_index,./JASSjr_search
Crystal,crystal --version | head -n 1,Regex,Array,./JASSjr_index_crystal,./JASSjr_search_crystal
D (dmd),dmd --version | head -n 1,Lexer,Array,./JASSjr_index_d_dmd,./JASSjr_search_d_dmd
D (ldc),ldc2 --version | head -n 1,Lexer,Array,./JASSjr_index_d_ldc,./JASSjr_search_d_ldc
Dart   ,dart --version,Regex,Array,./JASSjr_index.dart,./JASSjr_search.dart
Elixir ,elixir --version | tail -n 1,Lexer,HashMap,./JASSjr_index.exs,./JASSjr_search.exs
Fortran,gfortran --version | head -n 1,Lexer,Array,./JASSjr_index_fortran,./JASSjr_search_fortran
Go     ,go version,Lexer,Array,go run JASSjr_index.go, go run JASSjr_search.go
Java   ,java -version 2>&1 | head -n 1,Lexer,Array,java JASSjr_index,java JASSjr_search
JS     ,node --version,Regex,Array,./JASSjr_index.js,./JASSjr_search.js
Lua    ,luajit -v,Regex,HashMap,./JASSjr_index.lua,./JASSjr_search.lua
Nim    ,nim --version | head -n 1,Regex,Array,./JASSjr_index.nim,./JASSjr_search.nim
Perl   ,perl --version | head -n 2 | tail -n 1,Regex,Array,./JASSjr_index.pl,./JASSjr_search.pl
PHP    ,php --version | tr -d '\n',Regex,HashMap,./JASSjr_index.php,./JASSjr_search.php
Python ,python --version 2>&1,Regex,HashMap,./JASSjr_index.py,./JASSjr_search.py
Raku   ,raku --version | tr -d '\n',Regex,Array,echo hi,echo hi
Ruby   ,ruby --version,Regex,HashMap,./JASSjr_index.rb,./JASSjr_search.rb
Rust   ,rustc --version,Lexer,Array,./JASSjr_index_rust,./JASSjr_search_rust
Tcl    ,echo 'puts [info patchlevel]' | tclsh,Regex,HashMap,./JASSjr_index.tcl,./JASSjr_search.tcl
Zig    ,zig version,Lexer,Array,./JASSjr_index_zig,./JASSjr_search_zig
EOF
`

echo '| Language | Version                   | Parser | Accumulators | Indexing | Search  | Search 50 |'
echo '| -------- | -------                   | ------ | ------------ | -------- | ------  | --------- |'

readarray -t lines <<< "$table"
for line in "${lines[@]}"; do
	IFS=',' read -r -a elems <<< "$line"
	name="${elems[0]}"
	version=$(sh -c "${elems[1]}")
	parser="${elems[2]}"
	accumulators="${elems[3]}"
	index=$(sh -c "./tools/benchmark.sh $iters ${elems[4]} $infile | tail -n 1 | awk '{print \$2}'")
	search=$(sh -c "./tools/benchmark.sh $iters ${elems[5]} < query.txt | tail -n 1 | awk '{print \$2}'")
	search50=$(sh -c "./tools/benchmark.sh $iters ${elems[5]} < 51-100.titles.txt | tail -n 1 | awk '{print \$2}'")
	echo "| $name | $version | $parser | $accumulators | $index | $search | $search50 |"
done
