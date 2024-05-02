#!/usr/bin/env tclsh

# Copyright (c) 2024 Vaughan Kitchen
# Minimalistic BM25 search engine

# Make sure we have one parameter, the filename
if {$::argc != 1} {
	puts "Usage $::argv0 <infile.xml>"
	exit
}

set docid -1
set document_length 0
set push_next false; # is the next token the primary key?

set fh [open [lindex $::argv 0] r]
while {-1 != [gets $fh line]} {
	# A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
	# TREC <DOCNO> primary keys have a hyphen in them
	foreach token [regexp -all -inline {[a-zA-Z0-9][a-zA-Z0-9-]*|<[^>]*>} $line] {
		# If we see a <DOC> tag then we're at the start of the next document
		if {$token == "<DOC>"} {
			# Save the previous document length
			if {$docid != -1} {
				lappend doc_lengths $document_length
			}
			# Move on to the next document
			incr docid
			set document_length 0
			if {fmod($docid, 1000) == 0} {
				puts "$docid documents indexed"
			}
		}
		# If the last token we saw was a <DOCNO> then the next token is the primary key
		if $push_next {
			lappend doc_ids $token
			set push_next false
		}
		if {$token == "<DOCNO>"} {
			set push_next true
		}
		# Don't index XML tags
		if {[string index $token 0] eq "<"} continue

		# Lowercase the string
		set token [string tolower $token]

		# Truncate any long tokens at 255 characters (so that the length can be stored first and in a single byte)
		set token [string range $token 0 254]

		# Add the posting to the in-memory index
		if ![info exists vocab($token)] {
			# If the term isn't in the vocab yet
			set vocab($token) [list $docid 1]
		} else {
			if {[lindex $vocab($token) end-1] != $docid} {
				# If the docno for this occurence has changed then create a new <d,tf> pair
				lappend vocab($token) $docid 1
			} else {
				# Else increase the tf
				lset vocab($token) end [expr [lindex $vocab($token) end] + 1]
			}
		}

		# Compute the document length
		incr document_length
	}
}

# If we didn't index any documents then we're done
if {$docid == -1} exit

# Save the final document length
lappend doc_lengths $document_length

# Tell the user we've got to the end of parsing
puts "Indexed [expr $docid+1] documents. Serialising..."

# Store the primary keys
set docids_fh [open "docids.bin" w]
foreach docid $doc_ids {
	puts $docids_fh $docid
}
close $docids_fh

# Store the vocab
set postings_fh [open "postings.bin" w]
fconfigure $postings_fh -translation binary
set vocab_fh [open "vocab.bin" w]
fconfigure $vocab_fh -translation binary

foreach {term postings} [array get vocab] {
	# Write the postings list to one file
	set where [tell $postings_fh]
	puts -nonewline $postings_fh [binary format i* $postings]

	# Write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
	puts -nonewline $vocab_fh [binary format ca*xii [string length $term] $term $where [expr [llength $postings] * 4]]
}

close $postings_fh
close $vocab_fh

# Store the document lengths
set lengths_fh [open "lengths.bin" w]
fconfigure $lengths_fh -translation binary
puts -nonewline $lengths_fh [binary format i* $doc_lengths]
close $lengths_fh
