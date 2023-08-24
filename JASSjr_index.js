#!/usr/bin/env node

// JASSjr_index.js
// Copyright (c) 2023 Vaughan Kitchen
// Minimalistic BM25 search engine.

var fs = require('fs');
var os = require('os');
var readline = require('readline');

if (process.argv.length != 3) {
	console.log('Usage: %s %s <infile.xml>', process.argv[0], process.argv[1]);
	process.exit(1);
}

var vocab = {};
var doc_ids = [];
var length_vector = [];

var docid = -1;
var document_length = 0;
var push_next = false;

var rl = readline.createInterface({
	input: fs.createReadStream(process.argv[2]),
	crlfDelay: Infinity,
});

var token_count = 0;
var line_count = 0;

rl.on('line', function (line) {
	for (var match of line.matchAll(/[a-zA-Z0-9][a-zA-Z0-9-]*|<[^>]*>/g)) {
		var token = match[0];
		if (token == '<DOC>') {
			if (docid != -1)
				length_vector.push(document_length);
			docid++;
			document_length = 0;
			if (docid % 1000 == 0)
				console.log('%d documents indexed', docid);
		}
		if (push_next) {
			doc_ids.push(token);
			push_next = false;
		}
		if (token == '<DOCNO>')
			push_next = true;
		if (token[0] == '<')
			continue;

		token = token.toLowerCase();

		token = token.slice(0, 255);

		if (!vocab.hasOwnProperty(token))
			vocab[token] = [];

		postings_list = vocab[token];
		if (postings_list.length == 0 || postings_list[postings_list.length - 2] != docid) {
			postings_list.push(docid);
			postings_list.push(1);
		} else {
			postings_list[postings_list.length-1]++;
		}

		document_length += 1;
	}
});

rl.on('close', function () {
	if (docid == -1)
		process.exit(0);

	console.log('Indexed %d documents. Serialising...', docid + 1);

	length_vector.push(document_length);

	fs.writeFileSync('docids.bin', doc_ids.join(os.EOL) + '\n');

	fs.writeFileSync('lengths.bin', Uint32Array.from(length_vector));

	var postings_fd = fs.createWriteStream('postings.bin');
	var vocab_fd = fs.createWriteStream('vocab.bin');

	var buffer8 = Buffer.alloc(1);
	var buffer32 = Buffer.alloc(4);

	var where = 0;
	for (var term in vocab) {
		var postings = Uint32Array.from(vocab[term]);
		postings_fd.write(Buffer.from(postings.buffer));

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

	postings_fd.end();
	vocab_fd.end();
});

