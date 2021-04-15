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
    no_sort: bool = false,

    match_pattern: ?[]const u8 = null,
    paths: [][]const u8 = undefined,
};

const LSColors = @import("ls_colors.zig");

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
    try args.flagDecl("no-sort", 'n', &cfg.no_sort, null, "Don't bother sorting the results");
    try args.flagDecl("exts", 'e', &cfg.exts, "E1[,E2...]",
        \\Comma-separated list of extensions. If specified, only
        \\files with the given extensions will be printed. Implies
        \\`--files`.
    );

    var num_threads: u64 = 3;
    try args.flagDecl("num-threads", null, &num_threads, null, "Number of threads to use (default is 3)");

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

    var ls_colors = LSColors.init(allocator);
    defer ls_colors.deinit();

    try ls_colors.parse("rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=01;05;37;41:mi=01;05;37;41:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arc=01;31:*.arj=01;31:*.taz=01;31:*.lha=01;31:*.lz4=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.tzo=01;31:*.t7z=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.dz=01;31:*.gz=01;31:*.lrz=01;31:*.lz=01;31:*.lzo=01;31:*.xz=01;31:*.bz2=01;31:*.bz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.war=01;31:*.ear=01;31:*.sar=01;31:*.rar=01;31:*.alz=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:*.cab=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.webm=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.axv=01;35:*.anx=01;35:*.ogv=01;35:*.ogx=01;35:*.pdf=00;32:*.ps=00;32:*.txt=00;32:*.patch=00;32:*.diff=00;32:*.log=00;32:*.tex=00;32:*.doc=00;32:*.aac=00;36:*.au=00;36:*.flac=00;36:*.m4a=00;36:*.mid=00;36:*.midi=00;36:*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:*.axa=00;36:*.oga=00;36:*.spx=00;36:*.xspf=00;36");

    try startThreads(cfg, allocator, num_threads - 1);
    try run(cfg, outs, ls_colors, allocator, cwd);
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

fn styleFor(ls_colors: LSColors, kind: Entry.Kind, extension: ?[]const u8) ?[]const u8 {
    // TODO: Handle executable types?
    return switch (kind) {
        .BlockDevice => ls_colors.bd,
        .CharacterDevice => ls_colors.cd,
        .Directory => ls_colors.di,
        .NamedPipe => ls_colors.pi,
        .SymLink => ls_colors.ln,
        .File => if (extension) |ext| ls_colors.extensions.get(ext) orelse ls_colors.fi else ls_colors.fi,
        .UnixDomainSocket => ls_colors.so,
        .Whiteout => null,
        .Unknown => ls_colors.fi,
    };
}

fn styled(writer: anytype, _style: ?[]const u8, str: []const u8, comptime suffix: []const u8) !void {
    if (_style) |style| {
        try writer.print("\u{001b}[{s}m{s}{s}\u{001b}[0m", .{ style, str, suffix });
    } else {
        try writer.print("{s}{s}", .{ str, suffix });
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

fn startThreads(cfg: Config, a: *std.mem.Allocator, num_threads: u64) !void {
    var idx: u64 = 0;
    while (idx < num_threads) : (idx += 1) {
        _ = try std.Thread.spawn(thread, .{
            .cfg = cfg,
            .id = idx,
            .allocator = a,
        });
    }
}

fn thread(ctx: struct {
    cfg: Config,
    id: usize,
    allocator: *std.mem.Allocator,
}) noreturn {
    const cfg = ctx.cfg;
    const id = ctx.id;

    while (true) {
        var lock = job_queue_lock.acquire();
        var maybe_node = job_queue.popFirst();
        lock.release();

        if (maybe_node) |node| {
            defer ctx.allocator.destroy(node);

            const sr: *ScanResults = node.data;
            scanPath(cfg, sr) catch |err| std.debug.print("ERROR (thread={d}): {}\n", .{ id, err });
        }
    }
}

fn scanPath(cfg: Config, sr: *ScanResults) !void {
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

    var whitelisted_extensions_iterator: ?std.mem.TokenIterator = if (cfg.exts) |exts| std.mem.tokenize(exts, ",") else null;

    var iter = dir.iterate();
    while (try iter.next()) |p| {

        // First check if this is a hidden file
        if (p.name[0] == '.' and !cfg.include_hidden) {
            continue;
        }

        // Next see if we have extensions we're trying to match
        if (p.kind != .Directory) {
            if (whitelisted_extensions_iterator) |*exts_it| {
                defer exts_it.reset();

                const file_ext = std.fs.path.extension(p.name);
                if (file_ext.len == 0) {
                    // No extension? Definitely not going to match anything...
                    continue;
                }

                while (exts_it.next()) |ext| {
                    // file_ext is always preceded by a `.` here
                    if (std.mem.eql(u8, ext, file_ext[1..])) {
                        break; // Found a matching extension
                    }
                } else {
                    // No extensions matched, go to the next file
                    continue;
                }
            }
        }

        var qqq = [_][]const u8{ path, p.name };
        var joined = try std.fs.path.join(sr.allocator, qqq[0..]);

        switch (p.kind) {
            .Directory => try paths.append(joined),
            else => try files.append(Entry{ .kind = p.kind, .name = joined }),
        }
    }

    if (cfg.no_sort) return;

    // Sort paths z-a (since we pluck them off back-to-front, above)
    _ = std.sort.sort([]const u8, paths.items, {}, strGt);

    // Sort files a-z (since we iterate over them normally)
    _ = std.sort.sort(Entry, files.items, {}, entryLt);
}

pub fn run(cfg: Config, _out_stream: anytype, ls_colors: LSColors, allocator: *std.mem.Allocator, root: []const u8) !void {
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

        var job_node = try allocator.create(JobQueue.Node);
        errdefer allocator.destroy(job_node);

        job_node.data = &node.data;

        var lock = job_queue_lock.acquire();
        job_queue.prepend(job_node);
        lock.release();
    }

    while (scan_results.popFirst()) |node| {
        defer {
            node.data.deinit();
            allocator.destroy(node);
        }

        const sr = &node.data;
        sr.wait();

        var needs_flush = false;

        if (cfg.print_paths and scan_results.first != null) {
            try styled(writer, styleFor(ls_colors, .Directory, null), dropRoot(root, sr.path), "");
            try writer.print("\n", .{});
            needs_flush = true;
        }

        for (sr.paths.items) |path| {
            var node0 = try allocator.create(std.SinglyLinkedList(ScanResults).Node);
            errdefer allocator.destroy(node0);

            node0.data = try ScanResults.init(allocator, path);
            errdefer node0.data.deinit();

            scan_results.prepend(node0);

            var job_node = try allocator.create(JobQueue.Node);
            errdefer allocator.destroy(job_node);

            job_node.data = &node0.data;

            var lock = job_queue_lock.acquire();
            job_queue.prepend(job_node);
            lock.release();
        }

        if (cfg.print_files) {
            for (sr.files.items) |file| {
                const str = dropRoot(root, file.name);
                const dname = std.fs.path.dirname(str);
                const fname = std.fs.path.basename(str);
                const ename = std.fs.path.extension(str);

                if (dname) |ss| {
                    try styled(writer, styleFor(ls_colors, .Directory, null), ss, sep);
                }

                if (ename.len > 1) {
                    try styled(writer, styleFor(ls_colors, file.kind, ename[1..]), fname, "\n");
                } else {
                    try styled(writer, styleFor(ls_colors, file.kind, null), fname, "\n");
                }
            }

            needs_flush = sr.files.items.len > 0;
        }

        if (needs_flush) {
            try out_stream.flush();
        }
    }
}
