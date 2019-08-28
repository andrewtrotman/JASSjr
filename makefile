all : JASSjr_index.exe JASSjr_search.exe

JASSjr_index.exe : JASSjr_index.cpp
	cl -Ox -EHsc JASSjr_index.cpp 

JASSjr_search.exe : JASSjr_search.cpp
	cl -Ox -EHsc JASSjr_search.cpp 

clean:
	del JASSjr_search.exe JASSjr_index.exe JASSjr_search.obj JASSjr_index.obj

clean_index:
	del docids.txt lengths.bin postings.bin vocab.txt

clean_all : clean clean_index
