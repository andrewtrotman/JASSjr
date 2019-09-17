all : JASSjr_index.exe JASSjr_search.exe JASSjr_index.class JASSjr_search.class

JASSjr_index.exe : JASSjr_index.cpp
	cl -Ox -EHsc JASSjr_index.cpp 

JASSjr_search.exe : JASSjr_search.cpp
	cl -Ox -EHsc JASSjr_search.cpp 

JASSjr_index.class : JASSjr_index.java
	javac JASSjr_index.java

JASSjr_search.class : JASSjr_search.java
	javac JASSjr_search.java

clean:
	- del JASSjr_search.exe JASSjr_index.exe JASSjr_search.obj JASSjr_index.obj JASSjr_search.class JASSjr_index.class "JASSjr_index$$Posting.class" "JASSjr_index$$PostingsList.class" "JASSjr_search$$CompareRsv.class" "JASSjr_search$$VocabEntry.class"

clean_index:
	- del docids.bin lengths.bin postings.bin vocab.bin

clean_all : clean clean_index

