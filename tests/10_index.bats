#!/usr/bin/env bats

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

setup() {
	bats_load_library 'bats-support'
	bats_load_library 'bats-assert'
}

test_index_command() {
	command="$1"

	$command test_documents.xml

	run ./JASSjr_search <<< ten
	assert_output "$ten"
}

@test "CPP" {
	test_index_command ./JASSjr_index
}

@test "D (dmd)" {
	test_index_command ./JASSjr_index_d_dmd
}

@test "D (ldc)" {
	test_index_command ./JASSjr_index_d_ldc
}

@test "Elixir" {
	test_index_command ./JASSjr_index.exs
}

@test "Fortran" {
	test_index_command ./JASSjr_index_fortran
}

@test "Go" {
	test_index_command 'go run JASSjr_index.go'
}

@test "Java" {
	test_index_command 'java JASSjr_index'
}

@test "JavaScript" {
	test_index_command ./JASSjr_index.js
}

@test "Nim" {
	test_index_command ./JASSjr_index.nim
}

@test "Perl" {
	test_index_command ./JASSjr_index.pl
}

@test "Python" {
	test_index_command ./JASSjr_index.py
}

@test "Raku" {
	test_index_command ./JASSjr_index.raku
}

@test "Ruby" {
	test_index_command ./JASSjr_index.rb
}

@test "Zig" {
	test_index_command ./JASSjr_index_zig
}
