const std = @import("std");

ls_colors: ?[]const u8, // original LS_COLORS string

// TODO: Handle `rs`, which is presumably "reset"?

// These are all slices of `ls_colors`
di: ?[]const u8 = null, // directory
fi: ?[]const u8 = null, // file
ln: ?[]const u8 = null, // link
pi: ?[]const u8 = null, // pipe
so: ?[]const u8 = null, // socket
bd: ?[]const u8 = null, // block device
cd: ?[]const u8 = null, // character device
orph: ?[]const u8 = null, // orphaned symlink
mi: ?[]const u8 = null, // missing file
ex: ?[]const u8 = null, // executable
extensions: std.StringHashMap([]const u8),

allocator: *std.mem.Allocator,

const Self = @This();
pub fn init(a: *std.mem.Allocator) Self {
    return .{
        .ls_colors = null,
        .extensions = std.StringHashMap([]const u8).init(a),
        .allocator = a,
    };
}

pub fn deinit(self: *Self) void {
    if (self.ls_colors) |ls_colors| {
        self.allocator.free(ls_colors);
    }
    self.extensions.deinit();
}

pub fn parse(self: *Self, _ls_colors: []const u8) !void {
    self.ls_colors = try self.allocator.dupe(u8, _ls_colors);
    var ls_colors = self.ls_colors.?;

    var iter = std.mem.tokenize(ls_colors, ":");
    while (iter.next()) |pair| {
        if (pair.len == 0) continue;

        var equal_pos = std.mem.indexOf(u8, pair, "=") orelse return error.ParseError;
        var lval = pair[0..equal_pos];
        var style = pair[equal_pos + 1 ..];

        if (lval.len < 2) return error.ParseError;

        // TODO: try making this if chain compile-time generated!

        if (std.mem.eql(u8, "*.", lval[0..2])) {
            try self.extensions.put(lval[2..], style);
        } else if (std.mem.eql(u8, "di", lval)) {
            self.di = style;
        } else if (std.mem.eql(u8, "fi", lval)) {
            self.fi = style;
        } else if (std.mem.eql(u8, "ln", lval)) {
            self.ln = style;
        } else if (std.mem.eql(u8, "pi", lval)) {
            self.pi = style;
        } else if (std.mem.eql(u8, "so", lval)) {
            self.so = style;
        } else if (std.mem.eql(u8, "bd", lval)) {
            self.bd = style;
        } else if (std.mem.eql(u8, "cd", lval)) {
            self.cd = style;
        } else if (std.mem.eql(u8, "or", lval)) {
            self.orph = style;
        } else if (std.mem.eql(u8, "mi", lval)) {
            self.mi = style;
        } else if (std.mem.eql(u8, "ex", lval)) {
            self.ex = style;
        } else {
            //std.debug.print("unhandled color type: {s}\n", .{lval});
        }
    }
}
