const std = @import("std");

const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

test "Omitted flags get default values" {
    var args = Args.init(std.testing.allocator);
    defer args.deinit();

    var flag0: ?bool = null;
    var flag1: ?bool = true;
    var flag2: ?[]const u8 = null;
    var flag3: ?[]const u8 = "default";

    try args.boolFlagOpt("flag0", 'a', &flag0, "Optional boolean");
    try args.boolFlagOpt("flag1", 'b', &flag1, "Default true boolean");
    try args.flagOpt("flag2", 'c', &flag2, "Optional string");
    try args.flagOpt("flag3", 'd', &flag3, "Defaulted string");

    var argv = [_][]const u8{};
    try args.parseSlice(argv[0..]);

    expect(flag0 == null);
    expect(flag1 orelse false);
    expect(flag2 == null);
    expectEqualStrings("default", flag3 orelse "fail");
}

test "Flags can be set" {
    var args = Args.init(std.testing.allocator);
    defer args.deinit();

    var flag0: ?bool = null;
    var flag1: ?bool = false;
    var flag2: ?[]const u8 = null;
    var flag3: ?[]const u8 = "default";

    try args.boolFlagOpt("flag0", 'a', &flag0, "Optional boolean");
    try args.boolFlagOpt("flag1", 'b', &flag1, "Default true boolean");
    try args.flagOpt("flag2", 'c', &flag2, "Optional string");
    try args.flagOpt("flag3", 'd', &flag3, "Defaulted string");

    var argv = [_][]const u8{ "--flag0", "--flag1", "--flag2", "aaa", "--flag3", "bbb" };
    try args.parseSlice(argv[0..]);

    expect(flag0 orelse false);
    expect(flag1 orelse false);
    expectEqualStrings("aaa", flag2 orelse "fail");
    expectEqualStrings("bbb", flag3 orelse "fail");

    flag0 = null;
    flag1 = false;
    flag2 = null;
    flag3 = "default";

    argv = [_][]const u8{ "-a", "-b", "-c", "aaa", "-d", "bbb" };
    try args.parseSlice(argv[0..]);

    expect(flag0 orelse false);
    expect(flag1 orelse false);
    expectEqualStrings("aaa", flag2 orelse "fail");
    expectEqualStrings("bbb", flag3 orelse "fail");
}

test "Various ways to set a string value" {
    var args = Args.init(std.testing.allocator);
    defer args.deinit();

    var flag_equal: ?[]const u8 = null;
    var flag_posn: ?[]const u8 = null;

    try args.flagOpt("flag_equal", 'a', &flag_equal, "flag_equal");
    try args.flagOpt("flag_posn", 'b', &flag_posn, "flag_posn");

    var argv = [_][]const u8{ "--flag_equal=aaa", "--flag_posn", "bbb" };
    try args.parseSlice(argv[0..]);

    expectEqualStrings("aaa", flag_equal orelse "fail");
    expectEqualStrings("bbb", flag_posn orelse "fail");

    flag_equal = null;
    flag_posn = null;

    argv = [_][]const u8{ "-a=aaa", "-b", "bbb" };
    try args.parseSlice(argv[0..]);

    expectEqualStrings("aaa", flag_equal orelse "fail");
    expectEqualStrings("bbb", flag_posn orelse "fail");
}

test "Expecting errors on bad input" {
    var args = Args.init(std.testing.allocator);
    defer args.deinit();

    var flag0: ?bool = null;
    var flag1: ?[]const u8 = null;

    try args.boolFlagOpt("flag0", 'a', &flag0, "flag0");
    try args.flagOpt("flag1", 'b', &flag1, "flag1");

    var argv = [_][]const u8{"--flag10=aaa"};
    expectError(error.UnrecognizedOptionName, args.parseSlice(argv[0..]));

    argv = [_][]const u8{"-c"};
    expectError(error.UnrecognizedOptionName, args.parseSlice(argv[0..]));

    argv = [_][]const u8{"-ac"};
    expectError(error.UnrecognizedOptionName, args.parseSlice(argv[0..]));

    argv = [_][]const u8{"--flag0=not_right"};
    expectError(error.UnrecognizedBooleanValue, args.parseSlice(argv[0..]));
}

