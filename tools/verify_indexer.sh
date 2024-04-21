#!/usr/bin/env bash

# Copyright (c) 2024 Vaughan Kitchen

# Takes the command as is e.g.
# ./tools/verify_indexer.sh go run JASSjr_index.go wsj.xml

if [ $# -lt 2 ]; then
	echo "Usage: $0 <prog> <infile>"
	exit
fi

if [ ! -f stdout.gold.bin -o ! -f results.gold.bin -o ! -f docids.gold.bin -o ! -f lengths.gold.bin -o ! -f postings.gold.bin -o ! -f vocab.gold.bin ]; then
	echo "Generating gold standard with JASSjr_index"
	./JASSjr_index "${@: -1}" > stdout.gold.bin
	./JASSjr_search < 51-100.titles.txt > results.gold.bin
	mv docids.bin docids.gold.bin
	mv lengths.bin lengths.gold.bin
	mv postings.bin postings.gold.bin
	mv vocab.bin vocab.gold.bin
fi

echo "Verifying ${@:1:$#-1}"
"$@" > stdout.bin

correct=true

if ! cmp stdout.bin stdout.gold.bin; then
	echo "ERROR: stdout differs"
	correct=false
fi

if ! cmp docids.bin docids.gold.bin; then
	echo "ERROR: docids.bin differs"
	correct=false
fi

if ! cmp lengths.bin lengths.gold.bin; then
	echo "ERROR: lengths.bin differs"
	correct=false
fi

if [ "$(wc -c postings.bin | cut -d ' ' -f 1)" != "$(wc -c postings.gold.bin | cut -d ' ' -f 1)" ]; then
	echo "ERROR: postings.bin differs in length"
	correct=false
fi

if [ "$(wc -c vocab.bin | cut -d ' ' -f 1)" != "$(wc -c vocab.gold.bin | cut -d ' ' -f 1)" ]; then
	echo "ERROR: vocab.bin differs in length"
	correct=false
fi

echo "Verifying example queries"
./JASSjr_search < 51-100.titles.txt > results.bin
if ! cmp results.bin results.gold.bin; then
	echo "ERROR: example queries results differs"
	correct=false
fi

if $correct; then
	echo "${@:1:$#-1} appears to be correct"
fi
