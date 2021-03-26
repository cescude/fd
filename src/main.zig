const std = @import("std");
var stdout = std.io.getStdOut();

const Config = struct {
    use_color: bool = true,
};

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

    var proc = Proc(@TypeOf(writer)).init(allocator, cfg, &writer);
    try proc.run(cwd);
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
            Unknown,
        };

        pub fn styled(self: *Self, comptime style: Style, str: []const u8) !void {
            const sep = std.fs.path.sep_str;
            if (self.cfg.use_color) {
                switch (style) {
                    .Prefix => try self.writer.print("\u{001b}[1m{s}{s}\u{001b}[0m", .{ str, sep }),
                    .Default, .Unknown => try self.writer.print("{s}\n", .{str}),
                    .SymLink => try self.writer.print("\u{001b}[31;1m\u{001b}[7m{s}\u{001b}[0m\n", .{str}),
                }
            } else {
                switch (style) {
                    .Prefix => try self.writer.print("{s}{s}", .{ str, sep }),
                    else => try self.writer.print("{s}\n", .{str}),
                }
            }
        }

        pub fn run(self: *Self, root: []u8) !void {
            var paths = std.ArrayList([]const u8).init(self.allocator);
            defer {
                for (paths.items) |p| unreachable; //allocator.free(p);
                paths.deinit();
            }

            try paths.append(try self.allocator.dupe(u8, root));
            while (paths.items.len > 0) {
                var cur_path = paths.pop();
                defer self.allocator.free(cur_path);

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
                        try self.styled(Style.Prefix, ss);
                    }
                    try self.styled(Style.Default, fname);
                }

                var entries = std.ArrayList(Entry).init(self.allocator);
                defer {
                    for (entries.items) |entry| {
                        switch (entry.kind) {
                            .Directory => paths.append(entry.name) catch {},
                            else => self.allocator.free(entry.name),
                        }
                    }
                    entries.deinit();
                }

                var iterator = dir.iterate();
                while (try iterator.next()) |p| {
                    if (p.name[0] == '.') continue;

                    var qqq = [_][]const u8{ cur_path, p.name };
                    var joined = try std.fs.path.join(self.allocator, qqq[0..]);

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
                        try self.styled(Style.Prefix, ss);
                    }

                    switch (entry.kind) {
                        .Directory => continue,
                        .File => {
                            try self.styled(Style.Default, fname);
                        },
                        .SymLink => {
                            try self.styled(Style.SymLink, fname);
                        },
                        else => {
                            try self.styled(Style.Unknown, fname);
                        },
                    }
                }
            }
        }
    };
}