test "Missing string argument" {
    var args = Args.init(std.testing.allocator);
    defer args.deinit();

    var miss0: ?[]const u8 = null;
    var miss1: []const u8 = "";

    try args.flagOpt("miss0", 'm', &miss0, "");
    try args.flag("miss1", 'n', &miss1, "");

    // There's four codepaths for this error...

    var argv = [_][]const u8{"--miss0"};
    expectError(error.MissingStringValue, args.parseSlice(argv[0..]));

    argv = [_][]const u8{"--miss1"};
    expectError(error.MissingStringValue, args.parseSlice(argv[0..]));

    argv = [_][]const u8{"-m"};
    expectError(error.MissingStringValue, args.parseSlice(argv[0..]));

    argv = [_][]const u8{"-n"};
    expectError(error.MissingStringValue, args.parseSlice(argv[0..]));
}

test "Various ways to set a boolean to true" {
    var args = Args.init(std.testing.allocator);
    defer args.deinit();

    var flag_basic: ?bool = null;
    var flag_true: ?bool = null;
    var flag_yes: ?bool = null;
    var flag_on: ?bool = null;
    var flag_y: ?bool = null;
    var flag_1: ?bool = null;

    try args.boolFlagOpt("flag_basic", 'a', &flag_basic, "flag_basic");
    try args.boolFlagOpt("flag_true", 'b', &flag_true, "flag_true");
    try args.boolFlagOpt("flag_yes", 'c', &flag_yes, "flag_yes");
    try args.boolFlagOpt("flag_on", 'd', &flag_on, "flag_on");
    try args.boolFlagOpt("flag_y", 'e', &flag_y, "flag_y");
    try args.boolFlagOpt("flag_1", 'f', &flag_1, "flag_1");

    var argv = [_][]const u8{
        "--flag_basic", "--flag_true=true", "--flag_yes=yes",
        "--flag_on=on", "--flag_y=y",       "--flag_1=1",
    };
    try args.parseSlice(argv[0..]);

    expect(flag_basic orelse false);
    expect(flag_true orelse false);
    expect(flag_yes orelse false);
    expect(flag_on orelse false);
    expect(flag_y orelse false);
    expect(flag_1 orelse false);

    flag_basic = null;
    flag_true = null;
    flag_yes = null;
    flag_on = null;
    flag_y = null;
    flag_1 = null;

    argv = [_][]const u8{ "-a", "-b=true", "-c=yes", "-d=on", "-e=y", "-f=1" };
    try args.parseSlice(argv[0..]);

    expect(flag_basic orelse false);
    expect(flag_true orelse false);
    expect(flag_yes orelse false);
    expect(flag_on orelse false);
    expect(flag_y orelse false);
    expect(flag_1 orelse false);
}

test "Various ways to set a boolean to false" {
    var args = Args.init(std.testing.allocator);
    defer args.deinit();

    var flag_basic: ?bool = null;
    var flag_true: ?bool = null;
    var flag_yes: ?bool = null;
    var flag_on: ?bool = null;
    var flag_y: ?bool = null;
    var flag_1: ?bool = null;

    try args.boolFlagOpt("flag_basic", 'a', &flag_basic, "flag_basic");
    try args.boolFlagOpt("flag_true", 'b', &flag_true, "flag_true");
    try args.boolFlagOpt("flag_yes", 'c', &flag_yes, "flag_yes");
    try args.boolFlagOpt("flag_on", 'd', &flag_on, "flag_on");
    try args.boolFlagOpt("flag_y", 'e', &flag_y, "flag_y");
    try args.boolFlagOpt("flag_1", 'f', &flag_1, "flag_1");

    var argv = [_][]const u8{
        "--flag_true=false", "--flag_yes=no",
        "--flag_on=off",     "--flag_y=n",
        "--flag_1=0",
    };
    try args.parseSlice(argv[0..]);

    expect(flag_basic == null);
    expect(!flag_true.?);
    expect(!flag_yes.?);
    expect(!flag_on.?);
    expect(!flag_y.?);
    expect(!flag_1.?);

    flag_basic = null;
    flag_true = null;
    flag_yes = null;
    flag_on = null;
    flag_y = null;
    flag_1 = null;

    argv = [_][]const u8{ "-b=false", "-c=no", "-d=off", "-e=n", "-f=0" };
    try args.parseSlice(argv[0..]);

    expect(flag_basic == null);
    expect(!flag_true.?);
    expect(!flag_yes.?);
    expect(!flag_on.?);
    expect(!flag_y.?);
    expect(!flag_1.?);
}

