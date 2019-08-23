all : indexer searcher

indexer : indexer.cpp
	g++ -std=c++11 -O3 indexer.cpp -o indexer

searcher : searcher.cpp
	g++ -std=c++11 -O3 searcher.cpp -o searcher

clean:
	rm searcher indexer

clean_index:
	rm docids.txt lengths.bin postings.bin vocab.txt

clean_all : clean clean_index
