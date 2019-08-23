/*
	INDEXER.CPP
	-----------
	Copyright (c) 2019 Andrew Trotman and Kat Lilly
	Example solution to University of Otago COSC431 Search Engine Assignment
*/
#include <ctype.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include <vector>
#include <string>
#include <utility>
#include <iostream>
#include <unordered_map>

typedef std::vector<std::pair<int, int>> postings_list;				// a postings list is an ordered pair of <docid,tf> integers
char buffer[1024 * 1024];														// index line at a time where a line fits in this buffer
std::unordered_map<std::string, postings_list> vocab;					// the in-memory index
std::vector<std::string>doc_ids;												// the primary keys
std::vector<int> length_vector;												// hold the length of each document

/*
	MAIN()
	------
	Simple indexer for TREC WSJ collection
*/
int main(int argc, const char *argv[])
{
int docid = -1;
int document_length = 0;
FILE *fp;
char seperators[255];
char *into = seperators;

/*
	Make sure we have one paramter, the filename
*/
if (argc != 2)
	exit(printf("Usage:%s <infile.xml>\n", argv[0]));
/*
	Set up the tokenizer seperator characters
*/
for (int ch = 1; ch <= 0xFF; ch++)
	if (!isalnum(ch) && ch != '<' && ch != '>' && ch != '-')
		*into++ = ch;
*into++ = '\0';

/*
	open the file to index
*/
if ((fp = fopen(argv[1], "rb")) == NULL)
	exit(printf("can't open file %s\n", argv[1]));

bool push_next = false;		// is the next token the primary key?
while (fgets(buffer, sizeof(buffer), fp) != NULL)
	{
	for (char *token = strtok(buffer, seperators); token != NULL; token = strtok(NULL, seperators))
		{
		/*
			If we see a <DOC> tag then we're at the start of the next document
		*/
		if (strcmp(token, "<DOC>") == 0)
			{
			/*
				Save the previous document length
			*/
			if (docid != -1)
				length_vector.push_back(document_length);

			/*
				Move on to the next document
			*/
			docid++;
			document_length = 0;

			if ((docid % 1000) == 0)
				std::cout << docid << " documents indexed\n";
			}

		/*
			if the last token we saw was a <DOCID> then the next token is the primary key
		*/
		if (push_next)
			{
			doc_ids.push_back(std::string(token));
			push_next = false;
			}
		if (strcmp(token, "<DOCNO>") == 0)
			push_next = true;

		/*
			break the line into tokens and index each one
		*/
		char *tok_sav = NULL;
		for (token = strtok_r(token, "<-/>", &tok_sav); token != NULL; token = strtok_r(NULL, "<-/>", &tok_sav))
			{
			/*
				lower case the string
			*/
			std::string lowercase(token);
			for (auto &ch : lowercase)
				ch = tolower(ch);

			/*
				truncate and long tokens at 255 charactes (so that the length first in a single byte)
			*/
			if (lowercase.size() >= 0xFF)
				lowercase[0xFF] = '\0';

			/*
				add the posting to the in-memory index
			*/
			postings_list &list = vocab[lowercase];
			if (list.size() == 0 || list[list.size() - 1].first != docid)
				list.push_back(std::pair<int, int>(docid, 1));							// if the docno for this occurence hasn't changed the increase tf
			else
				list[list.size() - 1].second++;												// else create a new <d,tf> pair.

			/*
				Compute the document length
			*/
//			std::cout << "[" << lowercase << "]\n";
			document_length++;
			}
		}
	}

/*
	If we didn't index any documents then we're done.
*/
if (docid == -1)
	return 0;

/*
	tell the user we've got to the end of parsing
*/
std::cout << docid << " documents indexed, serialising...\n";

/*
	Save the final document length
*/
length_vector.push_back(document_length);

/*
	store the primary keys
*/
FILE *docid_fp = fopen("docids.txt", "w+b");
for (const auto &id : doc_ids)
	fprintf(docid_fp, "%s\n", id.c_str());
fclose(docid_fp);

FILE *postings_fp = fopen("postings.bin", "w+b");
FILE *vocab_fp = fopen("vocab.txt", "w+b");

/*
	serialise the in-memory index to disk
*/
for (const auto &term : vocab)
	{
	/*
		write the postings list to one file
	*/
	size_t where = ftell(postings_fp);
	size_t size = sizeof(term.second[0]) * term.second.size();
	fwrite(&term.second[0], 1, size, postings_fp);

	/*
		write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
	*/
	char token_length = term.first.size();
	fwrite(&token_length, sizeof(token_length), 1, vocab_fp);
	fwrite(term.first.c_str(), 1, token_length + 1, vocab_fp);
	fwrite(&where, sizeof(where), 1, vocab_fp);
	fwrite(&size, sizeof(size), 1, vocab_fp);
	}

/*
	store the document lengths
*/
FILE *lengths_fp = fopen("lengths.bin", "w+b");
fwrite(&length_vector[0], sizeof(length_vector[0]), length_vector.size(), lengths_fp);

/*
	clean up
*/
fclose(docid_fp);
fclose(postings_fp);
fclose(vocab_fp);
fclose(lengths_fp);

return 0;
}
