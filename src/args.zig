// TODO: help strings
// TODO: testing positionals
// TODO: friendly error strings to go along with the unfriendly error tags
// TODO: documentation
// TODO: number types?
const std = @import("std");

const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

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

const FlagPtr = struct {
    ptr: usize,
    conv_fn: ConvFn,

    const ConvFn = fn (ptr: usize, value: []const u8) error{ParseError}!void;
};

fn flagConv(ptr: anytype) FlagPtr {
    const T: type = @typeInfo(@TypeOf(ptr)).Pointer.child;

    const impl = struct {
        fn convert(p: usize, value: []const u8) error{ParseError}!void {

            // If T is an optional, we need to get at the underlying type for
            // the below conversions. Define a type C to inspect this.

            const C: type = switch (@typeInfo(T)) {
                .Optional => @typeInfo(T).Optional.child,
                else => T,
            };
            comptime var info = @typeInfo(C);

            var real_ptr: *T = @intToPtr(*T, p);

            switch (info) {
                .Int => switch (info.Int.signedness) {
                    .signed => {
                        real_ptr.* = std.fmt.parseInt(C, value, 10) catch return error.ParseError;
                    },
                    .unsigned => {
                        real_ptr.* = std.fmt.parseUnsigned(C, value, 10) catch return error.ParseError;
                    },
                },
                .Bool => {
                    real_ptr.* = try truthValue(value);
                },
                .Pointer => {
                    const is_const_u8_slice =
                        info.Pointer.size == .Slice and info.Pointer.child == u8 and info.Pointer.is_const;

                    if (is_const_u8_slice) {
                        real_ptr.* = value;
                    } else {
                        @compileError("Unsupported flag type: " ++ @typeName(T));
                    }
                },
                else => {
                    @compileError("Unsupported flag type: " ++ @typeName(T));
                },
            }
        }
    };

    return .{
        .ptr = @ptrToInt(ptr),
        .conv_fn = impl.convert,
    };
}

