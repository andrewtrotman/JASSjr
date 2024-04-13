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

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    const argv = try std.process.argsAlloc(arena.allocator());

    if (argv.len != 2) {
        std.debug.print("Usage: {s} <infile.xml>\n", .{argv[0]});
        std.process.exit(0);
    }

    var vocab = std.StringHashMap(std.ArrayList(Posting)).init(arena.allocator());
    var doc_ids = std.ArrayList([]u8).init(arena.allocator());
    var length_vector = std.ArrayList(i32).init(arena.allocator());

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
                    try length_vector.append(document_length);
                // Move on to the next document
                doc_id += 1;
                document_length = 0;
                if (@rem(doc_id, 1000) == 0)
                    std.debug.print("{d} documents indexed\n", .{doc_id});
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

            // Truncate any long tokens at 255 charactes (so that the length can be stored first and in a single byte)

            // Add the posting to the in-memory index
            const gop = try vocab.getOrPut(token);
            if (!gop.found_existing) {
                // If the term isn't in the vocab yet
                const term = try arena.allocator().dupe(u8, token);
                gop.key_ptr.* = term;
                gop.value_ptr.* = std.ArrayList(Posting).init(arena.allocator());
                try gop.value_ptr.append(.{ doc_id, 1 });
            } else {
                if (gop.value_ptr.getLast()[0] == doc_id) {
                    // If the docno for this occurence hasn't changed the increase tf
                    gop.value_ptr.items[gop.value_ptr.items.len - 1][1] += 1;
                } else {
                    // Else create a new <d,tf> pair.
                    try gop.value_ptr.append(.{ doc_id, 1 });
                }
            }

            // Compute the document length
            document_length += 1;
        }
    }

    var it = vocab.iterator();
    while (it.next()) |kv| {
        std.debug.print("{s}\n", .{kv.key_ptr.*});
        for (kv.value_ptr.items) |pair| {
            std.debug.print("  {d} {d}\n", pair);
        }
    }
}
