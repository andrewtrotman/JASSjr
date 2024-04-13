default : cpp java

all : cpp java zig

cpp : JASSjr_index JASSjr_search

java : JASSjr_index.class JASSjr_search.class

zig : JASSjr_index_zig JASSjr_search_zig

JASSjr_index : JASSjr_index.cpp
	g++ -std=c++11 -O3 -Wno-unused-result JASSjr_index.cpp -o JASSjr_index

JASSjr_search : JASSjr_search.cpp
	g++ -std=c++11 -O3 -Wno-unused-result JASSjr_search.cpp -o JASSjr_search

JASSjr_index.class : JASSjr_index.java
	javac JASSjr_index.java

JASSjr_search.class : JASSjr_search.java
	javac JASSjr_search.java

JASSjr_index_zig : JASSjr_index.zig
	zig build-exe -O ReleaseFast --name JASSjr_index_zig JASSjr_index.zig

JASSjr_search_zig : JASSjr_search.zig
	zig build-exe -O ReleaseFast --name JASSjr_search_zig JASSjr_search.zig

clean:
	- rm JASSjr_index JASSjr_search
	- rm 'JASSjr_index.class' 'JASSjr_search.class' 'JASSjr_index$$Posting.class' 'JASSjr_index$$PostingsList.class' 'JASSjr_search$$CompareRsv.class' 'JASSjr_search$$VocabEntry.class'
	- rm JASSjr_index_zig JASSjr_search_zig

clean_index:
	- rm docids.bin lengths.bin postings.bin vocab.bin

clean_all : clean clean_index
