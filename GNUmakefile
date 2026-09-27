all : cpp java crystal d_dmd d_ldc fortran hare odin rust vala zig tools

cpp : JASSjr_index JASSjr_search

java : JASSjr_index.class JASSjr_search.class

c3 : JASSjr_index_c3 JASSjr_search_c3

crystal : JASSjr_index_crystal JASSjr_search_crystal

chicken : JASSjr_index_chicken JASSjr_search_chicken

d_dmd : JASSjr_index_d_dmd JASSjr_search_d_dmd

d_ldc : JASSjr_index_d_ldc JASSjr_search_d_ldc

fortran : JASSjr_index_fortran JASSjr_search_fortran

hare : JASSjr_index_hare JASSjr_search_hare

odin : JASSjr_index_odin JASSjr_search_odin

rust : JASSjr_index_rust JASSjr_search_rust

vala : JASSjr_index_vala JASSjr_search_vala

zig : JASSjr_index_zig JASSjr_search_zig

JASSjr_index : JASSjr_index.cpp
	$(CXX) -std=c++11 -O3 -Wno-unused-result JASSjr_index.cpp -o JASSjr_index

JASSjr_search : JASSjr_search.cpp
	$(CXX) -std=c++11 -O3 -Wno-unused-result JASSjr_search.cpp -o JASSjr_search

JASSjr_index.class : JASSjr_index.java
	javac JASSjr_index.java

JASSjr_search.class : JASSjr_search.java
	javac JASSjr_search.java

JASSjr_index_c3 : JASSjr_index.c3
	c3c -O5 -o JASSjr_index_c3 compile JASSjr_index.c3

JASSjr_search_c3 : JASSjr_search.c3
	c3c -O5 -o JASSjr_search_c3 compile JASSjr_search.c3

JASSjr_index_crystal : JASSjr_index.cr
	CRYSTAL_LIBRARY_PATH=/usr/lib crystal build --release -o JASSjr_index_crystal JASSjr_index.cr

JASSjr_search_crystal : JASSjr_search.cr
	CRYSTAL_LIBRARY_PATH=/usr/lib crystal build --release -o JASSjr_search_crystal JASSjr_search.cr

JASSjr_index_chicken : JASSjr_index.scm
	csc -r7rs-syntax -O5 JASSjr_index.scm -o JASSjr_index_chicken

JASSjr_search_chicken : JASSjr_search.scm
	csc -r7rs-syntax -O5 JASSjr_search.scm -o JASSjr_search_chicken

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

JASSjr_index_hare : JASSjr_index.ha
	hare build -Ro JASSjr_index_hare JASSjr_index.ha

JASSjr_search_hare : JASSjr_search.ha
	hare build -Ro JASSjr_search_hare JASSjr_search.ha

JASSjr_index_odin : JASSjr_index.odin
	odin build JASSjr_index.odin -file -o:speed -microarch:native -no-bounds-check -out:JASSjr_index_odin

JASSjr_search_odin : JASSjr_search.odin
	odin build JASSjr_search.odin -file -o:speed -microarch:native -no-bounds-check -out:JASSjr_search_odin

JASSjr_index_rust : JASSjr_index.rs
	rustc -O -o JASSjr_index_rust JASSjr_index.rs

JASSjr_search_rust : JASSjr_search.rs
	rustc -O -o JASSjr_search_rust JASSjr_search.rs

JASSjr_index_vala : JASSjr_index.vala
	valac -X -O3 --pkg gee-0.8 --pkg gio-2.0 JASSjr_index.vala -o JASSjr_index_vala

JASSjr_search_vala : JASSjr_search.vala
	valac -X -O3 --pkg gee-0.8 --pkg gio-2.0 --pkg posix JASSjr_search.vala -o JASSjr_search_vala

JASSjr_index_zig : JASSjr_index.zig
	zig build-exe -O ReleaseFast --name JASSjr_index_zig JASSjr_index.zig

JASSjr_search_zig : JASSjr_search.zig
	zig build-exe -O ReleaseFast --name JASSjr_search_zig JASSjr_search.zig

.PHONY: tools
tools:
	make -C tools

clean:
	- rm JASSjr_index JASSjr_search
	- rm 'JASSjr_index.class' 'JASSjr_search.class' 'JASSjr_index$$Posting.class' 'JASSjr_index$$PostingsList.class' 'JASSjr_search$$CompareRsv.class' 'JASSjr_search$$VocabEntry.class'
	- rm JASSjr_index_chicken JASSjr_search_chicken
	- rm JASSjr_index_crystal JASSjr_search_crystal
	- rm JASSjr_index_d_dmd JASSjr_search_d_dmd JASSjr_index_d_ldc JASSjr_search_d_ldc
	- rm JASSjr_index_fortran JASSjr_search_fortran dynarray_integer_mod.mod dynarray_string_mod.mod lexer_mod.mod vocab_mod.mod
	- rm JASSjr_index_rust JASSjr_search_rust
	- rm JASSjr_index_zig JASSjr_search_zig
	- make -C tools clean

clean_index:
	- rm docids.bin lengths.bin postings.bin vocab.bin

clean_all : clean clean_index
