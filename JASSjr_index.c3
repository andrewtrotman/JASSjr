/*
	JASSjr_index.c3
	---------------
	Copyright (c) 2026 Vaughan Kitchen
	Minimalistic BM25 search engine.
*/

import std::collections::list;
import std::collections::map;
import std::collections::pair;
import std::core::ascii;
import std::core::mem;
import std::io;

alias PostingsList = List {Pair {int, int}};	// a postings list is an ordered pair of <docid,tf>
HashMap {String, PostingsList} vocab;		// the in-memory index
List {String} doc_ids;				// the primary keys
List {int} doc_lengths;				// hold the length of each document

/*
	Struct lexer
	------------
*/
struct Lexer
{
	String buffer;
	int current;
}

fn String? Lexer.next(Lexer *l)
{
	/*
		Skip over whitespace and punctuation (but not XML tags)
	*/
	for (; l.current < l.buffer.len && !ascii::is_alnum(l.buffer[l.current]) && l.buffer[l.current] != '<'; l.current++);

	/*
		A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
	*/
	if (l.current >= l.buffer.len) return io::EOF~;

	int start = l.current;
	if (ascii::is_alnum(l.buffer[l.current]))
	{
		// TREC <DOCNO> primary keys have a hyphen in them
		for (; l.current < l.buffer.len && (ascii::is_alnum(l.buffer[l.current]) || l.buffer[l.current] == '-'); l.current++);
	}
	else if (l.buffer[l.current] == '<')
	{
		for (l.current++; l.current < l.buffer.len && l.buffer[l.current-1] != '>'; l.current++);
	}

	/*
		Return the token
	*/
	return l.buffer[start..l.current-1];
}

fn int main(String[] args)
{
	// Force the index onto the heap for performance
	vocab.init(mem);
	doc_ids.init(mem);
	doc_lengths.init(mem);

	int docid = -1;
	int document_length = 0;

	/*
		Make sure we have one parameter, the filename
	*/
	if (args.len != 2)
	{
		io::eprintfn("Usage: %s <infile.xml>", args[0]);
		return 1;
	}

	/*
		open the file to index
	*/
	File fp = io::file::open(args[1], "rb")!!;
	defer fp.close();

	bool push_next = false; // is the next token the primary key?
	while (true)
	{
		@pool()
		{
			String? line = io::readline(tmem, &fp);
			if (catch line) break;

			Lexer lexer = { line, 0 };
			while (try String token = lexer.next())
			{
				/*
					If we see a <DOC> tag then we're at the start of the next document
				*/
				if (token == "<DOC>")
				{
					/*
						Save the previous document length
					*/
					if (docid != -1) doc_lengths.push(document_length);

					/*
						Move on to the next document
					*/
					docid++;
					document_length = 0;

					if ((docid % 1000) == 0) io::printfn("%d documents indexed", docid);
				}

				/*
					if the last token we saw was a <DOCNO> then the next token is the primary key
				*/
				if (push_next)
				{
					String primary_key = (String)@clone_slice((char[])token);
					doc_ids.push(primary_key);
					push_next = false;
				}
				if (token == "<DOCNO>") push_next = true;

				/*
					Don't index XML tags
				*/
				if (token[0] == '<') continue;

				/*
					lower case the string
				*/
				for (int i = 0; i < token.len; i++) token[i] = ascii::to_lower(token[i]);

				/*
					truncate any long tokens at 255 charactes (so that the length can be stored first and in a single byte)
				*/
				if (token.len > 255) token = token[:255];

				/*
					add the posting to the in-memory index
				*/
				PostingsList* list = vocab.get_or_create_ref(token);
				if (list.len() == 0)
				{
					// if the term isn't in the vocab yet
					list.init(mem);
					list.push({ docid, 1 });
				}
				else if (list.last()!!.first != docid)
				{
					// if the docno for this occurence has changed then create a new <d,tf> pair
					list.push({ docid, 1 });
				}
				else
				{
					// else increase the tf
					list.get_ref(list.len() - 1).second++;
				}

				/*
					Compute the document length
				*/
				document_length++;
			}
		};
	}

	/*
		If we didn't index any documents then we're done.
	*/
	if (docid == -1) return 0;

	/*
		Save the final document length
	*/
	doc_lengths.push(document_length);

	/*
		tell the user we've got to the end of parsing
	*/
	io::printfn("Indexed %d documents. Serialising...", docid+1);

	/*
		store the primary keys
	*/
	File docid_fp = io::file::open("docids.bin", "w+b")!!;
	defer docid_fp.close();
	foreach (id : doc_ids) io::fprintn(&docid_fp, id)!!;

	File postings_fp = io::file::open("postings.bin", "w+b")!!;
	defer postings_fp.close();
	File vocab_fp = io::file::open("vocab.bin", "w+b")!!;
	defer vocab_fp.close();

	/*
		serialise the in-memory index to disk
	*/
	foreach (term : vocab.iter())
	{
		/*
			write the postings list to one file
		*/
		int where = (int)postings_fp.cursor()!!;
		int size = int::size * (int)term.value.len() * 2;
		postings_fp.write(((char*)term.value.entries)[:size])!!;

		/*
			write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
		*/
		vocab_fp.write_byte((char)term.key.len)!!;
		vocab_fp.write(term.key)!!;
		vocab_fp.write_byte('\0')!!;
		vocab_fp.write(@as_char_view(where))!!;
		vocab_fp.write(@as_char_view(size))!!;
	}

	/*
		store the document lengths
	*/
	File lengths_fp = io::file::open("lengths.bin", "w+b")!!;
	defer lengths_fp.close();
	lengths_fp.write(((char*)doc_lengths.entries)[:int::size * doc_lengths.len()])!!;

	return 0;
}
