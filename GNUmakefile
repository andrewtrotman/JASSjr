default : cpp java

all : cpp java d_dmd d_ldc fortran zig

cpp : JASSjr_index JASSjr_search

java : JASSjr_index.class JASSjr_search.class

d_dmd : JASSjr_index_d_dmd JASSjr_search_d_dmd

d_ldc : JASSjr_index_d_ldc JASSjr_search_d_ldc

fortran : JASSjr_index_fortran JASSjr_search_fortran

zig : JASSjr_index_zig JASSjr_search_zig

JASSjr_index : JASSjr_index.cpp
	g++ -std=c++11 -O3 -Wno-unused-result JASSjr_index.cpp -o JASSjr_index

JASSjr_search : JASSjr_search.cpp
	g++ -std=c++11 -O3 -Wno-unused-result JASSjr_search.cpp -o JASSjr_search

JASSjr_index.class : JASSjr_index.java
	javac JASSjr_index.java

JASSjr_search.class : JASSjr_search.java
	javac JASSjr_search.java

JASSjr_index_d_dmd : JASSjr_index.d
	dmd -O -of=JASSjr_index_d_dmd JASSjr_index.d

JASSjr_search_d_dmd : JASSjr_search.d
	dmd -O -of=JASSjr_search_d_dmd JASSjr_search.d

JASSjr_index_d_ldc : JASSjr_index.d
	ldc2 -O3 --of=JASSjr_index_d_ldc JASSjr_index.d

JASSjr_search_d_ldc : JASSjr_search.d
	ldc2 -O3 --of=JASSjr_search_d_ldc JASSjr_search.d

JASSjr_index_fortran : JASSjr_index.f90
	gfortran -std=f2003 -O3 -Wall -Wextra JASSjr_index.f90 -o JASSjr_index_fortran

JASSjr_search_fortran : JASSjr_search.f90
	gfortran -std=f2003 -O3 -Wall -Wextra JASSjr_search.f90 -o JASSjr_search_fortran

JASSjr_index_zig : JASSjr_index.zig
	zig build-exe -O ReleaseFast --name JASSjr_index_zig JASSjr_index.zig

JASSjr_search_zig : JASSjr_search.zig
	zig build-exe -O ReleaseFast --name JASSjr_search_zig JASSjr_search.zig

clean:
	- rm JASSjr_index JASSjr_search
	- rm 'JASSjr_index.class' 'JASSjr_search.class' 'JASSjr_index$$Posting.class' 'JASSjr_index$$PostingsList.class' 'JASSjr_search$$CompareRsv.class' 'JASSjr_search$$VocabEntry.class'
	- rm JASSjr_index_fortran JASSjr_search_fortran
	- rm JASSjr_index_zig JASSjr_search_zig

clean_index:
	- rm docids.bin lengths.bin postings.bin vocab.bin

clean_all : clean clean_index
