#!/usr/bin/env php
<?php
ini_set('memory_limit', '512M');

// Copyright (c) 2024 Vaughan Kitchen
// Minimalistic BM25 search engine.

$k1 = 0.9; // BM25 k1 parameter
$b = 0.4; // BM25 b parameter

// Read the primary_keys
$doc_ids = explode("\n", rtrim(file_get_contents('docids.bin'))); // 0 indexed
// Read the document lengths
$doc_lengths = unpack('l*', file_get_contents('lengths.bin')); // 1 indexed
// Compute the average document length for BM25
$average_length = array_sum($doc_lengths) / count($doc_lengths);

// Decode the vocabulary (unsigned byte length, string, '\0', 4 byte signed where, 4 signed byte size)
$vocab = array();

$vocab_raw = file_get_contents('vocab.bin');
$offset = 0;
while ($offset < strlen($vocab_raw)) {
	$length = unpack('C', $vocab_raw, $offset)[1];
	$offset++;

	$term = substr($vocab_raw, $offset, $length);
	$offset += $length + 1; // Null terminated

	$postings_pair = unpack('loffset/lsize', $vocab_raw, $offset);
	$offset += 8;

	$vocab[$term] = $postings_pair;
}

// Search (one query per line)
while (true) {
	if (!$query = fgets(STDIN))
		break;

	$accumulators = array();

	$terms = explode(' ', rtrim($query)); // 0 indexed

	// If the first token is a number then assume a TREC query number, and skip it
	$query_id = '0';
	if (is_numeric($terms[0]))
		$query_id = array_shift($terms);

	foreach ($terms as $term) {
		if (empty($term))
			continue;

		// Does the term exist in the collection?
		if (!array_key_exists($term, $vocab))
			continue;

		['offset' => $offset, 'size' => $size] = $vocab[$term];

		// Seek and read the postings list
		$postings = unpack('l*', file_get_contents('postings.bin', false, null, $offset, $size)); // 1 indexed

		// Compute the IDF component of BM25 as log(N/n)
		$idf = log(count($doc_ids) / (count($postings) / 2));

		// Process the postings list by simply adding the BM25 component for this document into the accumulators array
		for ($i = 1; $i <= count($postings); $i += 2) {
			$docid = $postings[$i];
			$tf = $postings[$i+1];
			$rsv = $idf * $tf * ($k1 + 1) / ($tf + $k1 * (1 - $b + $b * ($doc_lengths[$docid+1] / $average_length)));
			if (array_key_exists($docid, $accumulators))
				$accumulators[$docid] += $rsv;
			else
				$accumulators[$docid] = $rsv;
		}
	}

	// Sort the results list. Tie break on the document ID
	krsort($accumulators);
	arsort($accumulators);

	// Print the (at most) top 1000 documents in the results list in TREC eval format which is:
	// query-id Q0 document-id rank score run-name
	$i = 1;
	foreach ($accumulators as $docid => $tf) {
		if ($i > 1000)
			break;
		printf("%s Q0 %s %d %.4f JASSjr\n", $query_id, $doc_ids[$docid], $i, $tf);
		$i++;
	}
}
?>
