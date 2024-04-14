// Copyright (c) 2024 Vaughan Kitchen
// Minimalistic BM25 search engine.

const std = @import("std");
const native_endian = @import("builtin").target.cpu.arch.endian();

const k1 = 0.9; // BM25 k1 parameter
const b = 0.4; // BM25 b parameter

fn compare_rsv(rsv: []f64, first: usize, second: usize) bool {
    return if (rsv[first] == rsv[second]) first > second else rsv[first] > rsv[second];
}

// The Zig standard library as of 0.12.0-dev.3639+9cfac4718 doesn't randomise the hash seed
// Due to the hash table implementation writing out and reading back with the same seed value is incredibly slow
// Here we provide a custom hash table context so that we can hash to different values
const StringContext = struct {
    pub fn hash(self: @This(), str: []const u8) u64 {
        _ = self;
        return std.hash.Wyhash.hash(42, str);
    }
    pub fn eql(self: @This(), first: []const u8, second: []const u8) bool {
        _ = self;
        return std.mem.eql(u8, first, second);
    }
};

// Simple search engine ranking on BM25.
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const stdout_raw = std.io.getStdOut().writer();
    var stdout_stream = std.io.bufferedWriter(stdout_raw);
    const stdout = stdout_stream.writer();

    // Read the document lengths
    var fh = try std.fs.cwd().openFile("lengths.bin", .{});

    const lengths_stat = try fh.stat();
    const documents_in_collection = lengths_stat.size / 4;
    const lengths_vector = try arena.allocator().alloc(u32, documents_in_collection);
    _ = try fh.readAll(std.mem.sliceAsBytes(lengths_vector));

    fh.close();

    // Compute the average document length for BM25
    var average_document_length: f64 = 0;
    for (lengths_vector) |val| average_document_length += @floatFromInt(val);
    average_document_length /= @floatFromInt(lengths_vector.len);

    // Read the primary keys
    fh = try std.fs.cwd().openFile("docids.bin", .{});
    var stream = std.io.bufferedReader(fh.reader());

    var primary_keys = try arena.allocator().alloc([]u8, documents_in_collection);

    var docid_buf: [256]u8 = undefined;
    var key_index: usize = 0;
    while (try stream.reader().readUntilDelimiterOrEof(&docid_buf, '\n')) |line| {
        const docid = try arena.allocator().dupe(u8, line);
        primary_keys[key_index] = docid;
        key_index += 1;
    }

    fh.close();

    // Build the vocabulary in memory
    fh = try std.fs.cwd().openFile("vocab.bin", .{});
    stream = std.io.bufferedReader(fh.reader());

    var vocab = std.HashMap([]const u8, struct { u32, u32 }, StringContext, std.hash_map.default_max_load_percentage).init(arena.allocator());

    while (true) {
        const len = stream.reader().readByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        const term = try arena.allocator().alloc(u8, len);
        _ = stream.reader().readAll(term) catch unreachable;
        _ = stream.reader().readByte() catch unreachable;

        const where = stream.reader().readInt(u32, native_endian) catch unreachable;
        const size = stream.reader().readInt(u32, native_endian) catch unreachable;

        try vocab.put(term, .{ where, size });
    }

    fh.close();

    // Open the postings list file
    const postings = try arena.allocator().alloc(struct { u32, u32 }, documents_in_collection * 2);
    const postings_fh = try std.fs.cwd().openFile("postings.bin", .{});
    defer postings_fh.close();

    // Allocate buffers
    var rsv = try arena.allocator().alloc(f64, documents_in_collection);

    // Set up the rsv pointers
    var rsv_pointers = try arena.allocator().alloc(usize, documents_in_collection);
    for (0..documents_in_collection) |i| {
        rsv_pointers[i] = i;
    }

    // Search (one query per line)
    var stdin = std.io.getStdIn().reader();
    var query_buf: [1024]u8 = undefined;
    while (try stdin.readUntilDelimiterOrEof(&query_buf, '\n')) |line| {
        // Zero the accumulator array
        for (0..documents_in_collection) |i| {
            rsv[i] = 0;
        }

        var it = std.mem.splitAny(u8, line, " \r\n");

        // If the first token is a number then assume a TREC query number, and skip it
        const query_id = std.fmt.parseInt(isize, it.peek().?, 10) catch 0;
        if (query_id != 0) _ = it.next();

        while (it.next()) |term| {
            if (term.len == 0) continue;
            // Does the term exist in the collection?
            if (vocab.get(term)) |pair| {
                // Seek and read the postings list
                try postings_fh.seekTo(pair[0]);
                _ = try fh.readAll(std.mem.sliceAsBytes(postings)[0..pair[1]]);

                // Compute the IDF component of BM25 as log(N/n)
                const idf = @log(@as(f64, @floatFromInt(documents_in_collection)) / @as(f64, @floatFromInt(pair[1] / 8)));

                // Process the postings list by simply adding the BM25 component for this document into the accumulators array
                for (postings, 0..) |p, i| {
                    if (i == pair[1] / 8) break;
                    const docid = p[0];
                    const tf: f64 = @floatFromInt(p[1]);
                    rsv[docid] += idf * tf * (k1 + 1) / (tf + k1 * (1 - b + b * (@as(f64, @floatFromInt(lengths_vector[docid])) / average_document_length)));
                }
            }
        }

        // Sort the results list
        std.sort.pdq(usize, rsv_pointers, rsv, compare_rsv);

        // Print the (at most) top 1000 documents in the results list in TREC eval format which is:
        // query-id Q0 document-id rank score run-name
        for (rsv_pointers, 0..) |r, i| {
            if (rsv[r] == 0 or i == 1000) break;
            try stdout.print("{d} Q0 {s} {d} {d:.4} JASSjr\n", .{ query_id, primary_keys[r], i + 1, rsv[r] });
        }
        try stdout_stream.flush();
    }
}
