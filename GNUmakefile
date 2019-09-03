all : JASSjr_index JASSjr_search

JASSjr_index : JASSjr_index.cpp
	g++ -std=c++11 -O3 JASSjr_index.cpp -o JASSjr_index

JASSjr_search : JASSjr_search.cpp
	g++ -std=c++11 -O3 JASSjr_search.cpp -o JASSjr_search

clean:
	rm JASSjr_search JASSjr_index

clean_index:
	rm docids.bin lengths.bin postings.bin vocab.bin

clean_all : clean clean_index
