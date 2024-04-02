/*
	JASSJR_SEARCH.CPP
	-----------------
	Copyright (c) 2019 Andrew Trotman and Kat Lilly
	Minimalistic BM25 search engine.
*/
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>

#include <algorithm>
#include <string>
#include <vector>
#include <iomanip>
#include <iostream>
#include <unordered_map>

/*
	CONSTANTS
	---------
*/
static constexpr double k1 = 0.9;				// BM25 k1 parameter
static constexpr double b = 0.4;					// BM25 b parameter

/*
	CLASS VOCAB_ENTRY
	-----------------
*/
class vocab_entry
	{
	public:
		int32_t where, size;		// where on the disk and how large (in bytes) is the postings list?

		vocab_entry() : where(0), size(0) {}
		vocab_entry(int32_t where, int32_t size): where(where), size(size) {}
	};

/*
	READ_ENTIRE_FILE()
	------------------
	Read the entire contents of the given file into memory and return its size.
*/
char *read_entire_file(const char *filename, size_t &file_size)
{
char *block = NULL;
FILE *fp;
struct stat details;

file_size = 0;
if ((fp = fopen(filename, "rb")) == NULL)
	return NULL;

if (fstat(fileno(fp), &details) == 0)
	if ((block = (char *)malloc(details.st_size)) != NULL)
		fread(block, 1, details.st_size, fp);

file_size = details.st_size;

fclose(fp);
return block;
}

/*
	COMPARE_RSV()
	-------------
	Callback from std::sort for two rsv values. Tie break on the document id.
*/
bool compare_rsv(double *first, double *second)
{
return *first > *second ? true : *first == *second ? first > second : false;
}

/*
	MAIN()
	------
	Simple search engine ranking on BM25.
*/
int main(int argc, const char *argv[])
{
size_t file_size;
char *vocab = read_entire_file("vocab.bin", file_size);
char *current;
int32_t where, size, string_length;
char seperators[255];
char *into = seperators;
int32_t *length_vector;

/*
	Set up the tokenizer seperator characters
*/
for (int32_t ch = 1; ch <= 0xFF; ch++)
	if (!isalnum(ch) && ch != '<' && ch != '>' && ch != '-')
		*into++ = ch;
*into++ = '\0';

/*
	Read the document lengths
*/
size_t length_filesize_in_bytes;
double average_document_length = 0;
length_vector = reinterpret_cast<int32_t *>(read_entire_file("lengths.bin", length_filesize_in_bytes));
if (length_filesize_in_bytes == 0)
	exit(printf("Could not find an index in the current directory\n"));

/*
	Compute the average document length for BM25
*/
double documents_in_collection = length_filesize_in_bytes / sizeof(int32_t);
int32_t max_docs = static_cast<int32_t>(documents_in_collection);
for (int32_t document = 0; document < max_docs; document++)
	average_document_length += length_vector[document];
average_document_length /= documents_in_collection;

/*
	Read the primary_keys
*/
char buffer[1024];													// the user's query (and also used to load the vocab)
std::vector<std::string>primary_key;							// the list of global IDs (i.e. primary keys)
FILE *fp = fopen("docids.bin", "rb");
while (fgets(buffer, sizeof(buffer), fp) != NULL)
	{
	buffer[strlen(buffer) - 1] = '\0';		// strip the '\n' that fgets leaves on the end
	primary_key.push_back(std::string(buffer));
	}
 
 /*
	Open the postings list file
*/
FILE *postings_file = fopen("postings.bin", "rb");
 
/*
	Build the vocabulary in memory
*/
std::unordered_map<std::string, vocab_entry>dictionary;	// the vocab
current = vocab;
while (current < vocab + file_size)
	{
	string_length = *current;
	where = *((int32_t *)(current + string_length + 2));			// +1 for the length and + 1 for the '\0'
	size = *((int32_t *)(current + string_length + 2 + sizeof(int32_t)));			// +1 for the length and + 1 for the '\0'

	dictionary[std::string(current + 1)] = vocab_entry(where, size);
	current += string_length + 2 + 2 * sizeof(int32_t);
	}
 
/*
	Allocate buffers
*/
int32_t *postings_buffer= new int32_t[(max_docs + 1) * 2];			// the postings list once loaded from disk
double *rsv = new double[max_docs];											// array of rsv values

/*
	Set up the rsv pointers
*/
double **rsv_pointers = new double *[max_docs];	
double **rsvp = rsv_pointers;
for (double *pointer = rsv; pointer < rsv + max_docs; pointer++)
	*rsvp++ = pointer;

/*
	Search (one query per line)
*/
while (fgets(buffer, sizeof(buffer), stdin) !=  NULL)
	{
	/*
		Zero the accumulator array.
	*/
	memset(rsv, 0, sizeof(*rsv) * max_docs);
	bool first_term = true;
	long query_id = 0;
	for (char *token = strtok(buffer, seperators); token != NULL; token = strtok(NULL, seperators))
		{
		/*
			If the first token is a number then assume a TREC query number, and skip it
		*/
		if (first_term && isdigit(*buffer))
			{
			query_id = atol(buffer);
			first_term = false;
			continue;
			}

		first_term = false;

		/*
			Does the term exist in the collection?
		*/
		vocab_entry term_details;
		if ((term_details = dictionary[std::string(token)]).size != 0)
			{
			/*
				Seek and read the postings list
			*/
			fseek(postings_file, term_details.where, SEEK_SET);
			(void)fread(postings_buffer, 1, term_details.size, postings_file);
			int32_t postings = term_details.size / (sizeof(int32_t) * 2);
			std::pair<int32_t, int32_t> *list = (std::pair<int32_t, int32_t> *)(&postings_buffer[0]);
	
			/*
				Compute the IDF component of BM25 as log(N/n).
				if IDF == 0 then don't process this postings list as the BM25 contribution of this term will be zero.
			*/
			if (documents_in_collection != postings)
				{
				double idf = log(documents_in_collection / postings);
		
				/*
					Process the postings list by simply adding the BM25 component for this document into the accumulators array
				*/
				for (int32_t which = 0; which < postings; which++, list++)
					{
					int32_t d = list->first;
					int32_t tf = list->second;
					rsv[d] += idf * ((tf * (k1 + 1)) / (tf + k1 * (1 - b + b * (length_vector[d] / average_document_length))));
					}
				}
			}
		}

	/*
		Sort the results list
	*/
	std::sort(&rsv_pointers[0], &rsv_pointers[max_docs], compare_rsv);

	/*
		Print the (at most) top 1000 documents in the results list in TREC eval format which is:
		query-id Q0 document-id rank score run-name
	*/
	std::cout << std::fixed << std::setprecision(4);

	for (int32_t position = 0; *rsv_pointers[position] != 0.0 && position < 1000; position++)
		std::cout << query_id << " Q0 " << primary_key[rsv_pointers[position] - rsv] << " " << position + 1 << " " << std::setw(2) << *rsv_pointers[position] << " JASSjr\n";
	}
}
