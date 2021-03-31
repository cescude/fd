const std = @import("std");
var stdout = std.io.getStdOut();

const sep = std.fs.path.sep_str;

const Config = struct {
    use_color: bool = true,
    files_only: bool = false,
};

const Args = struct {
    allocator: *std.mem.Allocator,

    values: std.ArrayList([]const u8), // Backing array for string arguments
    positionals: std.ArrayList([]const u8), // Backing array for positional arguments

    args: std.ArrayList(Arg), // List of argument patterns

    const Self = @This();

    // How to handle Optionals?
    const Arg = struct {
        long_name: ?[]const u8,
        short_name: ?u8,
        description: []const u8,
        val_ptr: union(enum) {
            Flag: *?bool,
            Value: *?[]const u8,
        },
    };

    pub fn init(allocator: *std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .values = std.ArrayList([]const u8).init(allocator),
            .positionals = std.ArrayList([]const u8).init(allocator),
            .args = std.ArrayList(Arg).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.values.items) |str| {
            self.allocator.free(str);
        }
        self.values.deinit();

        for (self.positionals.items) |str| {
            self.allocator.free(str);
        }
        self.positionals.deinit();

        self.args.deinit();
    }

    pub fn flag(self: *Self, long: ?[]const u8, short: ?u8, ptr: *?bool, desc: []const u8) !void {
        try self.args.append(Arg{
            .long_name = long,
            .short_name = short,
            .description = desc,
            .val_ptr = .{ .Flag = ptr },
        });
    }

    pub fn option(self: *Self, long: ?[]const u8, short: ?u8, ptr: *?[]const u8, desc: []const u8) !void {
        try self.args.append(Arg{
            .long_name = long,
            .short_name = short,
            .description = desc,
            .val_ptr = .{ .Value = ptr },
        });
    }

    pub fn positionals(self: *Self) [][]const u8 {
        return self.positionals.items;
    }

    pub fn processCommandLine(self: *Self) !void {
        var argv = try std.process.argsAlloc(self.allocator);
        defer std.process.argsFree(self.allocator, argv);
        try process(argv);
    }

    const Action = enum {
        Continue,
        ConsumedToken,
    };

    pub fn process(self: *Self, argv: [][]const u8) !void {
        var no_more_flags = false;

        var idx: usize = 0;
        while (idx < argv.len) : (idx += 1) {
            var token = argv[idx];

            if (no_more_flags) {
                std.debug.print("Positional {s}\n", .{token});
            } else {
                if (std.mem.eql(u8, token, "--")) {
                    no_more_flags = true;
                } else if (std.mem.startsWith(u8, token, "--")) {
                    const action = try self.fillLongValue(token[2..], argv[idx + 1 ..]);
                    switch (action) {
                        .Continue => {},
                        .ConsumedToken => idx += 1, // we used argv[idx+1] for the value
                    }
                } else if (std.mem.startsWith(u8, token, "-")) {
                    std.debug.print("Short opt {s}\n", .{token});
                } else {
                    std.debug.print("Positional {s}\n", .{token});
                }
            }
        }
    }

    fn extractName(token: []const u8) []const u8 {
        if (std.mem.indexOf(u8, token, "=")) |idx| {
            return token[0..idx];
        } else {
            return token;
        }
    }

    fn extractEqualValue(token: []const u8) ?[]const u8 {
        if (std.mem.indexOf(u8, token, "=")) |idx| {
            return token[idx + 1 ..];
        } else {
            return null;
        }
    }

    fn extractNextValue(remainder: [][]const u8) ?[]const u8 {
        if (remainder.len > 0 and !std.mem.startsWith(u8, remainder[0], "-")) {
            return remainder[0];
        } else {
            return null;
        }
    }

    fn findLongArg(args: []Arg, name: []const u8) ?Arg {
        for (args) |arg| {
            if (arg.long_name) |long_name| {
                if (std.mem.eql(u8, long_name, name)) {
                    return arg;
                }
            }
        }

        return null;
    }

    fn fillLongValue(self: *Self, token: []const u8, remainder: [][]const u8) !Action {
        var name = extractName(token);

        var arg: Arg = findLongArg(self.args.items, name) orelse return error.UnrecognizedOptionName;

        var consumed_token_from_remainder = false;

        switch (arg.val_ptr) {
            .Flag => |ptr| {
                ptr.* = true; // Just a bare flag. To support --xyz=on, etc, use an enum string (TODO)
            },
            .Value => |ptr| {
                const value = if (extractEqualValue(token)) |v|
                // --xyz=something
                    v
                else if (extractNextValue(remainder)) |v| brk: {
                    // --xyz something
                    consumed_token_from_remainder = true;
                    break :brk v;
                } else return error.MissingStringValue;

                ptr.* = try self.allocator.dupe(u8, value);
                errdefer self.allocator.free(ptr.*.?);

                try self.values.append(ptr.*.?); // Track this string to free on deinit
            },
        }

        return if (consumed_token_from_remainder) Action.ConsumedToken else Action.Continue;
    }
};

const expect = std.testing.expect;

test "args" {
    var args = Args.init(std.testing.allocator);
    defer args.deinit();

    var bool_one: ?bool = undefined; // No default value
    var bool_two: ?bool = false;
    var bool_three: ?bool = true; // Kind of useless?

    var str_one: ?[]const u8 = undefined; // No default value
    var str_two: ?[]const u8 = "default!";

    try args.flag("bool_one", null, &bool_one, "No default boolean");
    try args.flag("bool_two", null, &bool_two, "Boolean with default of false");
    try args.flag("bool_three", null, &bool_three, "Useless boolean with default of true");

    try args.option("str_one", null, &str_one, "No default string!");
    try args.option("str_two", null, &str_two, "String with default");

    var my_args = [_][]const u8{ "--bool_one", "--bool_two", "--str_one", "Jose", "--str_one=Nope" };

    try args.process(my_args[0..]);
    std.debug.print(
        \\bool_one={s}
        \\bool_two={s}
        \\bool_three={s}
        \\str_one={s}
        \\str_two={s}
    , .{ bool_one, bool_two, bool_three, str_one, str_two });
}

pub fn main() !void {
    var buffer: [4096]u8 = undefined;
    var cwd = try std.os.getcwd(buffer[0..]);

    const cfg = Config{ .use_color = std.os.isatty(stdout.handle) };

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
    try args.process();

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
                            try self.styled(Style.AccessDenied, dropRoot(root, cur_path), "\n");
                            continue;
                        },
                        else => return err,
                    }
                };
                defer dir.close();

                if (paths.items.len > 0) {
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

                for (files_found.items) |file| {
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
    };
}
