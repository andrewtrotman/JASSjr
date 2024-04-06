/*
	JASSJR_INDEX.CPP
	----------------
	Copyright (c) 2019 Andrew Trotman and Kat Lilly
	Minimalistic BM25 search engine.
*/
#include <ctype.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>

#include <vector>
#include <string>
#include <utility>
#include <iostream>
#include <unordered_map>

typedef std::vector<std::pair<int32_t, int32_t>> postings_list;	// a postings list is an ordered pair of <docid,tf> integers
char buffer[1024 * 1024];					// index line at a time where a line fits in this buffer
char *current;							// where the lexical analyser is in buffer[]
char next_token[1024 * 1024];					// the token we're currently building
std::unordered_map<std::string, postings_list> vocab;		// the in-memory index
std::vector<std::string>doc_ids;				// the primary keys
std::vector<int32_t> length_vector;				// hold the length of each document

/*
	LEX_GET_NEXT()
	--------------
	One-character lookahead lexical analyser
*/
char *lex_get_next()
	{
	/*
		Skip over whitespace and punctuation (but not XML tags)
	*/
	while (*current != '\0' && !isalnum(*current) && *current != '<')
		current++;

	/*
		A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
	*/
	char *start = current;
	if (isalnum(*current))
		while (isalnum(*current) || *current == '-')	// TREC <DOCNO> primary keys have a hyphen in them
			current++;
	else if (*current == '<')
		{
		current++;
		while (*(current - 1) != '>')
			current++;
		}
	else
		return NULL;	// must be at end of line

	/*
		Copy and return the token
	*/
	memcpy(next_token, start, current - start);
	next_token[current - start] = '\0';

	return next_token;
	}

/*
	LEX_GET_FIRST()
	---------------
	Start the lexical analysis process
*/
char *lex_get_first(char *with)
	{
	current = with;

	return lex_get_next();
	}

/*
	MAIN()
	------
	Simple indexer for TREC WSJ collection
*/
int main(int argc, const char *argv[])
	{
	int32_t docid = -1;
	int32_t document_length = 0;
	FILE *fp;

	/*
		Make sure we have one paramter, the filename
	*/
	if (argc != 2)
		exit(printf("Usage:%s <infile.xml>\n", argv[0]));

	/*
		open the file to index
	*/
	if ((fp = fopen(argv[1], "rb")) == NULL)
		exit(printf("can't open file %s\n", argv[1]));

	bool push_next = false;		// is the next token the primary key?
	while (fgets(buffer, sizeof(buffer), fp) != NULL)
		{
		for (char *token = lex_get_first(buffer); token != NULL; token = lex_get_next())
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
				if the last token we saw was a <DOCNO> then the next token is the primary key
			*/
			if (push_next)
				{
				doc_ids.push_back(std::string(token));
				push_next = false;
				}
			if (strcmp(token, "<DOCNO>") == 0)
				push_next = true;

			/*
				Don't index XML tags
			*/
			if (*token == '<')
				continue;

			/*
				lower case the string
			*/
			std::string lowercase(token);
			for (auto &ch : lowercase)
				ch = tolower(ch);

			/*
				truncate any long tokens at 255 charactes (so that the length can be stored first and in a single byte)
			*/
			if (lowercase.size() >= 0xFF)
				lowercase[0xFF] = '\0';

			/*
				add the posting to the in-memory index
			*/
			postings_list &list = vocab[lowercase];
			if (list.size() == 0 || list[list.size() - 1].first != docid)
				list.push_back(std::pair<int32_t, int32_t>(docid, 1));	// if the docno for this occurence hasn't changed the increase tf
			else
				list[list.size() - 1].second++;				// else create a new <d,tf> pair.

			/*
				Compute the document length
			*/
			document_length++;
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
	std::cout << "Indexed " << docid + 1 << " documents. Serialising...\n";

	/*
		Save the final document length
	*/
	length_vector.push_back(document_length);

	/*
		store the primary keys
	*/
	FILE *docid_fp = fopen("docids.bin", "w+b");
	for (const auto &id : doc_ids)
		fprintf(docid_fp, "%s\n", id.c_str());

	FILE *postings_fp = fopen("postings.bin", "w+b");
	FILE *vocab_fp = fopen("vocab.bin", "w+b");

	/*
		serialise the in-memory index to disk
	*/
	for (const auto &term : vocab)
		{
		/*
			write the postings list to one file
		*/
		int32_t where = ftell(postings_fp);
		int32_t size = sizeof(term.second[0]) * term.second.size();
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
