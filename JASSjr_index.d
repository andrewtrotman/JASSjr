#!/usr/bin/env dub
/+ dub.sdl: +/

/*
	JASSJR_INDEX.D
	--------------
	Copyright (c) 2024 Vaughan Kitchen
	Minimalistic BM25 search engine.
*/

import std.algorithm : each;
import std.array : array;
import std.ascii : isAlphaNum;
import std.outbuffer : OutBuffer;
import std.stdio : File, writefln, writeln;
import std.typecons : Tuple, tuple;
import std.uni : toLower;

class Lexer
{
	char[] buffer;
	int start = 0;
	int end;

	this(char[] buffer)
	{
		this.buffer = buffer;
	}

	@property bool empty() {
		// Skip over whitespace and punctuation (but not XML tags)
		while (start < buffer.length && !isAlphaNum(buffer[start]) && buffer[start] != '<')
			start++;

		return start >= buffer.length;
	}

	@property string front()
	{
		// A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
		end = start;
		if (isAlphaNum(buffer[end]))
			while (end < buffer.length && (isAlphaNum(buffer[end]) || buffer[end] == '-'))
				end++;
		else if (buffer[end] == '<')
			for (end++; end < buffer.length && buffer[end-1] != '>'; end++)
			{ /* do nothing */ }

		// Copy and return the token
		return buffer[start .. end].idup();
	}

	void popFront()
	{
		start = end;
	}
}


// Simple indexer for TREC WSJ collection
int main(string[] argv)
{
	alias Posting = Tuple!(int, "docid", int, "tf");
	alias posting = tuple!("docid", "tf");

	Posting[][string] vocab;
	string[] doc_ids;
	int[] length_vector;

	auto docid = -1;
	auto document_length = 0;

	// Make sure we have one parameter, the filename
	if (argv.length != 2)
	{
		writefln("Usage: %s <infile.xml>", argv[0]);
		return 0;
	}

	auto fh = File(argv[1]);

	auto push_next = false;
	foreach (char[] line; fh.byLine())
	{
		auto lex = new Lexer(line);
		foreach (string token; lex)
		{
			if (token == "<DOC>")
			{
				// Save the previous document length
				if (docid != -1)
					length_vector ~= document_length;

				// Move on to the next document
				docid++;
				document_length = 0;

				if ((docid % 1000) == 0)
					writeln(docid, " documents indexed");

			}
			// If the last token we saw was a <DOCNO> then the next token is the primary key
			if (push_next)
			{
				doc_ids ~= token;
				push_next = false;
			}
			if (token == "<DOCNO>")
				push_next = true;

			// Don't index XML tags
			if (token[0] == '<')
				continue;

			// Lower case the string
			token = token.toLower();

			// Truncate any long tokens at 255 characters (so that the length can be stored first and in a single byte)
			if (token.length > 0xFF)
				token = token[0 .. 0xFF];

			// Add the posting to the in-memory index
			vocab.update(token,
					() => [ posting(docid, 1) ], // if the term isn't in the vocab yet
					(ref Posting[] postings) {
						if (postings[$-1].docid != docid)
							postings ~= posting(docid, 1); // if the docno for this occurence has changed then create a new <d,tf> pair
						else
							postings[$-1].tf++; // else increase the tf
					});

			// Compute the document length
			document_length++;
		}
	}

	// Save the final document length
	length_vector ~= document_length;

	// Tell the user we've got to the end of parsing
	writefln("Indexed %d documents. Serialising", docid+1);

	// Store the primary keys
	auto docids_fh = File("docids.bin", "w");
	doc_ids.each!(line => docids_fh.writeln(line));

	auto postings_fh = File("postings.bin", "w");
	auto vocab_fh = File("vocab.bin", "w");
	// Serialise the in-memory index to disk
	OutBuffer out_buf = new OutBuffer();
	foreach (term, postings; vocab)
	{
		// Write the postings list to one file
		auto where = postings_fh.tell();
		postings_fh.rawWrite(postings);

		// Write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
		out_buf.clear();
		out_buf.write(cast(ubyte) term.length);
		out_buf.write(term);
		out_buf.write(cast(ubyte) 0);
		out_buf.write(cast(int) where);
		out_buf.write(cast(int) postings.length * 8);
		vocab_fh.rawWrite(out_buf.toBytes());
	}


	// Store the document lengths
	File("lengths.bin", "w").rawWrite(length_vector);

	return 0;
}
