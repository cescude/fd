const std = @import("std");
const expect = std.testing.expect;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;

fn contains(comptime T: type, needle: []const T, haystack: [][]const T) bool {
    for (haystack) |hay| {
        if (std.mem.eql(T, needle, hay)) {
            return true;
        }
    }

    return false;
}

fn truthValue(val: []const u8) !bool {
    var truly: [5][]const u8 = .{ "true", "yes", "on", "y", "1" };
    var falsy: [5][]const u8 = .{ "false", "no", "off", "n", "0" };

    if (contains(u8, val, truly[0..])) {
        return true;
    }

    if (contains(u8, val, falsy[0..])) {
        return false;
    }

    return error.ParseError;
}

pub const FlagConverter = struct {
    ptr: usize,
    conv_fn: ConvFn,

    const Self = @This();

    const ConvFn = fn (ptr: usize, value: []const u8) error{ParseError}!void;

    // T can be bool, or ?bool
    fn _convertBool(comptime T: type, p: *T, value: []const u8) !void {
        var v = p;
        v.* = try truthValue(value);
    }

    // T can be []const u8, or ?[]const u8
    fn _convertStr(comptime T: type, p: *T, value: []const u8) !void {
        var v = p;
        v.* = value;
    }

    // T can be C, or ?C
    fn _convertNum(comptime T: type, comptime C: type, p: *T, value: []const u8) !void {
        var v = p;
        const info = @typeInfo(C);
        v.* = switch (info) {
            .Int => switch (info.Int.signedness) {
                .signed => std.fmt.parseInt(C, value, 10) catch return error.ParseError,
                .unsigned => std.fmt.parseUnsigned(C, value, 10) catch return error.ParseError,
            },
            else => @compileError("Unsupported number type: " ++ @typeName(C)),
        };
    }

    pub fn init(ptr: anytype) Self {
        const T = @typeInfo(@TypeOf(ptr)).Pointer.child; // ptr must be a pointer!
        const C: type = switch (@typeInfo(T)) {
            .Optional => @typeInfo(T).Optional.child,
            else => T,
        };

        const info = @typeInfo(C);

        const impl = struct {
            pub fn convert(p: usize, value: []const u8) error{ParseError}!void {
                switch (info) {
                    .Int => try _convertNum(T, C, @intToPtr(*T, p), value),
                    .Bool => try _convertBool(T, @intToPtr(*T, p), value),
                    .Pointer => try _convertStr(T, @intToPtr(*T, p), value),
                    else => @compileError("Unsupported type " ++ @typeName(T)),
                }
            }
        };

        const can_convert: bool = switch (info) {
            .Bool, .Int => true,
            // Only if it's a pointer to a []const u8
            .Pointer => info.Pointer.size == .Slice and info.Pointer.is_const and info.Pointer.child == u8,
            else => false,
        };

        if (!can_convert) {
            @compileError("Unsupported type " ++ @typeName(T));
        }

        return FlagConverter{ .ptr = @ptrToInt(ptr), .conv_fn = impl.convert };
    }
};

test "Typed/Generic flag conversion functionality" {
    var b0: bool = false;
    var b0c = FlagConverter.init(&b0);
    try b0c.conv_fn(b0c.ptr, "true");
    expect(b0);

    var b1: ?bool = null;
    var b1c = FlagConverter.init(&b1);
    try b1c.conv_fn(b1c.ptr, "yes");
    expect(b1.?);
    try b1c.conv_fn(b1c.ptr, "no");
    expect(!b1.?);

    var uu0: u15 = 0;
    var uu0c = FlagConverter.init(&uu0);
    try uu0c.conv_fn(uu0c.ptr, "12");
    expect(uu0 == 12);
    expectError(error.ParseError, uu0c.conv_fn(uu0c.ptr, "-12"));
    expectError(error.ParseError, uu0c.conv_fn(uu0c.ptr, "7000000"));

    var uu1: ?u8 = null;
    var uu1c = FlagConverter.init(&uu1);
    try uu1c.conv_fn(uu1c.ptr, "12");
    expect(uu1.? == 12);
    expectError(error.ParseError, uu1c.conv_fn(uu1c.ptr, "-12"));
    expectError(error.ParseError, uu1c.conv_fn(uu1c.ptr, "7000000"));

    var ii0: i7 = 0;
    var ii0c = FlagConverter.init(&ii0);
    try ii0c.conv_fn(ii0c.ptr, "-60");
    expect(ii0 == -60);
    expectError(error.ParseError, ii0c.conv_fn(ii0c.ptr, "7000000"));

    var ii1: ?i7 = 0;
    var ii1c = FlagConverter.init(&ii1);
    try ii1c.conv_fn(ii1c.ptr, "-60");
    expect(ii1.? == -60);
    expectError(error.ParseError, ii1c.conv_fn(ii1c.ptr, "7000000"));

    var str0: []const u8 = "";
    var str0c = FlagConverter.init(&str0);
    try str0c.conv_fn(str0c.ptr, "pass");
    expectEqualStrings("pass", str0);

    var str1: ?[]const u8 = null;
    var str1c = FlagConverter.init(&str1);
    try str1c.conv_fn(str1c.ptr, "pass");
    expectEqualStrings("pass", str1.?);
}
