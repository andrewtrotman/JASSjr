#!/usr/bin/env raku

# Copyright (c) 2024 Vaughan Kitchen
# Minimalistic BM25 search engine.

if @*ARGS.elems != 1 {
	say("Usage: $*PROGRAM-NAME <infile.xml>");
	exit;
}

my %vocab; # the in-memory index
my @doc_ids; # the primary keys
my @length_vector; # hold the length of each document

my $docid = -1;
my $document_length = 0;
my $push_next = False; # is the next token the primary key?

for @*ARGS[0].IO.lines -> $line {
	# A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
  	# TREC <DOCNO> primary keys have a hyphen in them
	for $line.match(/<[a..zA..Z0..9]><[a..zA..Z0..9-]>* | '<'<-[>]>*'>'/, :global) {
		my $token = $_.Str;
		# If we see a <DOC> tag then we're at the start of the next document
		if $token eq '<DOC>' {
			# Save the previous document length
			@length_vector.push($document_length) if $docid != -1;
			# Move on to the next document
			$docid++;
			$document_length = 0;
			say("$docid documents indexed") if $docid %% 1000;
		}
		# if the last token we saw was a <DOCNO> then the next token is the primary key
		if $push_next {
			@doc_ids.push($token);
			$push_next = False;
		}
		$push_next = True if $token eq '<DOCNO>';

		# Don't index XML tags
		next if $token.starts-with('<');

		# lower case the string
		$token = $token.lc;

		# truncate any long tokens at 255 charactes (so that the length can be stored first and in a single byte)
		$token = $token.substr(0, 256);

		# add the posting to the in-memory index
		%vocab{$token} = [] if %vocab{$token}:!exists; # if the term isn't in the vocab yet
		my @postings_list := %vocab{$token};
		if @postings_list.elems == 0 || @postings_list[*-2] != $docid {
			@postings_list.push($docid, 1); # if the docno for this occurence has changed then create a new <d,tf> pair
		} else {
			@postings_list[*-1]++; # else increase the tf
		}

		# Compute the document length
		$document_length++;
	}
}

# If we didn't index any documents then we're done.
exit if $docid == -1;

# Save the final document length
@length_vector.push($document_length);

# tell the user we've got to the end of parsing
say("Indexed {$docid+1} documents. Serialising...");

# store the primary keys
my $docids_fh = open('docids.bin', :w);
for @doc_ids -> $docid {
	$docids_fh.say($docid);
}

my $postings_fh = open('postings.bin', :w, :bin);
my $vocab_fh = open('vocab.bin', :w, :bin);

my $buffer = Buf.new;
for %vocab.kv -> $term, @postings {
	$buffer.reallocate(0);

	# write the postings list to one file
	my $where = $postings_fh.tell;
	for @postings {
		$buffer.write-int32(0, $_);
		$postings_fh.write($buffer);
	}

	$buffer.reallocate(0);
	# write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
	$buffer.write-uint8(0, $term.chars);
	$vocab_fh.write($buffer);
	$vocab_fh.write($term.encode);
	$buffer.reallocate(0);
	$buffer.write-uint8(0, 0);
	$buffer.write-int32(1, $where);
	$buffer.write-int32(5, @postings.elems * 4);
	$vocab_fh.write($buffer);
}

$buffer.reallocate(0);

# store the document lengths
my $lengths_fh = open('lengths.bin', :w, :bin);
for @length_vector {
	$buffer.write-int32(0, $_);
	$lengths_fh.write($buffer);
}

# clean up
$docids_fh.close;
$postings_fh.close;
$vocab_fh.close;
$lengths_fh.close;
