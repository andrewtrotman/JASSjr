#!/usr/bin/env raku

# Copyright (c) 2024 Vaughan Kitchen
# Minimalistic BM25 search engine.

constant $k1 = 0.9; # BM25 k1 parameter
constant $b = 0.4; # BM25 b parameter

# Read the primary_keys
my @doc_ids = 'docids.bin'.IO.lines;

# Read the document lengths
my $doc_lengths_raw = slurp('lengths.bin', :bin);
my @doc_lengths = (0, 4 ...^ $doc_lengths_raw.bytes).map: { $doc_lengths_raw.read-int32($_) };
my $average_length = @doc_lengths.sum / @doc_lengths.elems;

# Open the postings list file
my $postings_fh = open('postings.bin');

# decode the vocabulary (unsigned byte length, string, '\0', 4 byte signed where, 4 signed byte size)
my %vocab;

my $vocab_raw = slurp('vocab.bin', :bin);
my $offset = 0;

while $offset < $vocab_raw.bytes {
	my $length = $vocab_raw[$offset].Int;
	$offset += 1;

	my $term = $vocab_raw.subbuf($offset, $length).decode('ascii');
	$offset += $length + 1; # Null terminated

	my $where = $vocab_raw.read-int32($offset);
	my $size = $vocab_raw.read-int32($offset+4);
	$offset += 8;

	%vocab{$term} = [$where, $size];
}

# Search (one query per line)
loop {
	my $query = prompt;
	last if !$query;

	my @accumulators = [0, 0] xx @doc_ids.elems;

	my $query_id = 0;
	my @query = $query.words;

	# If the first token is a number then assume a TREC query number, and skip it
	if @query[0].Int !~~ Failure {
		$query_id = @query.shift.Int;
	}

	for @query -> $term {
		# Does the term exist in the collection?
		next if %vocab{$term}:!exists;

		my ($offset, $size) = %vocab{$term};

		# Seek and read the postings list
		$postings_fh.seek($offset);
		my $postings_raw = $postings_fh.read($size);
		my @postings = (0, 4 ...^ $postings_raw.bytes).map: { $postings_raw.read-int32($_) };

		# Compute the IDF component of BM25 as log(N/n).
		my $idf = log(@doc_ids.elems / (@postings.elems / 2));

		# Process the postings list by simply adding the BM25 component for this document into the accumulators array
		for @postings -> $docid, $tf {
			my $rsv = $idf * (($tf * ($k1 + 1)) / ($tf + $k1 * (1 - $b + $b * (@doc_lengths[$docid] / $average_length))));
			@accumulators[$docid][0] += $rsv;
			@accumulators[$docid][1] = $docid;
		}
	}

	# Sort the results list. Tie break on the document ID.
	@accumulators = @accumulators.sort.reverse;
	
	# Print the (at most) top 1000 documents in the results list in TREC eval format which is:
	# query-id Q0 document-id rank score run-name
	for @accumulators.grep({ $_[0] > 0 || last }).head(1000).kv -> $i, ($rsv, $docid) {
		printf("%d Q0 %s %d %.4f JASSjr\n", $query_id, @doc_ids[$docid], $i+1, $rsv);
	}
}