test "Typed/Generic flag conversion functionality" {
    var flag0: u32 = 0;
    var flag1: i7 = 0;
    var flag2: bool = false;
    var flag3: []const u8 = "fail";

    var flag4: ?bool = null;
    var flag5: ?u64 = null;
    var flag6: ?i63 = null;
    var flag7: ?[]const u8 = "fail";

    const converters = [_]FlagPtr{
        flagConv(&flag0),
        flagConv(&flag1),
        flagConv(&flag2),
        flagConv(&flag3),
        flagConv(&flag4),
        flagConv(&flag5),
        flagConv(&flag6),
        flagConv(&flag7),
    };

    try converters[0].conv_fn(converters[0].ptr, "1234");
    try converters[1].conv_fn(converters[1].ptr, "43");
    try converters[2].conv_fn(converters[2].ptr, "true");
    try converters[3].conv_fn(converters[3].ptr, "pass");
    try converters[4].conv_fn(converters[4].ptr, "true");
    try converters[5].conv_fn(converters[5].ptr, "123456");
    try converters[6].conv_fn(converters[6].ptr, "434343");
    try converters[7].conv_fn(converters[7].ptr, "pass");

    expect(flag0 == 1234);
    expect(flag1 == 43);
    expect(flag2);
    expectEqualStrings("pass", flag3);
    expect(flag4.?);
    expect(flag5.? == 123456);
    expect(flag6.? == 434343);
    expectEqualStrings("pass", flag7.?);
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

pub const Args = CmdArgs(void); // Simple non-subcommand-using option parsing

// Option parsing that allows for subcommands (just pass the enum type to construct)
pub fn CmdArgs(comptime CommandEnumT: type) type {
    const SubCommand = struct {
        name: []const u8,
        cmd: CommandEnumT, // No more than 2^32 subcommands...
        args: Args,
    };

    return struct {
        allocator: *std.mem.Allocator,

        values: std.ArrayList([]const u8), // Backing array for string arguments
        positionals: std.ArrayList([]const u8), // Backing array for positional arguments

        flags: std.ArrayList(FlagConf), // List of argument patterns
        subcommands: std.ArrayList(SubCommand), // Allow to switch into namespaced command args
        command_used: ?CommandEnumT,

        const Self = @This();

        const Error = error{ ParseError, OutOfMemory };

        pub fn init(allocator: *std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .values = std.ArrayList([]const u8).init(allocator),
                .positionals = std.ArrayList([]const u8).init(allocator),
                .flags = std.ArrayList(FlagConf).init(allocator),
                .subcommands = std.ArrayList(SubCommand).init(allocator),
                .command_used = null,
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

            self.flags.deinit();

            for (self.subcommands.items) |*sub| {
                sub.args.deinit();
            }
            self.subcommands.deinit();
        }

        fn boolFlag(self: *Self, long: ?[]const u8, short: ?u8, ptr: *bool, desc: []const u8) !void {
            try self.flags.append(FlagConf{
                .long_name = long,
                .short_name = short,
                .description = desc,
                .val_ptr = .{ .BoolFlag = ptr },
            });
        }

        fn boolFlagOpt(self: *Self, long: ?[]const u8, short: ?u8, ptr: *?bool, desc: []const u8) !void {
            try self.flags.append(FlagConf{
                .long_name = long,
                .short_name = short,
                .description = desc,
                .val_ptr = .{ .OptBoolFlag = ptr },
            });
        }

        fn stringFlag(self: *Self, long: ?[]const u8, short: ?u8, ptr: *[]const u8, desc: []const u8) !void {
            try self.flags.append(FlagConf{
                .long_name = long,
                .short_name = short,
                .description = desc,
                .val_ptr = .{ .Flag = ptr },
            });
        }

        fn stringFlagOpt(self: *Self, long: ?[]const u8, short: ?u8, ptr: *?[]const u8, desc: []const u8) !void {
            try self.flags.append(FlagConf{
                .long_name = long,
                .short_name = short,
                .description = desc,
                .val_ptr = .{ .OptFlag = ptr },
            });
        }

        // TODO: Not sure if I like this; it might be a little too fancy
        //       compared to something like "boolFlag(...)" and
        //       "boolFlagOpt(...)". Keeping for now, though.
        pub fn flag(self: *Self, long: ?[]const u8, short: ?u8, ptr: anytype, desc: []const u8) !void {
            if (@TypeOf(ptr) == *bool) {
                try self.boolFlag(long, short, ptr, desc);
            } else if (@TypeOf(ptr) == *?bool) {
                try self.boolFlagOpt(long, short, ptr, desc);
            } else if (@TypeOf(ptr) == *[]const u8) {
                try self.stringFlag(long, short, ptr, desc);
            } else if (@TypeOf(ptr) == *?[]const u8) {
                try self.stringFlagOpt(long, short, ptr, desc);
            } else {
                @compileError("Unsupported ptr type " ++ @typeName(@TypeOf(ptr)));
            }
        }

        // For right now, we don't support subcommands of subcommands.
        pub fn command(self: *Self, name: []const u8, cmd: CommandEnumT) !*Args {
            if (CommandEnumT == void) {
                @compileError("Subcommands not allowed against a void command type. Use `CmdArgs` to get this functionality!!");
            }
            try self.subcommands.append(SubCommand{
                .name = name,
                .cmd = cmd,
                .args = Args.init(self.allocator),
            });
            return &self.subcommands.items[self.subcommands.items.len - 1].args;
        }

        pub fn getCommand(self: *Self) ?CommandEnumT {
            if (CommandEnumT == void) {
                @compileError("Subcommands not allowed against a void command type. Use `CmdArgs` to get this functionality!");
            }
            return self.command_used;
        }

        // TODO: add test case
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

        pub fn parseSlice(self: *Self, argv: [][]const u8) Error!void {
            var no_more_flags = false;
            self.command_used = null;

            var idx: usize = 0;
            while (idx < argv.len) : (idx += 1) {
                var token = argv[idx];

                if (no_more_flags) {
                    try self.addPositional(token); // TODO: needs test case
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
                        try self.addPositional(token); // TODO: needs test case
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
                        if (self.positionals.items.len == 0) {

                            // If this is the first positional token we've
                            // encountered (before a "--"), check to see if
                            // a subcommand is being referenced.

                            // TODO: needs testing
                            for (self.subcommands.items) |*sub_cmd| {
                                if (std.mem.eql(u8, sub_cmd.name, token)) {
                                    self.command_used = sub_cmd.cmd;
                                    try sub_cmd.args.parseSlice(argv[idx + 1 ..]);
                                    return;
                                }
                            } else {

                                // Nope, no subcommand, so just treat like a normal
                                // positional.
                                try self.addPositional(token); // TODO: needs test case
                            }
                        } else {
                            try self.addPositional(token); // TODO: needs test case
                        }
                    }
                }
            }
        }

        fn addPositional(self: *Self, value: []const u8) !void {
            try self.positionals.append(try self.allocator.dupe(u8, value));
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

        fn toTruthy(val: []const u8) !bool {
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

        fn fillLongValue(self: *Self, token: []const u8, remainder: [][]const u8) !Action {
            var name = extractName(token);
            var arg: FlagConf = getFlagByLongName(self.flags.items, name) orelse return error.ParseError;

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
                    } else return error.ParseError; // missing string value

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
                    } else return error.ParseError; // missing string value

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
            var arg: FlagConf = getFlagByShortName(self.flags.items, name) orelse return error.ParseError; // bad name

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
                        return error.ParseError; // missing string value
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
                        return error.ParseError; // missing string value
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
}

test "anyflag" {
    var args = Args.init(std.testing.allocator);
    defer args.deinit();

    var flag0: ?bool = null;
    var flag1: bool = false;
    var flag2: ?[]const u8 = null;
    var flag3: []const u8 = "fail";

    try args.flag("flag0", null, &flag0, "Boolean Opt");
    try args.flag("flag1", null, &flag1, "Boolean");
    try args.flag("flag2", null, &flag2, "String Opt");
    try args.flag("flag3", null, &flag3, "String");

    var argv = [_][]const u8{ "--flag0=yes", "--flag1=1", "--flag2=pass", "--flag3=pass" };
    try args.parseSlice(argv[0..]);

    expect(flag0 orelse false);
    expect(flag1);
    expectEqualStrings("pass", flag2 orelse "fail");
    expectEqualStrings("pass", flag3);
}

test "Omitted flags get default values" {
    var args = Args.init(std.testing.allocator);
    defer args.deinit();

    var flag0: ?bool = null;
    var flag1: ?bool = true;
    var flag2: ?[]const u8 = null;
    var flag3: ?[]const u8 = "default";

    try args.flag("flag0", 'a', &flag0, "Optional boolean");
    try args.flag("flag1", 'b', &flag1, "Default true boolean");
    try args.flag("flag2", 'c', &flag2, "Optional string");
    try args.flag("flag3", 'd', &flag3, "Defaulted string");

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

    try args.flag("flag0", 'a', &flag0, "Optional boolean");
    try args.flag("flag1", 'b', &flag1, "Default true boolean");
    try args.flag("flag2", 'c', &flag2, "Optional string");
    try args.flag("flag3", 'd', &flag3, "Defaulted string");

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

    try args.flag("flag_equal", 'a', &flag_equal, "flag_equal");
    try args.flag("flag_posn", 'b', &flag_posn, "flag_posn");

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

    try args.flag("flag0", 'a', &flag0, "flag0");
    try args.flag("flag1", 'b', &flag1, "flag1");

    var argv = [_][]const u8{"--flag10=aaa"};
    expectError(error.ParseError, args.parseSlice(argv[0..]));

    argv = [_][]const u8{"-c"};
    expectError(error.ParseError, args.parseSlice(argv[0..]));

    argv = [_][]const u8{"-ac"};
    expectError(error.ParseError, args.parseSlice(argv[0..]));

    argv = [_][]const u8{"--flag0=not_right"};
    expectError(error.ParseError, args.parseSlice(argv[0..]));
}

test "Missing string argument" {
    var args = Args.init(std.testing.allocator);
    defer args.deinit();

    var miss0: ?[]const u8 = null;
    var miss1: []const u8 = "";

    try args.flag("miss0", 'm', &miss0, "");
    try args.flag("miss1", 'n', &miss1, "");

    // There's four codepaths for this error...

    var argv = [_][]const u8{"--miss0"};
    expectError(error.ParseError, args.parseSlice(argv[0..]));

    argv = [_][]const u8{"--miss1"};
    expectError(error.ParseError, args.parseSlice(argv[0..]));

    argv = [_][]const u8{"-m"};
    expectError(error.ParseError, args.parseSlice(argv[0..]));

    argv = [_][]const u8{"-n"};
    expectError(error.ParseError, args.parseSlice(argv[0..]));
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

    try args.flag("flag_basic", 'a', &flag_basic, "flag_basic");
    try args.flag("flag_true", 'b', &flag_true, "flag_true");
    try args.flag("flag_yes", 'c', &flag_yes, "flag_yes");
    try args.flag("flag_on", 'd', &flag_on, "flag_on");
    try args.flag("flag_y", 'e', &flag_y, "flag_y");
    try args.flag("flag_1", 'f', &flag_1, "flag_1");

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

    try args.flag("flag_basic", 'a', &flag_basic, "flag_basic");
    try args.flag("flag_true", 'b', &flag_true, "flag_true");
    try args.flag("flag_yes", 'c', &flag_yes, "flag_yes");
    try args.flag("flag_on", 'd', &flag_on, "flag_on");
    try args.flag("flag_y", 'e', &flag_y, "flag_y");
    try args.flag("flag_1", 'f', &flag_1, "flag_1");

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

    try args.flag(null, 'a', &flag_a, "");
    try args.flag(null, 'b', &flag_b, "");
    try args.flag(null, 'c', &flag_c, "");

    try args.flag(null, 'd', &flag_d, "");
    try args.flag(null, 'e', &flag_e, "");

    try args.flag(null, 'f', &flag_f, "");
    try args.flag(null, 'g', &flag_g, "");

    try args.flag(null, 'h', &flag_h, "");
    try args.flag(null, 'i', &flag_i, "");

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

test "Basic SubCommands" {
    const Cmd = enum {
        Move,
        Turn,
    };

    var opts = CmdArgs(Cmd).init(std.testing.allocator);
    defer opts.deinit();

    const MoveCfg = struct {
        x: []const u8 = "",
        y: []const u8 = "",
    };

    var move_cfg: MoveCfg = .{};

    var move_opts = try opts.command("move", Cmd.Move);
    try move_opts.flag(null, 'x', &move_cfg.x, "X position");
    try move_opts.flag(null, 'y', &move_cfg.y, "Y position");

    const TurnCfg = struct {
        angle: []const u8 = "",
    };

    var turn_cfg: TurnCfg = .{};

    var turn_opts = try opts.command("turn", Cmd.Turn);
    try turn_opts.flag("angle", 'a', &turn_cfg.angle, "How far to turn");

    var argv1 = [_][]const u8{ "move", "-x=10", "-y", "20" };
    try opts.parseSlice(argv1[0..]);

    if (opts.getCommand()) |cmd| {
        switch (cmd) {
            .Move => {
                expectEqualStrings(move_cfg.x, "10");
                expectEqualStrings(move_cfg.y, "20");
            },
            .Turn => @panic("Found turn!"),
        }
    } else {
        @panic("No subcommands were run!");
    }

    var argv2 = [_][]const u8{ "turn", "--angle", "270" };
    try opts.parseSlice(argv2[0..]);

    if (opts.getCommand()) |cmd| switch (cmd) {
        .Move => @panic("Found move!"),
        .Turn => {
            expectEqualStrings(turn_cfg.angle, "270");
        },
    } else {
        @panic("No subcommands were run!");
    }

    var argv3 = [_][]const u8{ "no", "subcommand", "specified" };
    try opts.parseSlice(argv3[0..]);

    if (opts.getCommand()) |cmd| {
        std.debug.print("11111 {}\n", .{cmd});
        @panic("No subcommand was specified!");
    } else {}
}
