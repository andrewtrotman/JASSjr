#!/usr/bin/env node

// JASSjr_search.js
// Copyright (c) 2023 Vaughan Kitchen
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
var postings_raw = fs.readFileSync('postings.bin');
var doc_lengths = fs.readFileSync('lengths.bin');
var ids = fs.readFileSync('docids.bin', 'utf8').split(os.EOL);

var documents_in_collection = doc_lengths.length / 4;
var average_document_length = 0;
for (var i = 0; i < doc_lengths.length; i += 4)
	average_document_length += doc_lengths.subarray(i, i+4).readUInt32LE();
average_document_length /= documents_in_collection;

var vocab = {};

// decode the vocabulary (one byte length, string, '\0', 4 byte where, 4 byte size)
for (var offset = 0; offset < vocab_raw.length;) {
	var length = vocab_raw[offset];
	offset++;

	var word = vocab_raw.subarray(offset, offset+length).toString();
	offset += length+1; // null terminated

	vocab[word] = offset;
	offset += 8;
}

readline.question('', search);

function search(query) {
	var query_id = 0;
	var accumulators = new Array(documents_in_collection);

	var terms = query.split(' ');
	if (!isNaN(terms[0]))
		query_id = terms.shift();

	terms.forEach(function (term) {
		var offset = vocab[term];
		if (offset === undefined)
			return;

		var where = vocab_raw.subarray(offset, offset+4).readUInt32LE();
		var size = vocab_raw.subarray(offset+4, offset+8).readUInt32LE();

		var documents_in_postings = size / 8;
		var idf = Math.log(documents_in_collection / documents_in_postings)

		for (var i = where; i < where+size; i += 8) {
			var docid = postings_raw.subarray(i, i+4).readUInt32LE();
			var freq = postings_raw.subarray(i+4, i+8).readUInt32LE();

			var doc_length = doc_lengths.subarray(docid*4, docid*4+4).readUInt32LE();

			var rsv = idf * ((freq * (k1 + 1)) / (freq + k1 * (1 - b + b * (doc_length / average_document_length))))
			var current = accumulators[docid] || [0, 0]
			accumulators[docid] = [docid, current[1] + rsv];
		}
	});

	accumulators.sort(function (a, b) { return b[1] - a[1] || b[0] - a[0] });

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
