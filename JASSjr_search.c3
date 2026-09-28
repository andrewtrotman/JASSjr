/*
	JASSjr_search.c3
	----------------
	Copyright (c) 2026 Vaughan Kitchen
	Minimalistic BM25 search engine.
*/

import std::collections::list;
import std::collections::map;
import std::core::ascii;
import std::core::mem;
import std::io;
import std::io::file;
import std::math;
import std::sort;

/*
	CONSTANTS
	---------
*/
const double K1 = 0.9;	// BM25 k1 parameter
const double B = 0.4;	// BM25 b parameter

/*
	STRUCT VOCAB_ENTRY
	------------------
*/
struct VocabEntry
{
	int where, size;
}

/*
	COMPARE_RSV()
	-------------
	Callback from std::sort for two rsv values. Tie break on the document id.
*/
fn long compare_rsv(double *first, double *second)
{
	return (*first > *second) ? -1 : (*first < *second) ? 1 : second - first;
}

/*
	MAIN()
	------
	Simple search engine ranking on BM25.
*/
fn void main()
{
	/*
		Read the document lengths
	*/
	char[] data = file::load(mem, "lengths.bin")!!;
	int[] doc_lengths = ((int*)data.ptr)[:data.len / int::size];

	/*
		Compute the average document length for BM25
	*/
	long max_docs = doc_lengths.len;
	double documents_in_collection = doc_lengths.len;
	double average_document_length = array::@sum(doc_lengths) / documents_in_collection;

	/*
		Read the primary keys
	*/
	List {String} primary_key = list::ONHEAP {String}; // the list of global IDs (i.e. primary keys)
	File fp = file::open("docids.bin", "rb")!!;
	while (try String id = io::readline(mem, &fp)) primary_key.push(id);

	/*
		Open the postings list file
	*/
	File postings_file = file::open("postings.bin", "rb")!!;

	/*
		Build the vocabulary in memory
	*/
	data = file::load(mem, "vocab.bin")!!;
	HashMap {String, VocabEntry} dictionary = map::ONHEAP {String, VocabEntry}; // the vocab
	char* current = data.ptr;
	while (current < data.ptr + data.len)
	{
		char string_length = *current;
		int where = mem::load((int*)(current + string_length + 2), 4);			// +1 for the length and + 1 for the '\0'
		int size = mem::load((int*)(current + string_length + 2 + int::size), 4);	// +1 for the length and + 1 for the '\0'

		dictionary.set((String)current[1:string_length], { where, size });

		current += (long)string_length + 2 + 2 * int::size;
	}

	/*
		Allocate buffers
	*/
	int[] postings_buffer = mem::alloc_array(int, max_docs * 2);
	double[] rsv = mem::alloc_array(double, max_docs);

	/*
		Set up the rsv pointers
	*/
	double*[] rsv_pointers = mem::alloc_array(double*, max_docs);
	for (int i = 0; i < max_docs; i++) rsv_pointers[i] = &rsv[i];

	/*
		Search (one query per line)
	*/
	while (true)
	{
		int query_id = 0;

		/*
			Zero the accumulator array.
		*/
		mem::clear(rsv.ptr, rsv.len * double::size);

		@pool()
		{
			String? line = io::readline(tmem);
			if (catch line) break;

			bool first_term = true;
			Splitter splitter = line.tokenize(" ");
			while (try String token = splitter.next())
			{
				/*
					If the first token is a number then assume a TREC query number, and skip it
				*/
				if (first_term) if (try int num = token.to_int())
				{
					query_id = num;
					first_term = false;
					continue;
				}
				first_term = false;

				/*
					Does the term exist in the collection?
				*/
				VocabEntry? term_details = dictionary.get(token);
				if (catch term_details) continue;

				/*
					if IDF == 0 then don't process this postings list as the BM25 contribution of this term will be zero.
				*/
				int postings = term_details.size / 8;
				if (postings == max_docs) continue;

				/*
					Seek and read the postings list
				*/
				postings_file.seek(term_details.where)!!;
				postings_file.read(((char*)postings_buffer.ptr)[:term_details.size])!!;

				/*
					Compute the IDF component of BM25 as log(N/n).
				*/
				double idf = math::ln(documents_in_collection / postings);

				/*
					Process the postings list by simply adding the BM25 component for this document into the accumulators array
				*/
				for (int which = 0; which < postings*2; which += 2)
				{
					int d = postings_buffer[which];
					int tf = postings_buffer[which + 1];
					rsv[d] += idf * ((tf * (K1 + 1)) / (tf + K1 * (1 - B + B * (doc_lengths[d] / average_document_length))));
				}
			}
		};

		/*
			Sort the results list
		*/
		sort::quicksort(rsv_pointers, &compare_rsv);

		/*
			Print the (at most) top 1000 documents in the results list in TREC eval format which is:
			query-id Q0 document-id rank score run-name
		*/
		for (int position = 0; *rsv_pointers[position] != 0.0 && position < 1000; position++)
		{
			io::printfn("%d Q0 %s %d %.4f JASSjr", query_id, primary_key[rsv_pointers[position] - rsv.ptr], position+1, *rsv_pointers[position]);
		}
	}
}
