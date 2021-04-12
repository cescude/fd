const std = @import("std");
const Args = @import("args.zig").Args;
var stdout = std.io.getStdOut();
const ArrayList = std.ArrayList;

const sep = std.fs.path.sep_str;

const Config = struct {
    use_color: enum { On, Off, Auto } = .Auto,
    print_files: bool = false,
    print_paths: bool = false,
    include_hidden: bool = false,
    exts: ?[]const u8 = null,

    match_pattern: ?[]const u8 = null,
    paths: [][]const u8 = undefined,
};

pub fn main() !void {
    var buffer: [4096]u8 = undefined;
    var cwd = try std.os.getcwd(buffer[0..]);

    var cfg = Config{};

    var outs = std.io.bufferedWriter(stdout.writer());
    defer outs.flush() catch {};

    var writer = outs.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());

    const allocator = switch (std.builtin.mode) {
        .ReleaseFast => std.heap.c_allocator,
        else => &gpa.allocator,
    };

    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const allocator = &arena.allocator;

    var args = Args.init(allocator);
    defer args.deinit();

    args.summary(
        \\Recursively lists files. It's much fast^H^H^H^Hslower than either fd
        \\or find (although, to be fair, it does much, much less).
    );

    try args.flagDecl("color", 'c', &cfg.use_color, null, "Enable use of color (default is Auto)");
    try args.flagDecl("files", 'f', &cfg.print_files, null, "Print files");
    try args.flagDecl("paths", 'p', &cfg.print_paths, null, "Print paths");
    try args.flagDecl("hidden", 'H', &cfg.include_hidden, null, "Include hidden files/paths");
    try args.flagDecl("exts", 'e', &cfg.exts, "E1[,E2...]",
        \\Comma-separated list of extensions. If specified, only
        \\files with the given extensions will be printed. Implies
        \\`--files`.
    );
    var show_usage: bool = false;
    try args.flagDecl("help", 'h', &show_usage, null, "Display this help message");

    try args.argDecl("[PATTERN]", &cfg.match_pattern, "Only print files whose name matches this pattern.");
    try args.extraDecl("[PATH]", &cfg.paths,
        \\List files in the provided paths (default is the current working directory)
    );

    args.parse() catch args.printUsageAndDie();

    if (cfg.match_pattern) |pat| {
        std.debug.print("PATTERN: {s}\n", .{pat});
    }

    for (cfg.paths) |pat| {
        std.debug.print("PATHS: {s}\n", .{pat});
    }

    if (show_usage) {
        args.printUsageAndDie();
    }

    // If `use_color` is .Auto, use isatty to handle the change
    if (cfg.use_color == .Auto) {
        cfg.use_color = if (std.os.isatty(stdout.handle)) .On else .Off;
    }

    // If `exts` is specified, make sure `print_files` is enabled as well!
    if (cfg.exts) |_| {
        cfg.print_files = true;
    }

    // If neither is selected, default to both :^(
    if (!cfg.print_files and !cfg.print_paths) {
        cfg.print_files = true;
        cfg.print_paths = true;
    }

    nosuspend try run(cfg, writer, allocator, cwd);
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

const ScanResults = struct {
    path: []const u8,
    paths: ArrayList([]const u8),
    files: ArrayList(Entry),
};

