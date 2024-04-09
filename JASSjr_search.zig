// Copyright (c) 2024 Vaughan Kitchen
// Minimalistic BM25 search engine.

const std = @import("std");
const native_endian = @import("builtin").target.cpu.arch.endian();

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    // Read the document lengths
    var fh = try std.fs.cwd().openFile("lengths.bin", .{});

    const lengths_stat = try fh.stat();
    const lengths_vector = try arena.allocator().alloc(i32, lengths_stat.size / 4);
    _ = try fh.readAll(std.mem.sliceAsBytes(lengths_vector));

    fh.close();

    // Compute the average document length for BM25
    var average_document_length: f64 = 0;
    for (lengths_vector) |val| average_document_length += @floatFromInt(val);
    average_document_length /= @floatFromInt(lengths_vector.len);

    // Read the primary keys
    fh = try std.fs.cwd().openFile("docids.bin", .{});
    var stream = std.io.bufferedReader(fh.reader());

    var primary_keys = try arena.allocator().alloc([]u8, lengths_stat.size / 4);

    var docid_buf: [256]u8 = undefined;
    var i: usize = 0;
    while (try stream.reader().readUntilDelimiterOrEof(&docid_buf, '\n')) |line| {
        const docid = try arena.allocator().dupe(u8, line);
        primary_keys[i] = docid;
        i += 1;
    }

    fh.close();

    // Build the vocabulary in memory
    fh = try std.fs.cwd().openFile("vocab.bin", .{});
    stream = std.io.bufferedReader(fh.reader());

    var vocab = std.StringHashMap(struct { i32, i32 }).init(arena.allocator());

    while (true) {
        const len = stream.reader().readByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        const term = try arena.allocator().alloc(u8, len);
        _ = stream.reader().readAll(term) catch unreachable;
        _ = stream.reader().readByte() catch unreachable;

        const where = stream.reader().readInt(i32, native_endian) catch unreachable;
        const size = stream.reader().readInt(i32, native_endian) catch unreachable;

        try vocab.put(term, .{ where, size });
    }

    fh.close();

    // Open the postings list file
    var postings_fh = try std.fs.cwd().openFile("postings.bin", .{});
    defer postings_fh.close();

    var stdin = std.io.getStdIn().reader();
    var query_buf: [1024]u8 = undefined;
    while (try stdin.readUntilDelimiterOrEof(&query_buf, '\n')) |line| {
        var it = std.mem.split(u8, line, " ");
        while (it.next()) |term| {
            if (vocab.get(term)) |pair| {
                std.debug.print("{} {}\n", pair);
            }
        }
    }
}
