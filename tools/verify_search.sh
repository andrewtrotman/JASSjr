#!/usr/bin/env bash

# Copyright (c) 2024 Vaughan Kitchen

if [ $# -lt 1 ]; then
	echo "Usage: $0 <prog>"
	exit
fi

if [ -f results.gold.bin -a -f docids.gold.bin -a -f lengths.gold.bin -a -f postings.gold.bin -a -f vocab.gold.bin ]; then
	cp docids.gold.bin docids.bin
	cp lengths.gold.bin lengths.bin
	cp postings.gold.bin postings.bin
	cp vocab.gold.bin vocab.bin
else
	echo "A gold standard is required please generate with ./tools/verify_search.sh"
	exit
fi

echo "Verifying $@"
"$@" < 51-100.titles.txt > results.bin

if ! cmp results.bin results.gold.bin; then
	echo "ERROR: example queries results differs"
else
	echo "$@ appears to be correct"
fi
