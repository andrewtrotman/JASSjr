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
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>

#include <string>
#include <vector>
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
		size_t where, size;		// where on the disk and how large (in bytes) is the postings list?

		vocab_entry() : where(0), size(0) {}
		vocab_entry(size_t where, size_t size): where(where), size(size) {}
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
	Callback from qsort for two rsv values.  Tie break on the document id.
*/
int compare_rsv(const void *a, const void *b)
{
double **first = (double **)a;
double **second = (double **)b;

return **first < **second ? 1 : **first == **second ? *first < *second ? 1 : *first == *second ? 0 : -1 : -1;
}

/*
	MAIN()
	------
	Simple search engine ranking on BM25.
*/
int main(int argc, const char * argv[])
{
size_t file_size;
char *vocab = read_entire_file("vocab.txt", file_size);
char *current;
size_t where, size, string_length;
char seperators[255];
char *into = seperators;
int *length_vector;

/*
	Set up the tokenizer seperator characters
*/
for (int ch = 1; ch <= 0xFF; ch++)
	if (!isalnum(ch) && ch != '<' && ch != '>' && ch != '-')
		*into++ = ch;
*into++ = '\0';

/*
	Read the document lengths
*/
size_t length_filesize_in_bytes;
double average_document_length;
length_vector = reinterpret_cast<int *>(read_entire_file("lengths.bin", length_filesize_in_bytes));
if (length_filesize_in_bytes == 0)
	exit(printf("Could not find and index in the current directory\n"));

/*
	Allocate buffers
*/
double documents_in_collection = length_filesize_in_bytes / sizeof(int);
size_t max_docs = static_cast<size_t>(documents_in_collection);
int *postings_buffer= new int[(max_docs + 1) * 2];						// the postings list once loaded from disk
double *rsv = new double[max_docs];												// array of rsv values
double **rsv_pointers = new double *[max_docs];									// pointers to each member of rsv[] so that we can sort

/*
	Compute the average document length for BM25
*/
for (int document = 0; document < max_docs; document++)
	average_document_length += length_vector[document];
average_document_length /= documents_in_collection;

/*
	Set up the rsv pointers
*/
double **rsvp = rsv_pointers;
for (double *pointer = rsv; pointer < rsv + max_docs; pointer++)
	*rsvp++ = pointer;

/*
	Open the postings list file
*/
FILE *postings_file = fopen("postings.bin", "rb");

/*
	Read the primary_keys
*/
char buffer[1024];													// the user's query (and also used to load the vocab)
std::vector<std::string>primary_key;							// the list of global IDs (i.e. primary keys)
FILE *fp = fopen("docids.txt", "rb");
while (fgets(buffer, sizeof(buffer), fp) != NULL)
	{
	buffer[strlen(buffer) - 1] = '\0';		// strip the '\n' that fgets leaves on the end
	primary_key.push_back(std::string(buffer));
	}

/*
	Build the vocabulary in memory
*/
std::unordered_map<std::string, vocab_entry>dictionary;	// the vocab
current = vocab;
while (current < vocab + file_size)
	{
	string_length = *current;
	where = *((size_t *)(current + string_length + 2));			// +1 for the length and + 1 for the '\0'
	size = *((size_t *)(current + string_length + 2 + sizeof(size_t)));			// +1 for the length and + 1 for the '\0'

	dictionary[std::string(current + 1)] = vocab_entry(where, size);
	current += string_length + 2 + 2 * sizeof (size_t);
	}

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
	int query_id = 0;
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
		if ((term_details = dictionary[std::string(token)]).size == 0)
			continue;

		/*
			Seek and read the postings list
		*/
		fseek(postings_file, term_details.where, SEEK_SET);
		fread(postings_buffer, 1, term_details.size, postings_file);
		size_t postings = term_details.size / (sizeof(int) * 2);
		std::pair<int, int> *list = (std::pair<int, int> *)(&postings_buffer[0]);

		/*
			Compute the IDF component of BM25 as log(N/n).
			if IDF == 0 then don't process this postings list as the BM25 contribution of this term will be zero.
		*/
		if (documents_in_collection == postings)
			break;
		double idf = log(documents_in_collection / postings);

		/*
			Process the postings list by simply adding the BM25 component for this document into the accumulators array
		*/
		for (int which = 0; which < postings; which++, list++)
			rsv[list->first] += idf * ((list->second * (k1 + 1)) / (list->second + k1 * (1 - b + b * (length_vector[list->first] / average_document_length))));
		}

	/*
		Sort the results list
	*/
	qsort(rsv_pointers, max_docs, sizeof(*rsv_pointers), compare_rsv);

	/*
		Print the results list in TREC eval format which is:
		query-id Q0 document-id rank score run-name
	*/
	for (int position = 0; *rsv_pointers[position] != 0.0; position++)
		std::cout << query_id << " Q0 " << primary_key[rsv_pointers[position] - rsv] << " " << position + 1 << " " << *rsv_pointers[position] << " JASSjr\n";
	}
}
