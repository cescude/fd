const std = @import("std");
const Args = @import("args.zig").Args;
var stdout = std.io.getStdOut();

const sep = std.fs.path.sep_str;

const Config = struct {
    use_color: bool = true,
    print_files: bool = false,
    print_paths: bool = false,
    exts: ?[]const u8 = null,
};

pub fn main() !void {
    var buffer: [4096]u8 = undefined;
    var cwd = try std.os.getcwd(buffer[0..]);

    var cfg = Config{ .use_color = std.os.isatty(stdout.handle) };

    var outs = std.io.bufferedWriter(stdout.writer());
    defer outs.flush() catch {};

    var writer = outs.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());

    const allocator = switch (std.builtin.mode) {
        .ReleaseFast => std.heap.c_allocator,
        else => &gpa.allocator,
    };

    var args = Args.init(allocator);
    defer args.deinit();

    args.summary(
        \\Recursively lists files. It's much faster than either fd or find
        \\(although, to be fair, it does much, much less).
    );

    try args.flag("color", 'c', &cfg.use_color, "Enable use of color (defaults to isatty)");
    try args.flag("files", 'f', &cfg.print_files, "Print files");
    try args.flag("paths", 'p', &cfg.print_paths, "Print paths");
    try args.option("exts", 'e', &cfg.exts, "E1[,E2...]",
        \\Comma-separated list of extensions. If specified, only
        \\files with the given extensions will be printed. Implies
        \\`--files`.
    );

    var just: ?std.fs.Dir.Entry.Kind = null;
    try args.flag("just", null, &just, "Only display files of the given type.");

    var show_usage: bool = false;
    try args.flag("help", 'h', &show_usage, "Display this help message");

    args.parse() catch args.printUsageAndDie();

    if (show_usage) {
        args.printUsageAndDie();
    }

    // If ``exts` is specified, make sure `print_files` is enabled as well!
    if (cfg.exts) |_| {
        cfg.print_files = true;
    }

    // If neither is selected, default to both :^(
    if (!cfg.print_files and !cfg.print_paths) {
        cfg.print_files = true;
        cfg.print_paths = true;
    }

    var proc = Proc(@TypeOf(writer)).init(allocator, cfg, &writer);
    try proc.run(cwd);
}

const Entry = std.fs.Dir.Entry;

fn strLt(v: void, s0: []const u8, s1: []const u8) bool {
    var idx: usize = 0;
    var top = std.math.min(s0.len, s1.len);

    while (idx < top) : (idx += 1) {
        if (s0[idx] == s1[idx]) {
            continue;
        }

        return s0[idx] < s1[idx];
    }

    return s0.len < s1.len;
}

fn strGt(v: void, s0: []const u8, s1: []const u8) bool {
    var idx: usize = 0;
    var top = std.math.min(s0.len, s1.len);

    while (idx < top) : (idx += 1) {
        if (s0[idx] == s1[idx]) {
            continue;
        }

        return s0[idx] > s1[idx];
    }

    return s0.len > s1.len;
}

fn entryLt(v: void, e0: Entry, e1: Entry) bool {
    return strLt(v, e0.name, e1.name);
}

fn entryGt(v: void, e0: Entry, e1: Entry) bool {
    return strGt(v, e0.name, e1.name);
}

// test "Sorting functions don't crash on 1024+ items" {
//     var items: [1024][]const u8 = undefined;
//     for (items) |_, idx| {
//         items[idx] = try std.fmt.allocPrint(std.testing.allocator, "{d}", .{idx});
//     }
//     defer for (items) |i| {
//         std.testing.allocator.free(i);
//     };

//     // Had a bad implementation of strGt (`sort` crashes if gte instead of gt),
//     // make sure that doesn't slip up again.

//     _ = std.sort.sort([]const u8, items[0..], {}, strLt);
//     _ = std.sort.sort([]const u8, items[0..], {}, strGt);
// }

// test "Sorting panics on >1023 items" {
//     var items: [1024]usize = undefined;
//     for (items) |_, idx| {
//         items[idx] = idx;
//     }

//     const impl = struct {
//         fn lt(_: void, a: usize, b: usize) bool {
//             return a < b;
//         }
//         fn lte(_: void, a: usize, b: usize) bool {
//             return a <= b;
//         }
//     };

//     _ = std.sort.sort(usize, items[0..1023], {}, impl.lt); // ok
//     _ = std.sort.sort(usize, items[0..1023], {}, impl.lte); // ok

//     _ = std.sort.sort(usize, items[0..], {}, impl.lt); // ok
//     _ = std.sort.sort(usize, items[0..], {}, impl.lte); // panic!
// }