test "Mashing together short opts" {
    var args = Args.init(std.testing.allocator);
    defer args.deinit();

    var flag_a: ?bool = null;
    var flag_b: ?bool = null;
    var flag_c: ?bool = null;

    var flag_d: ?[]const u8 = null;
    var flag_e: ?[]const u8 = null;

    var flag_f: ?bool = null;
    var flag_g: ?[]const u8 = null;

    var flag_h: ?bool = null;
    var flag_i: ?[]const u8 = null;

    try args.boolFlagOpt(null, 'a', &flag_a, "");
    try args.boolFlagOpt(null, 'b', &flag_b, "");
    try args.boolFlagOpt(null, 'c', &flag_c, "");

    try args.flagOpt(null, 'd', &flag_d, "");
    try args.flagOpt(null, 'e', &flag_e, "");

    try args.boolFlagOpt(null, 'f', &flag_f, "");
    try args.flagOpt(null, 'g', &flag_g, "");

    try args.boolFlagOpt(null, 'h', &flag_h, "");
    try args.flagOpt(null, 'i', &flag_i, "");

    var argv = [_][]const u8{ "-abc=no", "-d=pass", "-e", "pass", "-fg=pass", "-hi", "pass" };
    try args.parseSlice(argv[0..]);

    expect(flag_a.?);
    expect(flag_b.?);
    expect(!flag_c.?);

    expectEqualStrings("pass", flag_d.?);
    expectEqualStrings("pass", flag_e.?);

    expect(flag_f.?);
    expectEqualStrings("pass", flag_g.?);

    expect(flag_h.?);
    expectEqualStrings("pass", flag_i.?);
}

const FlagConf = struct {
    long_name: ?[]const u8,
    short_name: ?u8,
    description: []const u8,
    val_ptr: union(enum) {
        OptBoolFlag: *?bool,
        BoolFlag: *bool,
        OptFlag: *?[]const u8,
        Flag: *[]const u8,
    },
};

