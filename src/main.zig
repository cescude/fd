// TODO: print a reset character before exiting
// TODO: install a signal handler to reset & flush?
const std = @import("std");
const Args = @import("args.zig").Args;
const LSColors = @import("ls_colors.zig");
const ArrayList = std.ArrayList;

var stdout = std.io.getStdOut();

const sep = std.fs.path.sep_str;

// In case there's no LS_COLORS environment variable
const default_colors = "ow=0:or=0;38;5;16;48;5;203:no=0:ex=1;38;5;203:cd=0;38;5;203;48;5;236:mi=0;38;5;16;48;5;203:*~=0;38;5;243:st=0:pi=0;38;5;16;48;5;81:fi=0:di=0;38;5;81:so=0;38;5;16;48;5;203:bd=0;38;5;81;48;5;236:tw=0:ln=0;38;5;203:*.m=0;38;5;48:*.o=0;38;5;243:*.z=4;38;5;203:*.a=1;38;5;203:*.r=0;38;5;48:*.c=0;38;5;48:*.d=0;38;5;48:*.t=0;38;5;48:*.h=0;38;5;48:*.p=0;38;5;48:*.cc=0;38;5;48:*.ll=0;38;5;48:*.jl=0;38;5;48:*css=0;38;5;48:*.md=0;38;5;185:*.gz=4;38;5;203:*.nb=0;38;5;48:*.mn=0;38;5;48:*.go=0;38;5;48:*.xz=4;38;5;203:*.so=1;38;5;203:*.rb=0;38;5;48:*.pm=0;38;5;48:*.bc=0;38;5;243:*.py=0;38;5;48:*.as=0;38;5;48:*.pl=0;38;5;48:*.rs=0;38;5;48:*.sh=0;38;5;48:*.7z=4;38;5;203:*.ps=0;38;5;186:*.cs=0;38;5;48:*.el=0;38;5;48:*.rm=0;38;5;208:*.hs=0;38;5;48:*.td=0;38;5;48:*.ui=0;38;5;149:*.ex=0;38;5;48:*.js=0;38;5;48:*.cp=0;38;5;48:*.cr=0;38;5;48:*.la=0;38;5;243:*.kt=0;38;5;48:*.ml=0;38;5;48:*.vb=0;38;5;48:*.gv=0;38;5;48:*.lo=0;38;5;243:*.hi=0;38;5;243:*.ts=0;38;5;48:*.ko=1;38;5;203:*.hh=0;38;5;48:*.pp=0;38;5;48:*.di=0;38;5;48:*.bz=4;38;5;203:*.fs=0;38;5;48:*.png=0;38;5;208:*.zsh=0;38;5;48:*.mpg=0;38;5;208:*.pid=0;38;5;243:*.xmp=0;38;5;149:*.iso=4;38;5;203:*.m4v=0;38;5;208:*.dot=0;38;5;48:*.ods=0;38;5;186:*.inc=0;38;5;48:*.sxw=0;38;5;186:*.aif=0;38;5;208:*.git=0;38;5;243:*.gvy=0;38;5;48:*.tbz=4;38;5;203:*.log=0;38;5;243:*.txt=0;38;5;185:*.ico=0;38;5;208:*.csx=0;38;5;48:*.vob=0;38;5;208:*.pgm=0;38;5;208:*.pps=0;38;5;186:*.ics=0;38;5;186:*.img=4;38;5;203:*.fon=0;38;5;208:*.hpp=0;38;5;48:*.bsh=0;38;5;48:*.sql=0;38;5;48:*TODO=1:*.php=0;38;5;48:*.pkg=4;38;5;203:*.ps1=0;38;5;48:*.csv=0;38;5;185:*.ilg=0;38;5;243:*.ini=0;38;5;149:*.pyc=0;38;5;243:*.psd=0;38;5;208:*.htc=0;38;5;48:*.swp=0;38;5;243:*.mli=0;38;5;48:*hgrc=0;38;5;149:*.bst=0;38;5;149:*.ipp=0;38;5;48:*.fsi=0;38;5;48:*.tcl=0;38;5;48:*.exs=0;38;5;48:*.out=0;38;5;243:*.jar=4;38;5;203:*.xls=0;38;5;186:*.ppm=0;38;5;208:*.apk=4;38;5;203:*.aux=0;38;5;243:*.rpm=4;38;5;203:*.dll=1;38;5;203:*.eps=0;38;5;208:*.exe=1;38;5;203:*.doc=0;38;5;186:*.wma=0;38;5;208:*.deb=4;38;5;203:*.pod=0;38;5;48:*.ind=0;38;5;243:*.nix=0;38;5;149:*.lua=0;38;5;48:*.epp=0;38;5;48:*.dpr=0;38;5;48:*.htm=0;38;5;185:*.ogg=0;38;5;208:*.bin=4;38;5;203:*.otf=0;38;5;208:*.yml=0;38;5;149:*.pro=0;38;5;149:*.cxx=0;38;5;48:*.tex=0;38;5;48:*.fnt=0;38;5;208:*.erl=0;38;5;48:*.sty=0;38;5;243:*.bag=4;38;5;203:*.rst=0;38;5;185:*.pdf=0;38;5;186:*.pbm=0;38;5;208:*.xcf=0;38;5;208:*.clj=0;38;5;48:*.gif=0;38;5;208:*.rar=4;38;5;203:*.elm=0;38;5;48:*.bib=0;38;5;149:*.tsx=0;38;5;48:*.dmg=4;38;5;203:*.tmp=0;38;5;243:*.bcf=0;38;5;243:*.mkv=0;38;5;208:*.svg=0;38;5;208:*.cpp=0;38;5;48:*.vim=0;38;5;48:*.bmp=0;38;5;208:*.ltx=0;38;5;48:*.fls=0;38;5;243:*.flv=0;38;5;208:*.wav=0;38;5;208:*.m4a=0;38;5;208:*.mid=0;38;5;208:*.hxx=0;38;5;48:*.pas=0;38;5;48:*.wmv=0;38;5;208:*.tif=0;38;5;208:*.kex=0;38;5;186:*.mp4=0;38;5;208:*.bak=0;38;5;243:*.xlr=0;38;5;186:*.dox=0;38;5;149:*.swf=0;38;5;208:*.tar=4;38;5;203:*.tgz=4;38;5;203:*.cfg=0;38;5;149:*.xml=0;38;5;185:*.jpg=0;38;5;208:*.mir=0;38;5;48:*.sxi=0;38;5;186:*.bz2=4;38;5;203:*.odt=0;38;5;186:*.mov=0;38;5;208:*.toc=0;38;5;243:*.bat=1;38;5;203:*.asa=0;38;5;48:*.awk=0;38;5;48:*.sbt=0;38;5;48:*.vcd=4;38;5;203:*.kts=0;38;5;48:*.arj=4;38;5;203:*.blg=0;38;5;243:*.c++=0;38;5;48:*.odp=0;38;5;186:*.bbl=0;38;5;243:*.idx=0;38;5;243:*.com=1;38;5;203:*.mp3=0;38;5;208:*.avi=0;38;5;208:*.def=0;38;5;48:*.cgi=0;38;5;48:*.zip=4;38;5;203:*.ttf=0;38;5;208:*.ppt=0;38;5;186:*.tml=0;38;5;149:*.fsx=0;38;5;48:*.h++=0;38;5;48:*.rtf=0;38;5;186:*.inl=0;38;5;48:*.yaml=0;38;5;149:*.html=0;38;5;185:*.mpeg=0;38;5;208:*.java=0;38;5;48:*.hgrc=0;38;5;149:*.orig=0;38;5;243:*.conf=0;38;5;149:*.dart=0;38;5;48:*.psm1=0;38;5;48:*.rlib=0;38;5;243:*.fish=0;38;5;48:*.bash=0;38;5;48:*.make=0;38;5;149:*.docx=0;38;5;186:*.json=0;38;5;149:*.psd1=0;38;5;48:*.lisp=0;38;5;48:*.tbz2=4;38;5;203:*.diff=0;38;5;48:*.epub=0;38;5;186:*.xlsx=0;38;5;186:*.pptx=0;38;5;186:*.toml=0;38;5;149:*.h264=0;38;5;208:*.purs=0;38;5;48:*.flac=0;38;5;208:*.tiff=0;38;5;208:*.jpeg=0;38;5;208:*.lock=0;38;5;243:*.less=0;38;5;48:*.dyn_o=0;38;5;243:*.scala=0;38;5;48:*.mdown=0;38;5;185:*.shtml=0;38;5;185:*.class=0;38;5;243:*.cache=0;38;5;243:*.cmake=0;38;5;149:*passwd=0;38;5;149:*.swift=0;38;5;48:*shadow=0;38;5;149:*.xhtml=0;38;5;185:*.patch=0;38;5;48:*.cabal=0;38;5;48:*README=0;38;5;16;48;5;186:*.toast=4;38;5;203:*.ipynb=0;38;5;48:*COPYING=0;38;5;249:*.gradle=0;38;5;48:*.matlab=0;38;5;48:*.config=0;38;5;149:*LICENSE=0;38;5;249:*.dyn_hi=0;38;5;243:*.flake8=0;38;5;149:*.groovy=0;38;5;48:*INSTALL=0;38;5;16;48;5;186:*TODO.md=1:*.ignore=0;38;5;149:*Doxyfile=0;38;5;149:*TODO.txt=1:*setup.py=0;38;5;149:*Makefile=0;38;5;149:*.gemspec=0;38;5;149:*.desktop=0;38;5;149:*.rgignore=0;38;5;149:*.markdown=0;38;5;185:*COPYRIGHT=0;38;5;249:*configure=0;38;5;149:*.DS_Store=0;38;5;243:*.kdevelop=0;38;5;149:*.fdignore=0;38;5;149:*README.md=0;38;5;16;48;5;186:*.cmake.in=0;38;5;149:*SConscript=0;38;5;149:*CODEOWNERS=0;38;5;149:*.localized=0;38;5;243:*.gitignore=0;38;5;149:*Dockerfile=0;38;5;149:*.gitconfig=0;38;5;149:*INSTALL.md=0;38;5;16;48;5;186:*README.txt=0;38;5;16;48;5;186:*SConstruct=0;38;5;149:*.scons_opt=0;38;5;243:*.travis.yml=0;38;5;186:*.gitmodules=0;38;5;149:*.synctex.gz=0;38;5;243:*LICENSE-MIT=0;38;5;249:*MANIFEST.in=0;38;5;149:*Makefile.in=0;38;5;243:*Makefile.am=0;38;5;149:*INSTALL.txt=0;38;5;16;48;5;186:*configure.ac=0;38;5;149:*.applescript=0;38;5;48:*appveyor.yml=0;38;5;186:*.fdb_latexmk=0;38;5;243:*CONTRIBUTORS=0;38;5;16;48;5;186:*.clang-format=0;38;5;149:*LICENSE-APACHE=0;38;5;249:*CMakeLists.txt=0;38;5;149:*CMakeCache.txt=0;38;5;243:*.gitattributes=0;38;5;149:*CONTRIBUTORS.md=0;38;5;16;48;5;186:*.sconsign.dblite=0;38;5;243:*requirements.txt=0;38;5;149:*CONTRIBUTORS.txt=0;38;5;16;48;5;186:*package-lock.json=0;38;5;243:*.CFUserTextEncoding=0;38;5;243";

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

