#!/usr/bin/env dart

// Copyright (c) 2024 Vaughan Kitchen
// Minimalistic BM25 search engine.

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const k1 = 0.9; // BM25 k1 parameter
const b = 0.4; // BM25 b parameter

void main() {
	// Read the primary_keys
	final doc_ids = File('docids.bin').readAsLinesSync();

	// Read the document lengths
	final doc_lengths = Int32List.view(File('lengths.bin').readAsBytesSync().buffer);

	// Compute the average document length for BM25
	final average_length = doc_lengths.reduce((a, b) => a + b) / doc_lengths.length;

	// Read the vocab
	final vocab = HashMap();
	final vocab_raw = File('vocab.bin').readAsBytesSync();
	final vocab_blob = ByteData.view(vocab_raw.buffer);

	// Decode the vocabulary (Uint8 strlen, String, 0, Int32 where, Int32 size)
	var offset = 0;
	while (offset < vocab_blob.lengthInBytes) {
		final length = vocab_blob.getUint8(offset);
		offset++;

		final term = ascii.decode(vocab_raw.sublist(offset, offset + length));
		offset += length + 1; // null terminated

		final where = vocab_blob.getInt32(offset, Endian.host);
		offset += 4;
		final size = vocab_blob.getInt32(offset, Endian.host);
		offset += 4;

		vocab[term] = (where, size);
	}

	// Open the postings list file
	final postings_fh = File('postings.bin').openSync();

	// Allocate buffers
	final accumulators = List.filled(doc_ids.length, 0.0);
	final pointers = List.generate(doc_ids.length, (i) => i);

	// Search (one query per line)
	while (true) {
		final query = stdin.readLineSync();
		if (query == null)
			break;

		// Zero the accumulator array
		accumulators.fillRange(0, accumulators.length, 0);

		final terms = query.split(RegExp(r'\W+'));
		if (terms.length == 0)
			continue;

		var query_id = 0;
		var start_at = 0;

		// If the first token is a number then assume a TREC query number, and skip it
		final number = int.tryParse(terms[0]);
		if (number != null) {
			query_id = number;
			start_at = 1;
		}

		for (final term in terms.skip(start_at)) {
			// Does the term exist in the collection?
			final pair = vocab[term];
			if (pair == null)
				continue;

			final (where, size) = pair;

			// Seek and read the postings list
			postings_fh.setPositionSync(where);
			final postings = Int32List.view(postings_fh.readSync(size).buffer);

			// Compute the IDF component of BM25 as log(N/n)
			final idf = log(doc_ids.length / (postings.length / 2));

			for (var i = 0; i < postings.length; i += 2) {
				final docid = postings[i];
				final tf = postings[i+1];
				accumulators[docid] += idf * tf * (k1 + 1) / (tf + k1 * (1 - b + b * doc_lengths[docid] / average_length));
			}
		}

		// Sort the results list. Tie break on the document ID
		pointers.sort((a, b) {
			final cmp = accumulators[b].compareTo(accumulators[a]);
			if (cmp != 0) return cmp;
			return b.compareTo(a);
		});

		// Print the (at most) top 1000 documents in the results list in TREC eval format which is:
		// query-id Q0 document-id rank score run-name
		for (final (i, docid) in pointers.indexed) {
			if (i == 1000 || accumulators[docid] == 0)
				break;
			final rsv = accumulators[docid].toStringAsFixed(4);
			print('$query_id Q0 ${doc_ids[docid]} ${i + 1} $rsv JASSjr');
		}
	}
}
