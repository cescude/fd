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

    var num_threads: u64 = std.Thread.cpuCount() catch 4;
    try args.flagDecl("num-threads", 'N', &num_threads, null, "Number of threads to use for scan (default is cpu-count)");

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

    try startThreads(allocator, num_threads);
    try run(cfg, outs, allocator, cwd);
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
            .Prefix => try writer.print("\u{001b}[36m{s}{s}\u{001b}[0m", .{ str, suffix }),
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

const ScanResults = struct {
    lock: std.Thread.ResetEvent,
    path: []const u8,
    paths: ArrayList([]const u8),
    files: ArrayList(Entry),
    allocator: *std.mem.Allocator,

    const Self = @This();

    pub fn init(a: *std.mem.Allocator, p: []const u8) !Self {
        var self = Self{
            .lock = undefined,
            .path = try a.dupe(u8, p),
            .paths = ArrayList([]const u8).init(a),
            .files = ArrayList(Entry).init(a),
            .allocator = a,
        };
        try self.lock.init();
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.lock.deinit();

        self.allocator.free(self.path);

        for (self.paths.items) |path| {
            self.allocator.free(path);
        }
        self.paths.deinit();

        for (self.files.items) |entry| {
            self.allocator.free(entry.name);
        }
        self.files.deinit();
    }

    pub fn wait(self: *Self) void {
        self.lock.wait();
    }

    pub fn ready(self: *Self) void {
        self.lock.set();
    }
};

const JobQueue = std.SinglyLinkedList(*ScanResults);
var job_queue = JobQueue{};
var job_queue_lock = std.Thread.Mutex{};

fn startThreads(a: *std.mem.Allocator, num_threads: u64) !void {
    var idx: u64 = 0;
    while (idx < num_threads) : (idx += 1) {
        _ = try std.Thread.spawn(thread, .{
            .id = idx,
            .allocator = a,
        });
    }
}

fn thread(ctx: struct {
    id: usize,
    allocator: *std.mem.Allocator,
}) noreturn {
    const id = ctx.id;
    // std.debug.print("Starting thread #{d}\n", .{id});
    while (true) {
        var lock = job_queue_lock.acquire();
        defer lock.release();

        if (job_queue.popFirst()) |node| {
            defer ctx.allocator.destroy(node);

            const sr: *ScanResults = node.data;
            // std.debug.print("Thread {d} scanning...{*} {s}\n", .{ id, sr, node.data.path });
            scanPath(sr) catch |err| std.debug.print("ERROR (thread={d}): {}\n", .{ id, err });
        }
    }
}

fn scanPath(sr: *ScanResults) !void {
    defer sr.ready();

    var path = sr.path;
    var paths = &sr.paths;
    var files = &sr.files;

    var dir = std.fs.openDirAbsolute(path, .{
        .iterate = true,
        .no_follow = true,
    }) catch |err| switch (err) {
        error.AccessDenied => return,
        else => return err,
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |p| {
        var qqq = [_][]const u8{ path, p.name };
        var joined = try std.fs.path.join(sr.allocator, qqq[0..]);

        switch (p.kind) {
            .Directory => try paths.append(joined),
            else => try files.append(Entry{ .kind = p.kind, .name = joined }),
        }
    }

    // Sort paths z-a (since we pluck them off back-to-front, above)
    _ = std.sort.sort([]const u8, paths.items, {}, strGt);

    // Sort files a-z (since we iterate over them normally)
    _ = std.sort.sort(Entry, files.items, {}, entryLt);
}

pub fn run(cfg: Config, _out_stream: anytype, allocator: *std.mem.Allocator, root: []const u8) !void {
    var scan_results = std.SinglyLinkedList(ScanResults){};

    var out_stream = _out_stream;
    var writer = out_stream.writer();

    defer {
        while (scan_results.popFirst()) |n| {
            n.data.deinit();
            allocator.destroy(n);
        }
    }

    {
        var node = try allocator.create(std.SinglyLinkedList(ScanResults).Node);
        errdefer allocator.destroy(node);

        node.data = try ScanResults.init(allocator, root);
        errdefer node.data.deinit();

        scan_results.prepend(node);

        var lock = job_queue_lock.acquire();
        defer lock.release();

        var job_node = try allocator.create(JobQueue.Node);
        errdefer allocator.destroy(job_node);

        job_node.data = &node.data;

        job_queue.prepend(job_node);
    }

    while (scan_results.popFirst()) |node| {
        // std.debug.print("SCAN RESULTS SIZE #{d}\n", .{scan_results.len()});
        defer {
            node.data.deinit();
            allocator.destroy(node);
        }

        const sr = &node.data;
        sr.wait();

        // std.debug.print("RUNNER: found results for {*} {s}, files={d} paths={d}\n", .{ sr, sr.path, sr.files.items.len, sr.paths.items.len });

        if (cfg.print_paths and scan_results.first != null) {
            try styled(cfg, writer, Style.Prefix, dropRoot(root, sr.path), "");
            try styled(cfg, writer, Style.Default, "", "\n");
            try out_stream.flush();
        }

        for (sr.paths.items) |path| {
            const fname = std.fs.path.basename(path);
            if (fname[0] == '.' and !cfg.include_hidden) {
                continue;
            }

            var node0 = try allocator.create(std.SinglyLinkedList(ScanResults).Node);
            errdefer allocator.destroy(node0);

            node0.data = try ScanResults.init(allocator, path);
            errdefer node0.data.deinit();

            scan_results.prepend(node0);

            // std.debug.print("!!!!11111 #{d}\n", .{scan_results.len()});

            var lock = job_queue_lock.acquire();
            defer lock.release();

            // std.debug.print("!!!!22222 #{d}\n", .{scan_results.len()});

            var job_node = try allocator.create(JobQueue.Node);
            errdefer allocator.destroy(job_node);

            job_node.data = &node0.data;

            job_queue.prepend(job_node);
            // std.debug.print("!!!!33333 #{d}\n", .{scan_results.len()});
        }

        // std.debug.print("SCAN RESULTS SIZE NOW #{d}\n", .{scan_results.len()});

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

                try out_stream.flush();
            }
        }
    }
}
