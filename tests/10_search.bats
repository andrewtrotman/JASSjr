#!/usr/bin/env bats

zero=`cat << EOF
0 Q0 0 1 2.7475 JASSjr
EOF`

one=`cat << EOF
0 Q0 10 1 2.0802 JASSjr
EOF`

two=`cat << EOF
0 Q0 9 1 1.5199 JASSjr
0 Q0 10 2 1.4789 JASSjr
EOF`

three=`cat << EOF
0 Q0 8 1 1.1915 JASSjr
0 Q0 9 2 1.1584 JASSjr
0 Q0 10 3 1.1272 JASSjr
EOF`

four=`cat << EOF
0 Q0 7 1 0.9549 JASSjr
0 Q0 8 2 0.9277 JASSjr
0 Q0 9 3 0.9019 JASSjr
0 Q0 10 4 0.8776 JASSjr
EOF`

five=`cat << EOF
0 Q0 6 1 0.7668 JASSjr
0 Q0 7 2 0.7443 JASSjr
0 Q0 8 3 0.7230 JASSjr
0 Q0 9 4 0.7030 JASSjr
0 Q0 10 5 0.6840 JASSjr
EOF`

six=`cat << EOF
0 Q0 5 1 0.6079 JASSjr
0 Q0 6 2 0.5895 JASSjr
0 Q0 7 3 0.5722 JASSjr
0 Q0 8 4 0.5558 JASSjr
0 Q0 9 5 0.5404 JASSjr
0 Q0 10 6 0.5258 JASSjr
EOF`

seven=`cat << EOF
0 Q0 4 1 0.4679 JASSjr
0 Q0 5 2 0.4533 JASSjr
0 Q0 6 3 0.4396 JASSjr
0 Q0 7 4 0.4266 JASSjr
0 Q0 8 5 0.4145 JASSjr
0 Q0 9 6 0.4030 JASSjr
0 Q0 10 7 0.3921 JASSjr
EOF`

eight=`cat << EOF
0 Q0 3 1 0.3406 JASSjr
0 Q0 4 2 0.3296 JASSjr
0 Q0 5 3 0.3194 JASSjr
0 Q0 6 4 0.3097 JASSjr
0 Q0 7 5 0.3006 JASSjr
0 Q0 8 6 0.2920 JASSjr
0 Q0 9 7 0.2839 JASSjr
0 Q0 10 8 0.2763 JASSjr
EOF`

nine=`cat << EOF
0 Q0 2 1 0.2220 JASSjr
0 Q0 3 2 0.2146 JASSjr
0 Q0 4 3 0.2077 JASSjr
0 Q0 5 4 0.2012 JASSjr
0 Q0 6 5 0.1952 JASSjr
0 Q0 7 6 0.1894 JASSjr
0 Q0 8 7 0.1840 JASSjr
0 Q0 9 8 0.1789 JASSjr
0 Q0 10 9 0.1741 JASSjr
EOF`

ten=`cat << EOF
0 Q0 1 1 0.1092 JASSjr
0 Q0 2 2 0.1054 JASSjr
0 Q0 3 3 0.1019 JASSjr
0 Q0 4 4 0.0987 JASSjr
0 Q0 5 5 0.0956 JASSjr
0 Q0 6 6 0.0927 JASSjr
0 Q0 7 7 0.0900 JASSjr
0 Q0 8 8 0.0874 JASSjr
0 Q0 9 9 0.0850 JASSjr
0 Q0 10 10 0.0827 JASSjr
EOF`

setup_file() {
	./JASSjr_index test_documents.xml
}

setup() {
	bats_load_library 'bats-support'
	bats_load_library 'bats-assert'
}

test_search_command() {
	command="$1"

	run $command <<< zero
	assert_output "$zero"

	run $command <<< one
	assert_output "$one"

	run $command <<< two
	assert_output "$two"

	run $command <<< three
	assert_output "$three"

	run $command <<< four
	assert_output "$four"

	run $command <<< five
	assert_output "$five"

	run $command <<< six
	assert_output "$six"

	run $command <<< seven
	assert_output "$seven"

	run $command <<< eight
	assert_output "$eight"

	run $command <<< nine
	assert_output "$nine"

	run $command <<< ten
	assert_output "$ten"
}

@test "CPP" {
	test_search_command ./JASSjr_search
}

@test "Crystal" {
	test_search_command ./JASSjr_search.cr
}

@test "D (dmd)" {
	test_search_command ./JASSjr_search_d_dmd
}

@test "D (ldc)" {
	test_search_command ./JASSjr_search_d_ldc
}

@test "Dart" {
	test_search_command ./JASSjr_search.dart
}

@test "Elixir" {
	test_search_command ./JASSjr_search.exs
}

@test "Fortran" {
	test_search_command ./JASSjr_search_fortran
}

@test "Go" {
	test_search_command 'go run JASSjr_search.go'
}

@test "Java" {
	test_search_command 'java JASSjr_search'
}

@test "JavaScript" {
	test_search_command ./JASSjr_search.js
}

@test "Lua" {
	test_search_command ./JASSjr_search.lua
}

@test "Nim" {
	test_search_command ./JASSjr_search.nim
}

@test "Perl" {
	test_search_command ./JASSjr_search.pl
}

@test "PHP" {
	test_search_command ./JASSjr_search.php
}

@test "Python" {
	test_search_command ./JASSjr_search.py
}

@test "Raku" {
	test_search_command ./JASSjr_search.raku
}

@test "Ruby" {
	test_search_command ./JASSjr_search.rb
}

@test "Rust" {
	test_search_command ./JASSjr_search_rust
}

@test "Tcl" {
	test_search_command ./JASSjr_search.tcl
}

@test "Zig" {
	test_search_command ./JASSjr_search_zig
}
