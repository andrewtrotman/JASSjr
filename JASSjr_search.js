#!/usr/bin/env node

// JASSjr_search.js
// Copyright (c) 2023, 2024 Vaughan Kitchen
// Minimalistic BM25 search engine.

var fs = require('fs');
var os = require('os');
var readline = require('readline').createInterface({
	input: process.stdin,
	output: process.stdout,
});

var k1 = 0.9; // BM25 k1 parameter
var b = 0.4; // BM25 b parameter

var vocab_raw = fs.readFileSync('vocab.bin');
var doc_lengths = fs.readFileSync('lengths.bin'); // Read the document lengths
var ids = fs.readFileSync('docids.bin', 'utf8').split(os.EOL); // Read the primary_keys

// Compute the average document length for BM25
var documents_in_collection = doc_lengths.length / 4;
var average_document_length = 0;
for (var i = 0; i < doc_lengths.length; i += 4)
	average_document_length += doc_lengths.subarray(i, i+4).readUInt32LE();
average_document_length /= documents_in_collection;

var vocab = {};

// Build the vocabulary in memory (one byte length, string, '\0', 4 byte where, 4 byte size)
for (var offset = 0; offset < vocab_raw.length;) {
	var length = vocab_raw[offset];
	offset++;

	var word = vocab_raw.subarray(offset, offset+length).toString();
	offset += length+1; // null terminated

	var where = vocab_raw.subarray(offset, offset+4).readInt32LE();
	var size = vocab_raw.subarray(offset+4, offset+8).readInt32LE();
	offset += 8;

	vocab[word] = [where, size];
}

// Open the postings list file
var postings = new Int32Array(documents_in_collection * 2);
var postings_fh = fs.openSync('postings.bin');

// Search (one query per line)
readline.question('', search);

function search(query) {
	var terms = query.split(' ');

	var query_id = 0;
	var accumulators = new Array(documents_in_collection); // array of rsv values

	// If the first token is a number then assume a TREC query number, and skip it
	if (!isNaN(terms[0]))
		query_id = terms.shift();

	terms.forEach(function (term) {
		// Does the term exist in the collection?
		var pair = vocab[term];
		if (pair === undefined)
			return;

		var [where, size] = pair;
		var documents_in_postings = size / 8;

		// if IDF == 0 then don't process this postings list as the BM25 contribution of this term will be zero.
		if (documents_in_collection == documents_in_postings)
			return;

		// Seek and read the postings list
		fs.readSync(postings_fh, postings, 0, size, where);

		// Compute the IDF component of BM25 as log(N/n).
		var idf = Math.log(documents_in_collection / documents_in_postings)

		for (var i = 0; i < documents_in_postings * 2; i += 2) {
			var docid = postings[i];
			var freq = postings[i+1];

			var doc_length = doc_lengths.subarray(docid*4, docid*4+4).readUInt32LE();

			// Process the postings list by simply adding the BM25 component for this document into the accumulators array
			var rsv = idf * ((freq * (k1 + 1)) / (freq + k1 * (1 - b + b * (doc_length / average_document_length))))
			var current = accumulators[docid] || [0, 0]
			accumulators[docid] = [docid, current[1] + rsv];
		}
	});

	// Sort the results list. Tie break on the document ID.
	accumulators.sort(function (a, b) { return b[1] - a[1] || b[0] - a[0] });

	// Print the (at most) top 1000 documents in the results list in TREC eval format which is:
	// query-id Q0 document-id rank score run-name
	for (var i = 0; i < accumulators.length; i++) {
		var pair = accumulators[i];
		if (!pair || i == 1000)
			break;
		var docid = pair[0];
		var rsv = pair[1];
		console.log('%d Q0 %s %d %s JASSjr', query_id, ids[docid], i+1, rsv.toLocaleString('en-US', { minimumFractionDigits: 4, maximumFractionDigits: 4 }));
	}

	readline.question('', search);
}
