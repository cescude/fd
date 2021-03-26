const std = @import("std");
var stdout = std.io.getStdOut().writer();

pub fn main() !void {
    var buffer: [4096]u8 = undefined;
    var cwd = try std.os.getcwd(buffer[0..]);

    var outs = std.io.bufferedWriter(stdout);
    defer outs.flush() catch {};

    var writer = outs.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());

    const allocator = switch (std.builtin.mode) {
        .ReleaseFast => std.heap.c_allocator,
        else => &gpa.allocator,
    };

    try WithWriter(@TypeOf(writer)).run(allocator, cwd, &writer);
}

const Entry = std.fs.Dir.Entry;

fn entryLt(v: void, e0: Entry, e1: Entry) bool {
    var s0 = e0.name;
    var s1 = e1.name;

    var idx: usize = 0;
    var top_idx = std.math.min(s0.len, s1.len);

    while (idx < top_idx) : (idx += 1) {
        if (s0[idx] == s1[idx]) {
            continue;
        }

        return s0[idx] < s1[idx];
    }

    return s0.len < s1.len;
}

fn WithWriter(comptime WriterType: type) type {
    return struct {
        pub fn printPath(writer: *WriterType, path: []const u8) !void {
            try writer.print("\u{001b}[1m{s}{s}\u{001b}[0m", .{ path, std.fs.path.sep_str });
            // try writer.print("{s}{s}{s}", .{ prefix, path, std.fs.path.sep_str });
        }

        pub fn run(allocator: *std.mem.Allocator, root: []u8, writer: *WriterType) !void {
            var paths = std.ArrayList([]const u8).init(allocator);
            defer {
                for (paths.items) |p| unreachable; //allocator.free(p);
                paths.deinit();
            }

            try paths.append(try allocator.dupe(u8, root));
            while (paths.items.len > 0) {
                var cur_path = paths.pop();
                defer allocator.free(cur_path);

                var dir = try std.fs.openDirAbsolute(cur_path, .{
                    .iterate = true,
                    .no_follow = true,
                });
                defer dir.close();

                if (paths.items.len > 0) {
                    const str = cur_path[root.len + 1 ..];
                    const dname = std.fs.path.dirname(str);
                    const fname = std.fs.path.basename(str);
                    if (dname) |ss| {
                        try printPath(writer, ss);
                    }
                    try writer.print("{s}\n", .{fname});
                }

                var entries = std.ArrayList(Entry).init(allocator);
                defer {
                    for (entries.items) |entry| {
                        switch (entry.kind) {
                            .Directory => paths.insert(0, entry.name) catch {},
                            else => allocator.free(entry.name),
                        }
                    }
                    entries.deinit();
                }

                var iterator = dir.iterate();
                while (try iterator.next()) |p| {
                    if (p.name[0] == '.') continue;

                    var qqq = [_][]const u8{ cur_path, p.name };
                    var joined = try std.fs.path.join(allocator, qqq[0..]);

                    try entries.append(Entry{ .kind = p.kind, .name = joined });
                }

                _ = std.sort.sort(Entry, entries.items, {}, entryLt);

                for (entries.items) |entry| {
                    const str = entry.name[root.len + 1 ..];
                    const dname = std.fs.path.dirname(str);
                    const fname = std.fs.path.basename(str);

                    if (entry.kind == Entry.Kind.Directory) {
                        continue;
                    }

                    if (dname) |ss| {
                        try printPath(writer, ss);
                    }

                    switch (entry.kind) {
                        .Directory => continue,
                        .File => {
                            try writer.print("{s}\n", .{fname});
                        },
                        .SymLink => {
                            try writer.print("{s}\n", .{fname});
                        },
                        else => {
                            try writer.print("{s} ({s})\n", .{ fname, entry.kind });
                        },
                    }
                }
            }
        }
    };
}
