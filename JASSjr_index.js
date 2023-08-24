#!/usr/bin/env node

// JASSjr_index.js
// Copyright (c) 2023 Vaughan Kitchen
// Minimalistic BM25 search engine.

var fs = require('fs');
var os = require('os');
var readline = require('readline');

// Make sure we have one paramter, the filename
if (process.argv.length != 3) {
	console.log('Usage: %s %s <infile.xml>', process.argv[0], process.argv[1]);
	process.exit(1);
}

var vocab = {}; // the in-memory index
var doc_ids = []; // the primary keys
var length_vector = []; // hold the length of each document

var docid = -1;
var document_length = 0;
var push_next = false; // is the next token the primary key?

var rl = readline.createInterface({
	input: fs.createReadStream(process.argv[2]),
	crlfDelay: Infinity,
});

var token_count = 0;
var line_count = 0;

rl.on('line', function (line) {
	// A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
	// TREC <DOCNO> primary keys have a hyphen in them
	for (var match of line.matchAll(/[a-zA-Z0-9][a-zA-Z0-9-]*|<[^>]*>/g)) {
		var token = match[0];
		// If we see a <DOC> tag then we're at the start of the next document
		if (token == '<DOC>') {
			// Save the previous document length
			if (docid != -1)
				length_vector.push(document_length);
			// Move on to the next document
			docid++;
			document_length = 0;
			if (docid % 1000 == 0)
				console.log('%d documents indexed', docid);
		}
		// if the last token we saw was a <DOCNO> then the next token is the primary key
		if (push_next) {
			doc_ids.push(token);
			push_next = false;
		}
		if (token == '<DOCNO>')
			push_next = true;
		// Don't index XML tags
		if (token[0] == '<')
			continue;

		// lower case the string
		token = token.toLowerCase();

		// truncate any long tokens at 255 charactes (so that the length can be stored first and in a single byte)
		token = token.slice(0, 255);

		if (!vocab.hasOwnProperty(token))
			vocab[token] = [];

		// add the posting to the in-memory index
		postings_list = vocab[token];
		if (postings_list.length == 0 || postings_list[postings_list.length - 2] != docid) {
			postings_list.push(docid);
			postings_list.push(1);
		} else {
			postings_list[postings_list.length-1]++;
		}

		// Compute the document length
		document_length += 1;
	}
});

rl.on('close', function () {
	// If we didn't index any documents then we're done.
	if (docid == -1)
		process.exit(0);

	// tell the user we've got to the end of parsing
	console.log('Indexed %d documents. Serialising...', docid + 1);

	// Save the final document length
	length_vector.push(document_length);

	// store the primary keys
	fs.writeFileSync('docids.bin', doc_ids.join(os.EOL) + '\n');

	// store the document lengths
	fs.writeFileSync('lengths.bin', Uint32Array.from(length_vector));

	var postings_fd = fs.createWriteStream('postings.bin');
	var vocab_fd = fs.createWriteStream('vocab.bin');

	var buffer8 = Buffer.alloc(1);
	var buffer32 = Buffer.alloc(4);

	// serialise the in-memory index to disk
	var where = 0;
	for (var term in vocab) {
		// write the postings list to one file
		var postings = Uint32Array.from(vocab[term]);
		postings_fd.write(Buffer.from(postings.buffer));

		// write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
		buffer8.writeUInt8(term.length);
		vocab_fd.write(Buffer.from(buffer8));

		vocab_fd.write(term);

		buffer8.writeUInt8(0);
		vocab_fd.write(Buffer.from(buffer8));

		buffer32.writeUInt32LE(where);
		vocab_fd.write(Buffer.from(buffer32));

		buffer32.writeUInt32LE(postings.buffer.byteLength);
		vocab_fd.write(Buffer.from(buffer32));

		where += postings.buffer.byteLength;
	}

	// clean up
	postings_fd.end();
	vocab_fd.end();
});

