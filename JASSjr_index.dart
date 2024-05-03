#!/usr/bin/env dart

// Copyright (c) 2024 Vaughan Kitchen
// Minimalistic BM25 search engine.

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

final vocab = HashMap(); // the in-memory index
final docids = []; // the primary keys
final List<int> doc_lengths = []; // hold the length of each document

var docid = -1;
var document_length = 0;
var push_next = false; // is the next token the primary key?

void main(List<String> args) async {
	// Make sure we have one parameter, the filename
	if (args.length != 1) {
		print('Usage: ${Platform.script} <infile.xml>');
		exit(1);
	}

	await File(args[0]).openRead().transform(AsciiDecoder()).transform(LineSplitter()).forEach((line) {
		// A token is either an XML tag '<'..'>' or a sequence of alpha-numerics
  		// TREC <DOCNO> primary keys have a hyphen in them
		for (final match in RegExp(r'[a-zA-Z0-9][a-zA-Z0-9-]*|<[^>]*>').allMatches(line)) {
			var token = match[0];
			if (token == null)
				continue;
			// If we see a <DOC> tag then we're at the start of the next document
			if (token == '<DOC>') {
				// Save the previous document length
				if (docid != -1)
					doc_lengths.add(document_length);
				// Move on to the next document
				docid++;
				document_length = 0;
				if (docid % 1000 == 0)
					print('$docid documents indexed');
			}
			// If the last token we saw was a <DOCNO> then the next token is the primary key
			if (push_next) {
				docids.add(token);
				push_next = false;
			}
			if (token == '<DOCNO>')
				push_next = true;
			// Don't index XML tags
			if (token[0] == '<')
				continue;

			// Lowercase the string
			token = token.toLowerCase();

			// Truncate any long tokens at 255 characters (so that the length can be stored first and in a single byte)
			if (token.length > 255)
				token = token.substring(0, 256);

			// Add the posting to the in-memory index
			var postings_list = vocab[token];
			if (postings_list == null) {
				// If the term isn't in the vocab yet
				vocab[token] = [docid, 1];
			} else if (postings_list[postings_list.length - 2] != docid) {
				postings_list.add(docid);
				postings_list.add(1);
			} else {
				postings_list[postings_list.length - 1]++;
			}

			// Compute the document length
			document_length++;
		}
	});

	// If we didn't index any documents then we're done
	if (docid == -1)
			exit(0);

	// Save the final document length
	doc_lengths.add(document_length);

	// Tell the user we've got to the end of parsing
	print('Indexed ${docid + 1} documents. Serialising...');

	// Store the primary keys
	final docids_fh = File('docids.bin').openWrite();
	docids_fh.writeAll(docids, '\n');
	docids_fh.write('\n');

	// Store the vocab and postings
	final vocab_fh = File('vocab.bin').openWrite();
	final postings_fh = File('postings.bin').openWrite();

	var bytes_written = 0;
	vocab.forEach((term, postings) {
		// Write the postings list to one file
		final where = bytes_written;
		postings_fh.add(Int32List.fromList(postings).buffer.asUint8List());
		bytes_written = (bytes_written + postings.length * 4).toInt(); // + returns num

		// Write the vocabulary to a second file (Uint8 length, String term, 0, Int32 where, Int32 size)
		vocab_fh.add(Uint8List.fromList([term.length]));
		vocab_fh.write(term);
		vocab_fh.add(Uint8List.fromList([0]));
		vocab_fh.add(Uint32List.fromList([where, postings.length * 4]).buffer.asUint8List());
	});

	// Store the document lengths
	File('lengths.bin').writeAsBytes(Int32List.fromList(doc_lengths).buffer.asUint8List());
}
