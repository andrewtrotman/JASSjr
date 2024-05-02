#!/usr/bin/env tclsh

# Copyright (c) 2024 Vaughan Kitchen
# Minimalistic BM25 search engine

set k1 0.9; # BM25 k1 parameter
set b 0.4; # BM25 b parameter

# https://wiki.tcl-lang.org/page/Summing+a+list
proc ladd {l} {::tcl::mathop::+ {*}$l}

# Read the primary_keys
set docids_fh [open "docids.bin" r]
set docids [split [read $docids_fh]]; # N.B. this has a spurious element at the end
close $docids_fh

# Read the document lengths
set lengths_fh [open "lengths.bin" r]
fconfigure $lengths_fh -translation binary
set lengths_raw [read $lengths_fh]
close $lengths_fh
binary scan $lengths_raw i* lengths

# Compute the average document length for BM25
set average_length [expr double([ladd $lengths]) / double([llength $lengths])]

# Read the vocab
set vocab_fh [open "vocab.bin" r]
fconfigure $vocab_fh -translation binary
set vocab_raw [read $vocab_fh]
close $vocab_fh

# Decode the vocabulary (unsigned byte length, string, '\0', 4 byte signed where, 4 signed byte size)
set offset 0
while 1 {
	if ![binary scan $vocab_raw @${offset}c length] break
	incr offset

	binary scan $vocab_raw @${offset}a${length} term
	incr offset [expr $length + 1]; # include null terminator

	binary scan $vocab_raw @${offset}i2 pair
	incr offset 8

	set vocab($term) $pair
}

# Open the postings list file
set postings_fh [open "postings.bin" r]
fconfigure $postings_fh -translation binary

# Search (one query per line)
while {-1 != [gets stdin query]} {
	set query_id 0
	unset -nocomplain accumulators

	set terms [split $query]

	# If the first token is a number then assume a TREC query number, and skip it
	if [string is integer [lindex $terms 0]] {
		set query_id [lindex $terms 0]
		set terms [lreplace $terms 0 0]
	}

	foreach term $terms {
		if ![info exists vocab($term)] continue
		set pair $vocab($term)
		set where [lindex $pair 0]
		set size [lindex $pair 1]

		# Seek and read the postings list
		seek $postings_fh $where
		set postings_raw [read $postings_fh $size]
		binary scan $postings_raw i* postings

		# Compute the IDF component of BM25 as log(N/n)
		set idf [expr log(double([llength $lengths]) / double($size / 8))]

		# Process the postings list by simply adding the BM25 component for this document into the accumulators array
		foreach {docid tf} $postings {
			set rsv [expr $idf * $tf * ($k1 + 1) / ($tf + $k1 * (1 - $b + $b * [lindex $lengths $docid] / $average_length))]
			if [info exists accumulators($docid)] {
				set accumulators($docid) [expr $accumulators($docid) + $rsv]
			} else {
				set accumulators($docid) $rsv
			}
		}
	}

	# Turn the accumulators back into an array to get a stable ordering
	set results [array get accumulators]

	# Sort the results list. Tie break on the document ID
	set results [lsort -stride 2 -integer -decreasing $results]
	set results [lsort -stride 2 -index 1 -real -decreasing $results]

	# Print the (at most) top 1000 documents in the results list in TREC eval format which is:
	# query-id Q0 document-id rank score run-name
	set i 1
	foreach {docid rsv} $results {
		if {$i > 1000} {
			break
		}
		puts "$query_id Q0 [lindex $docids $docid] $i [format "%.4f" $rsv] JASSjr"
		incr i
	}
}
