#!/usr/bin/env perl

# Copyright (c) 2024 Vaughan Kitchen
# Minimalistic BM25 search engine.

use v5.38;
use strict;
use warnings;
use builtin qw(true false);
no warnings 'experimental';

# Make sure we have one parameter, the filename
die "Usage: $0 <infile.xml>" if scalar @ARGV != 1;

my %vocab; # the in-memory index
my @doc_ids; # the primary keys
my @length_vector; # hold the length of each document

my $docid = -1;
my $document_length = 0;
my $push_next = false; # is the next token the primary key?

while (<>) {
	# A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
	# TREC <DOCNO> primary keys have a hyphen in them
	foreach (m/[a-zA-Z0-9][a-zA-Z0-9-]*|<[^>]*>/g) {
		# If we see a <DOC> tag then we're at the start of the next document
		if ($_ eq '<DOC>') {
			# Save the previous document length
			push @length_vector, $document_length if $docid != -1;
			# Move on to the next document
			$docid += 1;
			$document_length = 0;
			say "$docid documents indexed" if $docid % 1000 == 0;
		}
		# if the last token we saw was a <DOCNO> then the next token is the primary key
		if ($push_next) {
			push @doc_ids, $_;
			$push_next = false;
		}
		$push_next = true if $_ eq '<DOCNO>';
		# Don't index XML tags
		next if substr($_, 0, 1) eq '<';

		# lower case the string
		my $token = lc $_;
		# truncate any long tokens at 255 charactes (so that the length can be stored first and in a single byte)
		$token = substr $token, 0, 255;

		# add the posting to the in-memory index
		$vocab{$token} = [] if not exists $vocab{$token};
		my $postings_list = $vocab{$token};
		if (scalar @{$postings_list} == 0 || @{$postings_list}[-2] ne $docid) {
			push @{$postings_list}, $docid, 1;
		} else {
			@{$postings_list}[-1] += 1;
		}

		# Compute the document length
		$document_length += 1;
	}
}

# If we didn't index any documents then we're done.
exit if $docid == -1;

# Save the final document length
push @length_vector, $document_length;

# tell the user we've got to the end of parsing
say "Indexed @{[$docid + 1]} documents. Serialising...";

# Save the final document length
open my $docids_fh, '>', 'docids.bin' or die;
foreach (@doc_ids) {
	print $docids_fh "$_\n";
}

open my $postings_fh, '>:raw', 'postings.bin' or die;
open my $vocab_fh, '>:raw', 'vocab.bin' or die;

while (my ($term, $postings) = each %vocab) {
	my @postings = @{$postings};

	# write the postings list to one file
	my $where = tell $postings_fh;
	print $postings_fh pack 'l*', @postings;

	# write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
	print $vocab_fh pack 'Ca*xll', length($term), $term, $where, scalar @postings * 4;
}

# store the document lengths
open my $lengths_fh, '>:raw', 'lengths.bin' or die;
print $lengths_fh pack 'l*', @length_vector;

# clean up
close $docids_fh;
close $postings_fh;
close $vocab_fh;
close $lengths_fh;
