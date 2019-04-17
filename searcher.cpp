/*
	SEARCHER.CPP
	------------
	Copyright (c) 2019 Andrew Trotman and Kat Lilly
	Example solution to University of Otago COSC431 Search Engine Assignment
*/
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <string>
#include <vector>
#include <iostream>
#include <unordered_map>

/*
	CONSTANTS
	---------
*/
static constexpr size_t max_docs = 200000;		// there are no more than 200,000 documents in the collection

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
	GLOBALS
	-------
*/
char buffer[1024];													// the user's query (and also used to load the vocab)
int postings_buffer[(max_docs + 1) * 2];						// the postings list once loaded from disk
std::unordered_map<std::string, vocab_entry>dictionary;	// the vocab *
std::vector<std::string>primary_key;							// the list of global IDs (i.e. primary keys)
double rsv[max_docs];												// array of rsv values
double *rsv_pointers[max_docs];									// pointers to each member of rsv[] so that we can sort

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
	Callback from qsort for two rsv values
*/
int compare_rsv(const void *a, const void *b)
{
double **first = (double **)a;
double **second = (double **)b;

return **first < **second ? 1 : **first == **second ? 0 : -1;
}

/*
	MAIN()
	------
	Simple search engine ranking on sum of TF values.
*/
int main(int argc, const char * argv[])
{
size_t file_size;
char *vocab = read_entire_file("vocab.txt", file_size);
char *current;
size_t where, size, string_length;
char seperators[255];
char *into = seperators;

/*
	Set up the tokenizer seperator characters
*/
for (int ch = 1; ch <= 0xFF; ch++)
	if (!isalnum(ch) && ch != '<' && ch != '>' && ch != '-')
		*into++ = ch;
*into++ = '\0';

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
FILE *fp = fopen("docids.txt", "rb");
while (fgets(buffer, sizeof(buffer), fp) != NULL)
	{
	buffer[strlen(buffer) - 1] = '\0';		// strip the '\n' that fgets leaves on the end
	primary_key.push_back(std::string(buffer));
	}

/*
	Build the vocabulary in memory
*/
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
	memset(rsv, 0, sizeof(rsv));
	for (char *token = strtok(buffer, seperators); token != NULL; token = strtok(NULL, seperators))
		{
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
			Process the postings list by simply adding the tf into an array
		*/
		for (int which = 0; which < postings; which++, list++)
			rsv[list->first] += list->second;
		}

	/*
		Sort the results list
	*/
	qsort(rsv_pointers, max_docs, sizeof(*rsv_pointers), compare_rsv);

	/*
		Print the results list
	*/
	for (int position = 0; *rsv_pointers[position] != 0.0; position++)
		std::cout << "id: " <<  primary_key[rsv_pointers[position] - rsv] << " rsv:" << *rsv_pointers[position] << "\n";
	}
}
