#!/usr/bin/env luajit

-- Copyright (c) 2024 Vaughan Kitchen
-- Minimalistic BM25 search engine.

-- Allow strings to be accessed like an array
getmetatable('').__index = function(str, i) return string.sub(str, i, i) end
-- Allow strings to be "called" to access substr
getmetatable('').__call = string.sub

-- Lua5.3 includes pack but we are targeting Lua5.1
function pack_int(num)
	return string.char(
		bit.band(num, 0xFF),
		bit.rshift(bit.band(num, 0xFF00), 8),
		bit.rshift(bit.band(num, 0xFF0000), 16),
		bit.rshift(bit.band(num, 0xFF000000), 24)
	)
end

-- Make sure we have one parameter, the filename
if #arg ~= 1 then
	print(string.format("Usage: %s <infile.xml>", arg[0]))
	os.exit()
end

local vocab = {} -- the in-memory index
local doc_ids = {} -- the primary keys
local doc_lengths = {} -- hold the length of each document

local docid = -1
local document_length = 0
local push_next = false -- is the next token the primary key?

local fh = assert(io.open(arg[1]))
for line in fh:lines() do
	-- A token is either an XML tag '<'..'>' or a sequence of alpha-numerics
	-- TREC <DOCNO> primary keys have a hyphen in them
	-- Lua patterns aren't full regex. We can't do alternation on groups
	-- As our document is fairly well formed we should be fine
	for token in string.gmatch(line, "<?/?[a-zA-Z0-9][a-zA-Z0-9-]*") do
		-- If we see a <DOC> tag then we're at the start of the next document
		if token == "<DOC" then
			-- Save the previous document length
			if docid ~= -1 then
				table.insert(doc_lengths, document_length)
			end
			-- Move on to the next document
			docid = docid + 1
			document_length = 0
			if docid % 1000 == 0 then
				print(string.format("%d documents indexed", docid))
			end
		end
		-- If the last token we saw was a <DOCNO> then the next token is the primary key
		if push_next then
			table.insert(doc_ids, token)
			push_next = false
		end
		if token == "<DOCNO" then
			push_next = true
		end
		-- Don't index XML tags
		if token[1] ~= "<" then
			-- TODO handle / at start of string
			-- Lowercase the string
			token = string.lower(token)

			-- Truncate any long tokens at 255 characters (so that the length can be stored first and in a single byte)
			token = token(1, 255)

			-- Add the posting to the in-memory index
			local postings = vocab[token] or {}
			local postings_len = #postings -- TODO make this more efficient? (is O(log(n))
			if postings_len == 0 or postings[postings_len - 1] ~= docid then
				-- If the docno for this occurence has changed then create a new <d,tf> pair
				table.insert(postings, docid)
				table.insert(postings, 1)
			else
				postings[postings_len] = postings[postings_len] + 1
			end
			vocab[token] = postings

			-- Compute the document length
			document_length = document_length + 1
		end
	end
end

-- If we didn't index any documents then we're done
if docid == -1 then
	os.exit()
end

-- Save the final document length
table.insert(doc_lengths, document_length)

-- Tell the user we've got to the end of parsing
print(string.format("Indexed %d documents. Serialising...", docid + 1))

-- Store the primary keys
local docids_fh = io.open("docids.bin", "w")
for _, docid in ipairs(doc_ids) do
	docids_fh:write(docid, "\n")
end

local postings_fh = io.open("postings.bin", "w")
local vocab_fh = io.open("vocab.bin", "w")
for term, postings in pairs(vocab) do
	-- Write the postings list to one file
	local where = postings_fh:seek()
	for _, post in ipairs(postings) do
		postings_fh:write(pack_int(post))
	end

	-- Write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
	vocab_fh:write(string.char(string.len(term)), term, "\0", pack_int(where), pack_int(#postings * 4))
end

-- Store the document lengths
local lengths_fh = io.open("lengths.bin", "w")
for _, length in ipairs(doc_lengths) do
	lengths_fh:write(pack_int(length))
end

-- Clean up
docids_fh:close()
postings_fh:close()
vocab_fh:close()
lengths_fh:close()