// Make sure the memory allocated for ScanResults is taken care of!
// => paths needs to be deinit'd, and its contents free'd
// => files needs to be deinit'd, and its contents free'd
fn scanPath(allocator: *std.mem.Allocator, path: []const u8) !ScanResults {
    var paths = ArrayList([]const u8).init(allocator);
    var files = ArrayList(Entry).init(allocator);

    var dir = std.fs.openDirAbsolute(path, .{
        .iterate = true,
        .no_follow = true,
    }) catch |err| switch (err) {
        error.AccessDenied => return ScanResults{
            .path = path,
            .paths = paths,
            .files = files,
        },
        else => return err,
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |p| {
        var qqq = [_][]const u8{ path, p.name };
        var joined = try std.fs.path.join(allocator, qqq[0..]);

        switch (p.kind) {
            .Directory => try paths.append(joined),
            else => try files.append(Entry{ .kind = p.kind, .name = joined }),
        }
    }

    // Sort paths z-a (since we pluck them off back-to-front, above)
    _ = std.sort.sort([]const u8, paths.items, {}, strGt);

    // Sort files a-z (since we iterate over them normally)
    _ = std.sort.sort(Entry, files.items, {}, entryLt);

    return ScanResults{
        .path = path,
        .paths = paths,
        .files = files,
    };
}

const Style = enum {
    Prefix,
    Default,
    SymLink,
    AccessDenied,
    Unknown,
};

pub fn styled(cfg: Config, writer: anytype, comptime style: Style, str: []const u8, comptime suffix: []const u8) !void {
    if (cfg.use_color == .On) {
        switch (style) {
            .Prefix => try writer.print("\u{001b}[1m{s}{s}\u{001b}[0m", .{ str, suffix }),
            .Default, .Unknown => try writer.print("{s}{s}", .{ str, suffix }),
            .SymLink => try writer.print("\u{001b}[31;1m\u{001b}[7m{s}\u{001b}[0m{s}", .{ str, suffix }),
            .AccessDenied => try writer.print("\u{001b}[41;1m\u{001b}[37;1m{s}\u{001b}[0m{s}", .{ str, suffix }),
        }
    } else {
        switch (style) {
            .Prefix => try writer.print("{s}{s}", .{ str, suffix }),
            else => try writer.print("{s}{s}", .{ str, suffix }),
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

const Stack = std.SinglyLinkedList(@Frame(scanPath));

pub fn run(cfg: Config, writer: anytype, allocator: *std.mem.Allocator, root: []const u8) !void {
    var scan_results = Stack{};
    defer {
        while (scan_results.popFirst()) |n| {
            allocator.destroy(n);
        }
    }

    {
        var path_dup = try allocator.dupe(u8, root);
        errdefer allocator.free(path_dup);

        var node = try allocator.create(Stack.Node);
        errdefer allocator.destroy(node);

        node.data = async scanPath(allocator, path_dup);

        scan_results.prepend(node);
    }

    while (scan_results.popFirst()) |node| {
        defer allocator.destroy(node);

        const sr = try await node.data;

        defer {
            allocator.free(sr.path);

            // The path strings themselves need to stick around to be
            // used in future ScanResults (eventually free'd by the
            // prior call).
            sr.paths.deinit();

            // Not so with the file variables...
            for (sr.files.items) |f| {
                allocator.free(f.name);
            }
            sr.files.deinit();
        }

        if (cfg.print_paths and scan_results.first != null) {
            try styled(cfg, writer, Style.Prefix, dropRoot(root, sr.path), "");
            try styled(cfg, writer, Style.Default, "", "\n");
        }

        for (sr.paths.items) |path| {
            const fname = std.fs.path.basename(path);
            if (fname[0] == '.' and !cfg.include_hidden) {
                allocator.free(path);
                continue;
            }

            errdefer allocator.free(path);

            var node0 = try allocator.create(Stack.Node);
            errdefer allocator.destroy(node0);

            node0.data = async scanPath(allocator, path);

            scan_results.prepend(node0);
        }

        if (cfg.print_files) {
            for (sr.files.items) |file| {
                if (file.name[0] == '.' and !cfg.include_hidden) continue;

                if (cfg.exts) |exts| {
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
                    try styled(cfg, writer, Style.Prefix, ss, sep);
                }

                switch (file.kind) {
                    .Directory => unreachable,
                    .File => try styled(cfg, writer, Style.Default, fname, "\n"),
                    .SymLink => try styled(cfg, writer, Style.SymLink, fname, "\n"),
                    else => try styled(cfg, writer, Style.Unknown, fname, "\n"),
                }
            }
        }
    }
}
