all : JASSjr_index JASSjr_search JASSjr_index.class JASSjr_search.class

JASSjr_index : JASSjr_index.cpp
	g++ -std=c++11 -O3 -Wno-unused-result JASSjr_index.cpp -o JASSjr_index

JASSjr_search : JASSjr_search.cpp
	g++ -std=c++11 -O3 -Wno-unused-result JASSjr_search.cpp -o JASSjr_search

JASSjr_index.class : JASSjr_index.java
	javac JASSjr_index.java

JASSjr_search.class : JASSjr_search.java
	javac JASSjr_search.java

clean:
	- rm JASSjr_search JASSjr_index JASSjr_index.class JASSjr_search.class

clean_index:
	- rm docids.bin lengths.bin postings.bin vocab.bin

clean_all : clean clean_index