fn Proc(comptime WriterType: type) type {
    return struct {
        allocator: *std.mem.Allocator,
        cfg: Config,
        writer: *WriterType,

        const Self = @This();

        pub fn init(allocator: *std.mem.Allocator, cfg: Config, writer: *WriterType) Self {
            return .{
                .allocator = allocator,
                .cfg = cfg,
                .writer = writer,
            };
        }

        const Style = enum {
            Prefix,
            Default,
            SymLink,
            AccessDenied,
            Unknown,
        };

        pub fn styled(self: *Self, comptime style: Style, str: []const u8, comptime suffix: []const u8) !void {
            if (self.cfg.use_color) {
                switch (style) {
                    .Prefix => try self.writer.print("\u{001b}[1m{s}{s}\u{001b}[0m", .{ str, suffix }),
                    .Default, .Unknown => try self.writer.print("{s}{s}", .{ str, suffix }),
                    .SymLink => try self.writer.print("\u{001b}[31;1m\u{001b}[7m{s}\u{001b}[0m{s}", .{ str, suffix }),
                    .AccessDenied => try self.writer.print("\u{001b}[41;1m\u{001b}[37;1m{s}\u{001b}[0m{s}", .{ str, suffix }),
                }
            } else {
                switch (style) {
                    .Prefix => try self.writer.print("{s}{s}", .{ str, suffix }),
                    else => try self.writer.print("{s}{s}", .{ str, suffix }),
                }
            }
        }

        // Strip the `root` prefix from `path`
        pub fn dropRoot(root: []const u8, path: []const u8) []const u8 {
            // Let's assume sep is always a single character...
            if (root[root.len - 1] == sep[0]) {
                return path[root.len..];
            } else {
                return path[root.len + 1 ..];
            }
        }

        pub fn run(self: *Self, root: []const u8) !void {
            var paths = std.ArrayList([]const u8).init(self.allocator);
            defer {
                for (paths.items) |p| self.allocator.free(p);
                paths.deinit();
            }

            try paths.append(try self.allocator.dupe(u8, root));
            while (paths.items.len > 0) {
                var cur_path = paths.pop();
                defer self.allocator.free(cur_path);

                var dir = std.fs.openDirAbsolute(cur_path, .{
                    .iterate = true,
                    .no_follow = true,
                }) catch |err| {
                    switch (err) {
                        error.AccessDenied => {
                            // try self.styled(Style.AccessDenied, dropRoot(root, cur_path), "\n");
                            continue;
                        },
                        else => return err,
                    }
                };
                defer dir.close();

                if (paths.items.len > 0 and self.cfg.print_paths) {
                    try self.styled(Style.Prefix, dropRoot(root, cur_path), "\n");
                }

                var files_found = std.ArrayList(Entry).init(self.allocator);
                defer {
                    for (files_found.items) |file| {
                        switch (file.kind) {
                            .Directory => unreachable, //paths.append(entry.name) catch {},
                            else => self.allocator.free(file.name),
                        }
                    }
                    files_found.deinit();
                }

                // Store the size of the paths list; we're going to (reverse)
                // sort any added paths found in the current directory & want to
                // only affect those that were newly added...
                const paths_size = paths.items.len;

                var iterator = dir.iterate();
                while (try iterator.next()) |p| {
                    if (p.name[0] == '.') continue;

                    var qqq = [_][]const u8{ cur_path, p.name };
                    var joined = try std.fs.path.join(self.allocator, qqq[0..]);

                    switch (p.kind) {
                        .Directory => try paths.append(joined),
                        else => try files_found.append(Entry{ .kind = p.kind, .name = joined }),
                    }
                }

                // Sort paths z-a (since we pluck them off back-to-front, above)
                _ = std.sort.sort([]const u8, paths.items[paths_size..], {}, strGt);

                // Sort files a-z (since we iterate over them normally, below)
                _ = std.sort.sort(Entry, files_found.items, {}, entryLt);

                if (self.cfg.print_files) {
                    for (files_found.items) |file| {
                        if (self.cfg.exts) |exts| {
                            const file_ext = std.fs.path.extension(file.name);
                            if (file_ext.len == 0) {
                                // No extension? Definitely not going to match anything...
                                continue;
                            }

                            var ext_match = false;

                            var it = std.mem.tokenize(exts, ",");
                            while (it.next()) |ext| {
                                // file_ext is always preceded by a `.` here
                                ext_match = ext_match or std.mem.eql(u8, ext, file_ext[1..]);
                            }

                            if (!ext_match) {
                                // None of the extensions matched, move to the next file
                                continue;
                            }
                        }

                        const str = dropRoot(root, file.name);
                        const dname = std.fs.path.dirname(str);
                        const fname = std.fs.path.basename(str);

                        if (dname) |ss| {
                            try self.styled(Style.Prefix, ss, sep);
                        }

                        switch (file.kind) {
                            .Directory => unreachable,
                            .File => {
                                try self.styled(Style.Default, fname, "\n");
                            },
                            .SymLink => {
                                try self.styled(Style.SymLink, fname, "\n");
                            },
                            else => {
                                try self.styled(Style.Unknown, fname, "\n");
                            },
                        }
                    }
                }
            }
        }
    };
}
