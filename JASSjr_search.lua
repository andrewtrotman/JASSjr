#!/usr/bin/env luajit

-- Copyright (c) 2024 Vaughan Kitchen
-- Minimalistic BM25 search engine.

-- Allow strings to be accessed like an array
getmetatable('').__index = function(str, i) return string.sub(str, i, i) end
-- Allow strings to be "called" to access substr
getmetatable('').__call = string.sub

-- Lua5.3 includes unpack but we are targeting Lua5.1
function unpack_int(str)
	return bit.bor(
		string.byte(str[1]),
		bit.lshift(string.byte(str[2]), 8),
		bit.lshift(string.byte(str[3]), 16),
		bit.lshift(string.byte(str[4]), 24)
	)
end

local k1 = 0.9 -- BM25 k1 parameter
local b = 0.4 -- BM25 b parameter

local documents_in_collection = 0

-- Read the primary keys
local doc_ids = {}
local doc_ids_fh = assert(io.open("docids.bin"), "r")
for line in doc_ids_fh:lines() do
	table.insert(doc_ids, line)
	documents_in_collection = documents_in_collection + 1
end

-- Read the document lengths
local doc_lengths = {}
local doc_lengths_fh = assert(io.open("lengths.bin"), "rb")
local doc_lengths_raw = doc_lengths_fh:read("*all")

local offset = 1
while offset < string.len(doc_lengths_raw) do
	table.insert(doc_lengths, unpack_int(doc_lengths_raw(offset, offset + 3)))
	offset = offset + 4
end

-- Compute the average document length for BM25
local average_length = 0
local count = 0
for _, length in ipairs(doc_lengths) do
	average_length = average_length + length
	count = count + 1
end
average_length = average_length / count

-- Decode the vocabulary (unsigned byte length, string, '\0', 4 byte signed where, 4 signed byte size)
local vocab = {}
local vocab_fh = assert(io.open("vocab.bin"), "rb")
local vocab_raw = vocab_fh:read("*all")

local offset = 1
while offset < string.len(vocab_raw) do
	length = string.byte(vocab_raw[offset])
	offset = offset + 1

	term = vocab_raw(offset, offset + length - 1)
	offset = offset + length + 1

	where = unpack_int(vocab_raw(offset, offset + 3))
	offset = offset + 4
	size = unpack_int(vocab_raw(offset, offset + 3))
	offset = offset + 4

	vocab[term] = {where, size}
end

-- Open the postings list file
local postings_fh = assert(io.open("postings.bin"), "rb")

-- Search (one query per line)
while true do
	local query = io.read()
	if query == nil then
		break
	end

	local accumulators = {}

	local query_id = nil
	local allow_search = false

	for term in string.gmatch(query, "%S+") do
		-- If the first token is a number then assume a TREC query number, and skip it
		if not allow_search then
			query_id = tonumber(term)
			if query_id == nil then
				query_id = 0
				allow_search = true
			end
		end

		if allow_search then
			local pair = vocab[term]
			-- Does the term exist in the collection?
			if pair then
				local offset = pair[1]
				local size = pair[2]

				-- Seek and read the postings list
				local postings = {}

				postings_fh:seek("set", offset)
				local postings_raw = postings_fh:read(size)

				local offset = 1
				while offset < size do
					table.insert(postings, unpack_int(postings_raw(offset, offset + 3)))
					offset = offset + 4
				end

				-- Compute the IDF component of BM25 as log(N/n)
				local idf = math.log(documents_in_collection / (size / 8))

				-- Process the postings list by simply adding the BM25 component for this document into the accumulators array
				local offset = 1
				while offset < size / 4 do
					local docid = postings[offset]
					local tf = postings[offset+1]

					local rsv = idf * tf * (k1 + 1) / (tf + k1 * (1 - b + b * (doc_lengths[docid+1] / average_length)))

					local current_rsv = accumulators[docid] or 0
					accumulators[docid] = current_rsv + rsv

					offset = offset + 2
				end
			end
		end

		allow_search = true
	end

	-- Turn the accumulators back into an array to get a stable ordering
	local results = {}
	for docid, rsv in pairs(accumulators) do
		table.insert(results, {rsv, docid})
	end

	-- Sort the results list. Tie break on the document ID
	table.sort(results, function(a, b) return a[1] == b[1] and a[2] > b[2] or a[1] > b[1] end)

	-- Print the (at most) top 1000 documents in the results list in TREC eval format which is:
	-- query-id Q0 document-id rank score run-name
	for i, pair in ipairs(results) do
		if i > 1000 then
			break
		end
		local rsv = pair[1]
		local docid = pair[2]
		print(string.format("%d Q0 %s %d %.4f JASSjr", query_id, doc_ids[docid+1], i, rsv))
	end
end
