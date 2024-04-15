// Copyright (c) 2024 Vaughan Kitchen
// Minimalistic BM25 search engine.

const std = @import("std");
const native_endian = @import("builtin").target.cpu.arch.endian();

// Pair definition for a value in a postings list
const Posting = struct { i32, i32 };

// One-character lookahead lexical analyser
const Lexer = struct {
    buffer: []u8,
    current: usize,

    fn init(buffer: []u8) Lexer {
        return Lexer{ .buffer = buffer, .current = 0 };
    }

    // Conform to Zig naming conventions for iterators
    fn next(self: *Lexer) ?[]u8 {
        // Skip over whitespace and punctuation (but not XML tags)
        while (self.current < self.buffer.len and !std.ascii.isAlphanumeric(self.buffer[self.current]) and self.buffer[self.current] != '<')
            self.current += 1;

        // A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
        const start = self.current;
        if (self.current >= self.buffer.len) {
            return null; // must be at end of line
        } else if (std.ascii.isAlphanumeric(self.buffer[self.current])) {
            // TREC <DOCNO> primary keys have a hyphen in them
            while (self.current < self.buffer.len and (std.ascii.isAlphanumeric(self.buffer[self.current]) or self.buffer[self.current] == '-'))
                self.current += 1;
        } else if (self.buffer[self.current] == '<') {
            self.current += 1;
            while (self.current < self.buffer.len and self.buffer[self.current - 1] != '>')
                self.current += 1;
        }

        // Return the token as a slice. This won't live past the underlying buffer
        return self.buffer[start..self.current];
    }
};

// Simple indexer for TREC WSJ collection
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const stdout = std.io.getStdOut().writer();

    const argv = try std.process.argsAlloc(arena.allocator());

    // Make sure we have one parameter, the filename
    if (argv.len != 2) {
        try stdout.print("Usage: {s} <infile.xml>\n", .{argv[0]});
        std.process.exit(0);
    }

    var vocab = std.StringHashMap(std.ArrayList(Posting)).init(arena.allocator());
    var doc_ids = std.ArrayList([]u8).init(arena.allocator());
    var lengths_vector = std.ArrayList(i32).init(arena.allocator());

    var doc_id: i32 = -1;
    var document_length: i32 = 0;

    const fh = try std.fs.cwd().openFile(argv[1], .{});
    var stream = std.io.bufferedReader(fh.reader());

    var buf: [2048]u8 = undefined;
    var push_next = false;
    while (try stream.reader().readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var lex = Lexer.init(line);
        while (lex.next()) |token| {
            if (std.mem.eql(u8, token, "<DOC>")) {
                // Save the previous document length
                if (doc_id != -1)
                    try lengths_vector.append(document_length);
                // Move on to the next document
                doc_id += 1;
                document_length = 0;
                if (@rem(doc_id, 1000) == 0)
                    try stdout.print("{d} documents indexed\n", .{doc_id});
            }
            // If the last token we saw was a <DOCNO> then the next token is the primary key
            if (push_next) {
                const primary_key = try arena.allocator().dupe(u8, token);
                try doc_ids.append(primary_key);
                push_next = false;
            }
            if (std.mem.eql(u8, token, "<DOCNO>")) {
                push_next = true;
            }
            // Don't index XML tags
            if (token[0] == '<')
                continue;

            // Lower case the string
            _ = std.ascii.lowerString(token, token);

            // Truncate any long tokens at 255 characters (so that the length can be stored first and in a single byte)
            const token2 = if (token.len < 255) token else token[0..255];

            // Add the posting to the in-memory index
            const gop = try vocab.getOrPut(token2);
            if (!gop.found_existing) {
                // If the term isn't in the vocab yet
                const term = try arena.allocator().dupe(u8, token2);
                gop.key_ptr.* = term;
                gop.value_ptr.* = std.ArrayList(Posting).init(arena.allocator());
                try gop.value_ptr.append(.{ doc_id, 1 });
            } else {
                if (gop.value_ptr.getLast()[0] != doc_id) {
                    // If the docno for this occurence has changed then create a new <d,tf> pair
                    try gop.value_ptr.append(.{ doc_id, 1 });
                } else {
                    // Else increase the tf
                    gop.value_ptr.items[gop.value_ptr.items.len - 1][1] += 1;
                }
            }

            // Compute the document length
            document_length += 1;
        }
    }

    // Save the final document length
    try lengths_vector.append(document_length);

    // Tell the user we've got to the end of parsing
    try stdout.print("Indexed {d} documents. Serialing...\n", .{doc_id + 1});

    // Store the primary keys
    const docids_fh = try std.fs.cwd().createFile("docids.bin", .{});
    var docids_stream = std.io.bufferedWriter(docids_fh.writer());

    for (doc_ids.items) |primary_key| {
        try docids_stream.writer().writeAll(primary_key);
        try docids_stream.writer().writeByte('\n');
    }

    // Serialise the in-memory index to disk
    const postings_fh = try std.fs.cwd().createFile("postings.bin", .{});
    var postings_stream = std.io.bufferedWriter(postings_fh.writer());

    const vocab_fh = try std.fs.cwd().createFile("vocab.bin", .{});
    var vocab_stream = std.io.bufferedWriter(vocab_fh.writer());

    var where: usize = 0;
    var it = vocab.iterator();
    while (it.next()) |kv| {
        // Write the postings list to one file
        try postings_stream.writer().writeAll(std.mem.sliceAsBytes(kv.value_ptr.items));

        // Write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
        try vocab_stream.writer().writeByte(@truncate(kv.key_ptr.len));
        try vocab_stream.writer().writeAll(kv.key_ptr.*);
        try vocab_stream.writer().writeByte(0);
        try vocab_stream.writer().writeInt(u32, @truncate(where), native_endian);
        try vocab_stream.writer().writeInt(u32, @truncate(kv.value_ptr.items.len * 8), native_endian);

        where += kv.value_ptr.items.len * 8;
    }

    // Store the document lengths
    const lengths_fh = try std.fs.cwd().createFile("lengths.bin", .{});
    var lengths_stream = std.io.bufferedWriter(lengths_fh.writer());
    try lengths_stream.writer().writeAll(std.mem.sliceAsBytes(lengths_vector.items));

    // Cleanup
    try lengths_stream.flush();
    lengths_fh.close();

    try vocab_stream.flush();
    vocab_fh.close();

    try postings_stream.flush();
    postings_fh.close();

    try docids_stream.flush();
    docids_fh.close();
}
