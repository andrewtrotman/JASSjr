#!/usr/bin/env php
<?php
ini_set('memory_limit', '-1');

// Copyright (c) 2024 Vaughan Kitchen
// Minimalistic BM25 search engine.

// Make sure we have one parameter, the filename
if (count($argv) != 2)
	exit("Usage: $argv[0] <infile.xml>\n");

$vocab = array(); // the in-memory index
$doc_ids = array(); // the primary keys
$doc_lengths = array(); // hold the length of each document

// A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
// TREC <DOCNO> primary keys have a hyphen in them
$lexer = '/[a-zA-Z0-9][a-zA-Z0-9-]*|<[^>]*>/';

$fh = fopen($argv[1], 'r') or exit("ERROR: failed to open $argv[1]\n");

$docid = -1;
$document_length = 0;
$push_next = false; // is the next token the primary key?

while (($line = fgets($fh)) != false) {
	preg_match_all($lexer, $line, $tokens, PREG_PATTERN_ORDER);
	foreach ($tokens[0] as $token) {
		// If we see a <DOC> tag then we're at the start of the next document
		if ($token == '<DOC>') {
			// Save the previous document length
			if ($docid != -1)
				$doc_lengths[] = $document_length;
			// Move on to the next document
			$docid += 1;
			$document_length = 0;
			if ($docid % 1000 == 0)
				echo "$docid documents indexed\n";
		}
		// If the last token we saw was a <DOCNO> then the next token is the primary key
		if ($push_next) {
			$doc_ids[] = $token;
			$push_next = false;
		}
		if ($token == '<DOCNO>')
			$push_next = true;
		// Don't index XML tags
		if ($token[0] == '<')
			continue;

		// Lower case the string
		$token = strtolower($token);

		// Truncate any long tokens at 255 characters (so that the length can be stored first and in a single byte)
		if (strlen($token) > 255)
			$token = substr($token, 0, 255);

		// Add the posting to the in-memory index
		if (!array_key_exists($token, $vocab)) {
			$vocab[$token] = [$docid, 1]; // if the term isn't in the vocab yet 
		} else {
			$list = &$vocab[$token];
			if ($list[count($list) - 2] != $docid)
				array_push($list, $docid, 1); // if the docno for this occurence has changed then create a new <d,tf> pair
			else
				$list[count($list) - 1]++; // else increase the tf
		}

		// Compute the document length
		$document_length++;
	}
}

// If we didn't index any documents then we're done
if ($docid == -1)
	exit();

// Save the final document length
$doc_lengths[] = $document_length;

// Tell the user we've got to the end of parsing
echo "Indexed " . $docid + 1 . " documents. Serialising...\n";

// Store the primary keys
file_put_contents('docids.bin', implode("\n", $doc_ids) . "\n");

// Serialise the in-memory index to disk
$postings_fh = fopen('postings.bin', 'wb') or exit("ERROR: failed to open postings.bin\n");
$vocab_fh = fopen('vocab.bin', 'wb') or exit("ERROR: failed to open vocab.bin\n");

foreach ($vocab as $term => $postings) {
	// Write the postings list to one file
	$where = ftell($postings_fh);
	fwrite($postings_fh, pack('l*', ...$postings));

	// Write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
	fwrite($vocab_fh, pack('C', strlen($term)));
	fwrite($vocab_fh, $term);
	fwrite($vocab_fh, "\0"); # string is null terminated
	fwrite($vocab_fh, pack('ll', $where, count($postings) * 4)); // no. of bytes
}

// Store the document lengths
file_put_contents('lengths.bin', pack('l*', ...$doc_lengths));

// Cleanup
fclose($fh);
fclose($postings_fh);
fclose($vocab_fh);
?>