pub const Args = struct {
    allocator: *std.mem.Allocator,

    values: std.ArrayList([]const u8), // Backing array for string arguments
    positionals: std.ArrayList([]const u8), // Backing array for positional arguments

    args: std.ArrayList(FlagConf), // List of argument patterns

    const Self = @This();

    pub fn init(allocator: *std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .values = std.ArrayList([]const u8).init(allocator),
            .positionals = std.ArrayList([]const u8).init(allocator),
            .args = std.ArrayList(FlagConf).init(allocator),
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

    pub fn boolFlag(self: *Self, long: ?[]const u8, short: ?u8, ptr: *bool, desc: []const u8) !void {
        try self.args.append(FlagConf{
            .long_name = long,
            .short_name = short,
            .description = desc,
            .val_ptr = .{ .BoolFlag = ptr },
        });
    }

    pub fn boolFlagOpt(self: *Self, long: ?[]const u8, short: ?u8, ptr: *?bool, desc: []const u8) !void {
        try self.args.append(FlagConf{
            .long_name = long,
            .short_name = short,
            .description = desc,
            .val_ptr = .{ .OptBoolFlag = ptr },
        });
    }

    pub fn flag(self: *Self, long: ?[]const u8, short: ?u8, ptr: *[]const u8, desc: []const u8) !void {
        try self.args.append(FlagConf{
            .long_name = long,
            .short_name = short,
            .description = desc,
            .val_ptr = .{ .Flag = ptr },
        });
    }

    pub fn flagOpt(self: *Self, long: ?[]const u8, short: ?u8, ptr: *?[]const u8, desc: []const u8) !void {
        try self.args.append(FlagConf{
            .long_name = long,
            .short_name = short,
            .description = desc,
            .val_ptr = .{ .OptFlag = ptr },
        });
    }

    pub fn positionals(self: *Self) [][]const u8 {
        return self.positionals.items;
    }

    pub fn parse(self: *Self) !void {
        var argv = try std.process.argsAlloc(self.allocator);
        defer std.process.argsFree(self.allocator, argv);
        try self.parseSlice(argv[0..]);
    }

    const Action = enum {
        AdvanceOneCharacter,
        ContinueToNextToken,
        SkipNextToken,
    };

    pub fn parseSlice(self: *Self, argv: [][]const u8) !void {
        var no_more_flags = false;

        var idx: usize = 0;
        while (idx < argv.len) : (idx += 1) {
            var token = argv[idx];

            if (no_more_flags) {
                try self.positionals.append(try self.allocator.dupe(u8, token));
            } else {
                if (std.mem.eql(u8, token, "--")) {
                    no_more_flags = true;
                } else if (std.mem.startsWith(u8, token, "--")) {
                    const action = try self.fillLongValue(token[2..], argv[idx + 1 ..]);
                    switch (action) {
                        .AdvanceOneCharacter => unreachable,
                        .ContinueToNextToken => {},
                        .SkipNextToken => idx += 1, // we used argv[idx+1] for the value
                    }
                } else if (std.mem.eql(u8, token, "-")) {
                    std.debug.print("Positional {s}\n", .{token});
                } else if (std.mem.startsWith(u8, token, "-")) {

                    // Pull out all short flags from the token
                    token = token[1..];
                    shortloop: while (token.len > 0) {
                        const action = try self.fillShortValue(token, argv[idx + 1 ..]);
                        switch (action) {
                            .AdvanceOneCharacter => token = token[1..], // go to the next short flag
                            .ContinueToNextToken => {
                                break :shortloop;
                            },
                            .SkipNextToken => {
                                idx += 1;
                                break :shortloop;
                            },
                        }
                    }
                } else {
                    try self.positionals.append(try self.allocator.dupe(u8, token));
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

    fn getFlagByLongName(args: []FlagConf, name: []const u8) ?FlagConf {
        for (args) |arg| {
            if (arg.long_name) |long_name| {
                if (std.mem.eql(u8, long_name, name)) {
                    return arg;
                }
            }
        }

        return null;
    }

    fn getFlagByShortName(args: []FlagConf, name: u8) ?FlagConf {
        for (args) |arg| {
            if (arg.short_name) |short_name| {
                if (short_name == name) {
                    return arg;
                }
            }
        }

        return null;
    }

    fn contains(comptime T: type, needle: []const T, haystack: [][]const T) bool {
        for (haystack) |hay| {
            if (std.mem.eql(T, needle, hay)) {
                return true;
            }
        }

        return false;
    }

    fn toTruthy(val: []const u8) !bool {
        var truly: [5][]const u8 = .{ "true", "yes", "on", "y", "1" };
        var falsy: [5][]const u8 = .{ "false", "no", "off", "n", "0" };

        if (contains(u8, val, truly[0..])) {
            return true;
        }

        if (contains(u8, val, falsy[0..])) {
            return false;
        }

        return error.UnrecognizedBooleanValue;
    }

    fn fillLongValue(self: *Self, token: []const u8, remainder: [][]const u8) !Action {
        var name = extractName(token);
        var arg: FlagConf = getFlagByLongName(self.args.items, name) orelse return error.UnrecognizedOptionName;

        var action_taken: Action = undefined;

        switch (arg.val_ptr) {
            .BoolFlag => |ptr| {
                action_taken = Action.ContinueToNextToken;
                if (extractEqualValue(token)) |value| {
                    ptr.* = try toTruthy(value);
                } else {
                    ptr.* = true;
                }
            },
            .OptBoolFlag => |ptr| {
                action_taken = Action.ContinueToNextToken;
                if (extractEqualValue(token)) |value| {
                    ptr.* = try toTruthy(value);
                } else {
                    ptr.* = true;
                }
            },
            .Flag => |ptr| {
                var value: []const u8 = undefined;

                if (extractEqualValue(token)) |v| {
                    action_taken = Action.ContinueToNextToken;
                    value = v;
                } else if (extractNextValue(remainder)) |v| {
                    action_taken = Action.SkipNextToken;
                    value = v;
                } else return error.MissingStringValue;

                const value_copy = try self.allocator.dupe(u8, value);
                errdefer self.allocator.free(value_copy);
                try self.values.append(value_copy); // Track this string to free on deinit
                ptr.* = value_copy;
            },
            .OptFlag => |ptr| {
                var value: []const u8 = undefined;

                if (extractEqualValue(token)) |v| {
                    action_taken = Action.ContinueToNextToken;
                    value = v;
                } else if (extractNextValue(remainder)) |v| {
                    action_taken = Action.SkipNextToken;
                    value = v;
                } else return error.MissingStringValue;

                const value_copy = try self.allocator.dupe(u8, value);
                errdefer self.allocator.free(value_copy);
                try self.values.append(value_copy); // Track this string to free on deinit
                ptr.* = value_copy;
            },
        }

        return action_taken;
    }

    fn fillShortValue(self: *Self, token: []const u8, remainder: [][]const u8) !Action {
        var name = token[0];
        var arg: FlagConf = getFlagByShortName(self.args.items, name) orelse return error.UnrecognizedOptionName;

        var action_taken: Action = undefined;

        switch (arg.val_ptr) {
            .BoolFlag => |ptr| {
                if (token.len > 1 and token[1] == '=') {
                    action_taken = Action.ContinueToNextToken; // didn't use any of the remainder
                    ptr.* = try toTruthy(token[2..]);
                } else {
                    action_taken = Action.AdvanceOneCharacter;
                    ptr.* = true;
                }
            },
            .OptBoolFlag => |ptr| {
                if (token.len > 1 and token[1] == '=') {
                    action_taken = Action.ContinueToNextToken; // didn't use any of the remainder
                    ptr.* = try toTruthy(token[2..]);
                } else {
                    action_taken = Action.AdvanceOneCharacter;
                    ptr.* = true;
                }
            },
            .Flag => |ptr| {
                var value: []const u8 = undefined;

                if (token.len > 1 and token[1] == '=') {
                    action_taken = Action.ContinueToNextToken;
                    value = token[2..];
                } else if (extractNextValue(remainder)) |v| {
                    action_taken = Action.SkipNextToken;
                    value = v;
                } else {
                    return error.MissingStringValue;
                }

                const value_copy = try self.allocator.dupe(u8, value);
                errdefer self.allocator.free(value_copy);
                try self.values.append(value_copy);
                ptr.* = value_copy;
            },
            .OptFlag => |ptr| {
                var value: []const u8 = undefined;

                if (token.len > 1 and token[1] == '=') {
                    action_taken = Action.ContinueToNextToken;
                    value = token[2..];
                } else if (extractNextValue(remainder)) |v| {
                    action_taken = Action.SkipNextToken;
                    value = v;
                } else {
                    return error.MissingStringValue;
                }

                const value_copy = try self.allocator.dupe(u8, value);
                errdefer self.allocator.free(value_copy);
                try self.values.append(value_copy);
                ptr.* = value_copy;
            },
        }

        return action_taken;
    }
};
