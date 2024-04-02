#!/usr/bin/env perl

# Copyright (c) 2024 Vaughan Kitchen
# Minimalistic BM25 search engine.

use v5.38;
use strict;
use warnings;

my $K1 = 0.9; # BM25 k1 parameter
my $B = 0.4; # BM25 b parameter

sub slurp($filename) {
	open my $fh, '<:raw', $filename or die;
	die $! if not defined read $fh, my $content, -s $fh;
	close $fh;
	return $content;
}

# Read the primary_keys
open my $fh, '<', 'docids.bin' or die;
chomp(my @docids = <$fh>);
close $fh;
my %vocab;
my @lengths = unpack 'l*', slurp('lengths.bin'); # Read the document lengths
# Compute the average document length for BM25
my $average_length = 0;
foreach (@lengths) {
	$average_length += $_;
}
$average_length /= scalar @lengths;
open my $postings_fh, '<:raw', 'postings.bin' or die;

# decode the vocabulary (unsigned byte length, string, '\0', 4 byte signed where, 4 signed byte size)
my @vocab_raw = unpack '(C/axll)*', slurp('vocab.bin');
while (my ($term, $where, $size) = splice(@vocab_raw, 0, 3)) {
	$vocab{$term} = [$where, $size];
}

# Search (one query per line)
while (<>) {
	chomp;
	my @query = split /\s/;

	# If the first token is a number then assume a TREC query number, and skip it
	my $query_id = '0';
	if ($query[0] =~ /^\d+$/) {
		$query_id = $query[0];
		shift @query;
	}

	my @accumulators; # array of rsv values

	foreach (@query) {
		my $results = $vocab{$_};
		next if not defined $results; # Does the term exist in the collection?

		# Seek and read the postings list
		my ($where, $size) = @{$results};
		seek $postings_fh, $where, 0;
		die $! if not defined read $postings_fh, (my $postings), $size;
		my @postings = unpack 'l*', $postings;

		# Compute the IDF component of BM25 as log(N/n).
		my $idf = log(scalar @docids / (scalar @postings / 2));

		# Process the postings list by simply adding the BM25 component for this document into the accumulators array
		while (my ($docid, $freq) = splice(@postings, 0, 2)) {
			my $rsv = $idf * (($freq * ($K1 + 1)) / ($freq + $K1 * (1 - $B + $B * ($lengths[$docid] / $average_length))));
			if (not defined $accumulators[$docid]) {
				$accumulators[$docid] = [$docid, $rsv];
			} else {
				${$accumulators[$docid]}[1] += $rsv;
			}
		}
	}

	# Sort the results list. Tie break on the document ID.
	@accumulators = sort { @{$b}[1] <=> @{$a}[1] || @{$b}[0] <=> @{$a}[0] } @accumulators;

	# Print the (at most) top 1000 documents in the results list in TREC eval format which is:
	# query-id Q0 document-id rank score run-name
	while (my ($i, $result) = each @accumulators) {
		last if not defined $result;
		last if $i == 1000;

		my ($id, $freq) = @{$result};
		printf "%s Q0 %s %d %.4f JASSjr\n", $query_id, $docids[$id], $i+1, $freq;
	}
}

close $postings_fh; # clean up
