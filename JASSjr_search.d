#!/usr/bin/env dub
/+ dub.sdl: +/

/*
	JASSJR_SEARCH.D
	---------------
	Copyright (c) 2024 Vaughan Kitchen
	Minimalistic BM25 search engine.
*/

import std.algorithm : sort, sum;
import std.array : array;
import std.bitmanip : read;
import std.conv : ConvException, to;
import std.exception : collectException;
import std.file : read;
import std.math : log;
import std.range : popFrontN, split;
import std.stdio : File, lines, SEEK_SET, stdin, writefln;
import std.system : endian;
import std.typecons : Tuple, tuple;

const auto k1 = 0.9; // BM25 k1 parameter
const auto b = 0.4;  // BM25 b parameter

// Simple search engine ranking on BM25.
void main(string[] argv)
{
	// Read the document lengths
	auto document_lengths = cast(int[]) read("lengths.bin");

	// Compute the average document length for BM25
	auto average_document_length = cast(double) sum(document_lengths) / cast(double) document_lengths.length;

	// Read the primary keys
	auto primary_keys = File("docids.bin").byLineCopy().array();

	// Build the vocabulary in memory
	Tuple!(int, int)[string] vocab;

	auto vocab_raw = cast(ubyte[]) read("vocab.bin");
	while (vocab_raw.length > 0)
	{
		auto term_len = vocab_raw.read!ubyte();
		auto term = cast(string) vocab_raw[0 .. term_len];
		vocab_raw.popFrontN(term_len + 1); // also read the '\0' string terminator
		auto where = vocab_raw.read!(int, endian)();
		auto size = vocab_raw.read!(int, endian)();
		vocab[term] = tuple(where, size);
	}

	// Open the postings list file
	auto postings_file = File("postings.bin");
	auto postings = new Tuple!(int, int)[primary_keys.length];

	// Allocate buffers
	auto rsv = new double[primary_keys.length];

	// Set up the rsv pointers
	auto rsv_pointers = new double*[primary_keys.length];
	foreach (size_t i, ref r; rsv)
		rsv_pointers[i] = &r;

	// Search (one query per line)
	foreach (string line; stdin.lines())
	{
		// Zero the accumulator array.
		rsv[] = 0;
		int query_id = 0;
		foreach (size_t i, string token; line.split())
		{
			// If the first token is a number then assume a TREC query number, and skip it
			if (i == 0 && collectException!ConvException(token.to!int(), query_id) is null)
				continue;

			// Does the term exist in the collection?
			if (token !in vocab)
				continue;
			auto term_details = vocab[token];

			auto postings_length = term_details[1] / (int.sizeof * 2);

			// If IDF == 0 then don't process this postings list as the BM25 contribution of this term will be zero
			if (postings_length == primary_keys.length)
				continue;

			// Seek and read the postings list
			postings_file.seek(term_details[0], SEEK_SET);
			postings_file.rawRead(postings[0 .. postings_length]);

			// Compute the IDF component of BM25 as log(N/n).
			auto idf = log(cast(double) primary_keys.length / cast(double) postings_length);

			// Process the postings list by simply adding the BM25 component for this document into the accumulators array
			foreach (Tuple!(int, int) post; postings[0 .. postings_length])
			{
				auto docid = post[0], tf = cast(double) post[1];
				rsv[docid] += idf * tf * (k1 + 1) / (tf + k1 * (1 - b + b * (cast(double) document_lengths[docid] / average_document_length)));
			}
		}

		// Sort the results list
		rsv_pointers.sort!("*a == *b ? a > b : *a > *b");

		// Print the (at most) top 1000 documents in the results list in TREC eval format which is:
		// query-id Q0 document-id rank score run-name
		foreach (size_t i, double *r; rsv_pointers)
		{
			if (*r == 0 || i == 1000)
				break;
			writefln("%d Q0 %s %d %.4f JASSjr", query_id, primary_keys[r - &rsv[0]], i+1, *r);
		}
	}
}