pub fn main() !void {
    var buffer: [4096]u8 = undefined;
    var cwd = try std.os.getcwd(buffer[0..]);

    var cfg = Config{};

    var outs = std.io.bufferedWriter(stdout.writer());
    defer outs.flush() catch {};

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());

    // Need to use thread-safe allocators
    const allocator = switch (std.builtin.mode) {
        .ReleaseFast => std.heap.c_allocator,
        else => &gpa.allocator,
    };

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
    try args.flagDecl("num-threads", 'N', &num_threads, null, "Number of threads to use (default is 3)");

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

    try ls_colors.parse(std.os.getenv("LS_COLORS") orelse default_colors);

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

fn styleFor(ls_colors: LSColors, kind: Entry.Kind, mode: u64, extension: ?[]const u8) ?[]const u8 {
    return switch (kind) {
        .BlockDevice => ls_colors.bd,
        .CharacterDevice => ls_colors.cd,
        .Directory => ls_colors.di,
        .NamedPipe => ls_colors.pi,
        .SymLink => ls_colors.ln,
        .File => if ((mode & 1) > 0)
            ls_colors.ex
        else if (extension) |ext|
            ls_colors.extensions.get(ext) orelse ls_colors.fi
        else
            ls_colors.fi,
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

const JobQueue = SafeQueue(*ScanResults);
var job_queue = JobQueue{};

fn SafeQueue(comptime T: type) type {
    return struct {
        unsafe: std.SinglyLinkedList(T) = std.SinglyLinkedList(T){},
        lock: std.Thread.Mutex = std.Thread.Mutex{},

        const LL = std.SinglyLinkedList(T);
        const Self = @This();

        pub const Node = LL.Node;

        pub fn push(self: *Self, item: *Node) void {
            var h = self.lock.acquire();
            defer h.release();
            item.next = self.unsafe.first;
            self.unsafe.first = item;
        }

        pub fn pop(self: *Self) ?*Node {
            var h = self.lock.acquire();
            defer h.release();
            if (self.unsafe.first) |first| {
                self.unsafe.first = first.next;
                return first;
            }
            return null;
        }

        // pub fn push(self: *Self, item: *LL.Node) void {
        //     var maybe_item: ?*LL.Node = item;
        //     while (true) {
        //         var first = self.unsafe.first;
        //         item.next = first;
        //         if (@cmpxchgWeak(?*LL.Node, &self.unsafe.first, first, maybe_item, .SeqCst, .SeqCst)) |_| {
        //             continue;
        //         }
        //         break;
        //     }
        // }

        // pub fn pop(self: *Self) ?*LL.Node {
        //     while (true) {
        //         var first = self.unsafe.first orelse return null;
        //         if (@cmpxchgWeak(?*LL.Node, &self.unsafe.first, first, first.next, .SeqCst, .SeqCst)) |_| {
        //             continue;
        //         }
        //         return first;
        //     }
        // }
    };
}

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
        if (job_queue.pop()) |node| {
            defer ctx.allocator.destroy(node);
            scanPath(cfg, node.data) catch |err| {
                std.debug.print("ERROR (thread={d}): {}\n", .{ id, err });
            };
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
        if (p.kind == .File) {
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
        job_queue.push(job_node);
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
            try styled(writer, if (cfg.use_color == .On) styleFor(ls_colors, .Directory, 0, null) else null, dropRoot(root, sr.path), "");
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
            job_queue.push(job_node);
        }

        if (cfg.print_files) {
            for (sr.files.items) |file| {
                const str = dropRoot(root, file.name);
                const dname = std.fs.path.dirname(str);
                const fname = std.fs.path.basename(str);
                const ename = std.fs.path.extension(str);

                if (cfg.use_color == .Off) {
                    if (dname) |ss| {
                        try writer.print("{s}{s}", .{ ss, sep });
                    }
                    try writer.print("{s}\n", .{fname});
                    continue;
                }

                var mode: u64 = 0;
                if (file.kind == .File) {
                    if (std.fs.openFileAbsolute(file.name, .{ .read = true })) |handle| {
                        defer handle.close();
                        if (handle.stat()) |st| {
                            mode = st.mode;
                        } else |_| {}
                    } else |_| {}
                }

                if (dname) |ss| {
                    try styled(writer, styleFor(ls_colors, .Directory, 0, null), ss, sep);
                }

                if (ename.len > 1) {
                    try styled(writer, styleFor(ls_colors, file.kind, mode, ename[1..]), fname, "\n");
                } else {
                    try styled(writer, styleFor(ls_colors, file.kind, mode, null), fname, "\n");
                }
            }

            needs_flush = sr.files.items.len > 0;
        }

        if (needs_flush) {
            try out_stream.flush();
        }
    }
}
