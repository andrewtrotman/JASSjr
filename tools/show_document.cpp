#include <sys/stat.h>

#include <iostream>

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

int main(int argc, const char *argv[])
	{
	size_t file_size;

	if (argc != 3)
		{
		std::cout << "Usage: " << argv[0] << " <infile.xml> <docno>" << std::endl;
		exit(1);
		}

	std::string document(read_entire_file(argv[1], file_size));
	if (file_size == 0)
		{
		std::cout << "Can't open file '" << argv[1] << "'" << std::endl;
		exit(1);
		}

	std::string needle(argv[2]);

	bool in_docno = false;
	bool found = false;
	size_t doc_start = 0;
	for (size_t i = 0; i < document.length(); i++)
		{
		if (document[i] == '<')
			{
			if (document.compare(i, 5, "<DOC>") == 0)
				doc_start = i;

			if (document.compare(i, 7, "<DOCNO>") == 0)
				in_docno = true;

			if (document.compare(i, 8, "</DOCNO>") == 0)
				in_docno = false;

			if (document.compare(i, 6, "</DOC>") == 0)
				{
				if (found)
					{
					std::cout << document.substr(doc_start, i - doc_start + 6) << std::endl;
					exit(0);
					}

				in_docno = false;
				}
			}

		if (in_docno && document.compare(i, needle.length(), needle) == 0)
			found = true;
		}

	std::cout << "Not found" << std::endl;
	exit(0);
	}
