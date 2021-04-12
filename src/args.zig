// TODO: Add a readme or something
// TODO: place ptr up front in flag/arg/extra commands
const std = @import("std");

const reflowText = @import("reflow_text.zig").reflowText;
const FlagConverter = @import("flag_converters.zig").FlagConverter;

const max_width: usize = 80; // TODO: try to figure out the width of the terminal or whatever

pub const Args = CmdArgs(void); // Simple non-subcommand-using option parsing

// Option parsing that allows for subcommands (just pass the enum type to construct)
pub fn CmdArgs(comptime CommandEnumT: type) type {
    return struct {
        allocator: *std.mem.Allocator,

        program_name: ?[]const u8 = null,
        program_summary: ?[]const u8 = null,

        values: std.ArrayList([]const u8), // Backing array for string arguments

        // Basic pattern:
        //   cmd FLAGS... ARGS... EXTRAS...
        //
        // Both "ARGS" and "EXTRAS" are positional arguments; the difference is
        // that EXTRAS are overflow, as in (defun cmd (arg0 arg1 &rest extra)).
        //
        // ...so, take "grep": the first positional argument is the pattern, the
        // remaining arguments are which files to search.

        flags: std.ArrayList(FlagDefinition), // List of argument patterns
        args: std.ArrayList(PositionalDefinition),

        positionals: std.ArrayList([]const u8), // Backing array for all positional arguments
        positional_extras: ?ExtrasDefinition = null, // Used if we need to capture the positionals that trail args

        subcommands: std.ArrayList(SubCommandDefinition), // Allow to switch into namespaced command args
        command_used: ?CommandEnumT,

        last_error: ?[]const u8 = null,

        const Self = @This();

        const Error = error{ ParseError, OutOfMemory };

        const FlagDefinition = struct {
            long_name: ?[]const u8,
            short_name: ?u8,
            val_name: ?[]const u8,
            description: []const u8,
            // There's different parsing rules if this is a bool (flag) vs string
            // (option), namely that bools can omit an equals value, and can't be
            // assigned by a token in the next position.
            //
            // Eg: "--bool_flag" and "--bool_flag=true" but not "--bool_flag true"
            parse_type: enum { Bool, Str },
            val_ptr: FlagConverter,
        };

        const PositionalDefinition = struct {
            name: []const u8,
            description: []const u8,
            conv: FlagConverter,
        };

        const ExtrasDefinition = struct {
            name: []const u8,
            description: []const u8,
            ptr: *[][]const u8,
        };

        const SubCommandDefinition = struct {
            name: []const u8,
            cmd: CommandEnumT,
            args: Args,
        };

        pub fn init(allocator: *std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .values = std.ArrayList([]const u8).init(allocator),
                .positionals = std.ArrayList([]const u8).init(allocator),
                .flags = std.ArrayList(FlagDefinition).init(allocator),
                .args = std.ArrayList(PositionalDefinition).init(allocator),
                .subcommands = std.ArrayList(SubCommandDefinition).init(allocator),
                .command_used = null,
            };
        }

        pub fn takeover(self: *Self, T: CommandEnumT) void {
            var other = CmdArgs(T);
            self = other; // Will this work?
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
            self.args.deinit();

            for (self.subcommands.items) |*sub| {
                sub.args.deinit();
            }
            self.subcommands.deinit();

            if (self.last_error) |msg| {
                self.allocator.free(msg);
            }
        }

        pub fn printUsage(self: *Self, comptime W: type, writer: W) !void {
            if (self.last_error) |msg| {
                try writer.print("error: {s}\n\n", .{msg});
            }

            if (self.program_name) |program_name| {
                try writer.print("usage: {s} ", .{program_name});
            } else {
                try writer.print("usage: TODO ", .{});
            }

            if (self.flags.items.len > 0) {
                try writer.print("[OPTIONS]... ", .{});
            }

            for (self.args.items) |a| {
                try writer.print("{s} ", .{a.name});
            }

            if (self.positional_extras) |defn| {
                try writer.print("{s}...", .{defn.name});
            }

            try writer.print("\n", .{});

            if (self.program_summary) |program_summary| {
                var iter = reflowText(self.allocator, program_summary, max_width);
                defer iter.deinit();

                while (iter.next() catch null) |line| {
                    try writer.print("{s}\n", .{line});
                }
            }

            try writer.print("\n", .{});

            if (self.flags.items.len > 0) {
                try writer.print("OPTIONS\n", .{});
            }

            for (self.flags.items) |defn| {
                var spec_line = try specStringAlloc(self.allocator, defn.long_name, defn.short_name, defn.val_name);
                defer self.allocator.free(spec_line);
                try self.printArgUsage(spec_line, defn.description, W, writer);
            }

            try writer.print("\n", .{});

            if (self.args.items.len > 0) {
                try writer.print("ARGS\n", .{});
            }

            for (self.args.items) |arg_defn| {
                try self.printArgUsage(arg_defn.name, arg_defn.description, W, writer);
            }

            if (self.positional_extras) |defn| {
                try self.printArgUsage(defn.name, defn.description, W, writer);
            }
        }

        fn specStringAlloc(allocator: *std.mem.Allocator, long_name: ?[]const u8, short_name: ?u8, maybe_val_name: ?[]const u8) ![]const u8 {
            if (long_name == null and short_name == null) {
                unreachable;
            }

            if (maybe_val_name) |val_name| {
                if (short_name != null and long_name != null) {
                    return try std.fmt.allocPrint(allocator, "-{c}, --{s}={s}", .{ short_name.?, long_name.?, val_name });
                } else if (short_name != null) {
                    return try std.fmt.allocPrint(allocator, "-{c}={s}", .{ short_name.?, val_name });
                } else if (long_name != null) {
                    return try std.fmt.allocPrint(allocator, "    --{s}={s}", .{ long_name.?, val_name });
                }
            } else {
                if (short_name != null and long_name != null) {
                    return try std.fmt.allocPrint(allocator, "-{c}, --{s}", .{ short_name.?, long_name.? });
                } else if (short_name != null) {
                    return try std.fmt.allocPrint(allocator, "-{c}", .{short_name.?});
                } else if (long_name != null) {
                    return try std.fmt.allocPrint(allocator, "    --{s}", .{long_name.?});
                }
            }

            unreachable;
        }

        fn printArgUsage(self: *Self, arg_name: []const u8, arg_desc: []const u8, comptime W: type, writer: W) !void {
            try writer.print("   {s: <25} ", .{arg_name});

            // This is very unlikely, but...
            if (arg_name.len > 25) {
                try writer.print("\n" ++ " " ** 29, .{});
            }

            var iter = reflowText(self.allocator, arg_desc, max_width - 29);
            defer iter.deinit();

            var first_line = true;
            while (iter.next() catch null) |line| {
                if (first_line) {
                    first_line = false;
                } else {
                    try writer.print(" " ** 29, .{});
                }
                try writer.print("{s}\n", .{line});
            }
        }

        pub fn printUsageAndDie(self: *Self) noreturn {
            const stderr = std.io.getStdErr().writer();
            self.printUsage(@TypeOf(stderr), stderr) catch {};
            std.process.exit(1);
        }

        /// Configure the name for this program. This only affects "usage"
        /// output; TODO: if omitted, this will be taken from the first argv.
        pub fn programName(self: *Self, program_name: []const u8) void {
            self.program_name = program_name;
        }

        /// Configure a usage summary for this program. This is a summary
        /// paragraph that follows the program name in the help text.
        pub fn summary(self: *Self, program_summary: []const u8) void {
            self.program_summary = program_summary;
        }

        /// Configure a commandline flag, as well as provide a memory location
        /// to store the result.
        ///
        /// Note that `ptr` can refer to a boolean, signed/unsigned integer, a
        /// []const u8 string, or an optional of any of the prior types.
        ///
        /// Boolean flags have slightly different parsing rules from
        /// string/value flags.
        pub fn flag(self: *Self, comptime long_name: ?[]const u8, comptime short_name: ?u8, ptr: anytype) !void {
            try self.flagDecl(long_name, short_name, ptr, null, "");
        }

        pub fn flagDecl(self: *Self, comptime long_name: ?[]const u8, comptime short_name: ?u8, ptr: anytype, comptime val_desc: ?[]const u8, comptime description: []const u8) !void {
            if (long_name == null and short_name == null) {
                @compileError("Must provide at least one name to identify this flag");
            }

            const is_bool = @TypeOf(ptr) == *bool or @TypeOf(ptr) == *?bool;
            const conv = FlagConverter.init(ptr);

            try self.flags.append(.{
                .long_name = long_name,
                .short_name = short_name,
                .val_name = val_desc orelse conv.tag,
                .description = description,
                .parse_type = if (is_bool) .Bool else .Str,
                .val_ptr = conv,
            });
        }

        pub fn arg(self: *Self, ptr: anytype) !void {
            try self.argDecl("", ptr, "");
        }

        pub fn argDecl(self: *Self, comptime arg_name: []const u8, ptr: anytype, comptime description: []const u8) !void {
            try self.args.append(.{
                .name = arg_name, // TODO: Should we piggyback on conv.tag at all?
                .description = description,
                .conv = FlagConverter.init(ptr),
            });
        }

        /// Name and bind the non-flag commandline arguments
        pub fn extra(self: *Self, ptr: *[][]const u8) !void {
            try self.extraDecl("", ptr, "");
        }

        pub fn extraDecl(self: *Self, comptime extras_name: []const u8, ptr: *[][]const u8, comptime description: []const u8) !void {
            self.positional_extras = .{
                .name = extras_name,
                .description = description,
                .ptr = ptr,
            };
        }

        // For right now, we don't support subcommands of subcommands.
        pub fn command(self: *Self, cmd: CommandEnumT) !*Args {
            std.debug.print("YYY {s}\n", .{@tagName(cmd)});
            return try self.commandDecl(@tagName(cmd), cmd);
        }

        pub fn commandDecl(self: *Self, command_name: []const u8, cmd: CommandEnumT) !*Args {
            if (CommandEnumT == void) {
                @compileError("Subcommands not allowed against a void command type. Use `CmdArgs` to get this functionality!!");
            }
            try self.subcommands.append(SubCommandDefinition{
                .name = command_name,
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

        pub fn parse(self: *Self) !void {
            var argv = try std.process.argsAlloc(self.allocator);
            defer std.process.argsFree(self.allocator, argv);
            if (self.program_name == null) {
                const basename = try self.allocator.dupe(u8, std.fs.path.basename(argv[0]));
                errdefer self.allocator.free(basename); // TODO: Assuming this scope is just the current block

                // So it'll get free'd on deinit()
                try self.values.append(basename);
                self.program_name = self.values.items[self.values.items.len - 1];
            }
            try self.parseSlice(argv[1..]);
        }

        fn setError(self: *Self, comptime fmt: []const u8, vals: anytype) !void {
            if (self.last_error) |e| {
                self.allocator.free(e);
            }

            self.last_error = try std.fmt.allocPrint(self.allocator, fmt, vals);
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
            outer: while (idx < argv.len) : (idx += 1) {
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
                        no_more_flags = true;
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

                            for (self.subcommands.items) |*sub_cmd| {
                                if (std.mem.eql(u8, sub_cmd.name, token)) {
                                    self.command_used = sub_cmd.cmd;
                                    try sub_cmd.args.parseSlice(argv[idx + 1 ..]);
                                    break :outer;
                                }
                            } else {

                                // Nope, no subcommand, so just treat like a normal
                                // positional.
                                try self.addPositional(token); // TODO: needs test case
                                no_more_flags = true;
                            }
                        } else {
                            try self.addPositional(token); // TODO: needs test case
                            no_more_flags = true;
                        }
                    }
                }
            }

            if (self.positional_extras) |defn| {
                const num_posns = self.positionals.items.len;
                const num_args = self.args.items.len;

                if (num_args <= num_posns) {
                    defn.ptr.* = self.positionals.items[num_args..];
                } else {
                    defn.ptr.* = self.positionals.items[0..0];
                }
            }
        }

        fn addPositional(self: *Self, value: []const u8) !void {
            if (self.args.items.len > self.positionals.items.len) {
                var defn = self.args.items[self.positionals.items.len];

                const dup_value = try self.allocator.dupe(u8, value);
                errdefer self.allocator.free(dup_value);

                try defn.conv.conv_fn(defn.conv.ptr, dup_value);
                try self.positionals.append(dup_value);
            } else if (self.positional_extras) |_| {
                try self.positionals.append(try self.allocator.dupe(u8, value));
            } else {
                // We've received an arg but ran out of arg bindings, and also
                // don't have a positional_extras.ptr to bind it to.
                try self.setError("Unexpected argument \"{s}\"", .{value});
                return error.ParseError;
            }
        }

        fn fillLongValue(self: *Self, token: []const u8, remainder: [][]const u8) !Action {
            var flag_name = extractName(token);
            var defn: FlagDefinition = getFlagByLongName(self.flags.items, flag_name) orelse {
                try self.setError("Unrecognized option \"--{s}\"", .{flag_name});
                return error.ParseError;
            };

            var action_taken: Action = undefined;

            const ptr = defn.val_ptr.ptr;
            const conv_fn = defn.val_ptr.conv_fn;

            switch (defn.parse_type) {
                .Bool => {
                    action_taken = Action.ContinueToNextToken;
                    if (extractEqualValue(token)) |value| {
                        conv_fn(ptr, value) catch |err| {
                            // NOTE: zig bug--using "switch (err) {...}" doesn't compile!
                            if (err == error.ParseError) {
                                try self.setError("Can't set flag \"--{s}\" to \"{s}\"", .{ flag_name, value });
                            }
                            return err;
                        };
                    } else {
                        try conv_fn(ptr, "true"); // This should never give a parse error...
                    }
                },
                .Str => {
                    var value: []const u8 = undefined;

                    if (extractEqualValue(token)) |v| {
                        action_taken = Action.ContinueToNextToken;
                        value = v;
                    } else if (extractNextValue(remainder)) |v| {
                        action_taken = Action.SkipNextToken;
                        value = v;
                    } else {
                        try self.setError("Missing value for option \"{s}\"", .{flag_name});
                        return error.ParseError; // missing a string value
                    }

                    // We want our own, backing copy of the value...
                    const value_copy = try self.allocator.dupe(u8, value);
                    errdefer self.allocator.free(value_copy);

                    // Remember this value so we can free it on deinit()
                    try self.values.append(value_copy);
                    errdefer _ = self.values.pop();

                    // Attempt the conversion
                    conv_fn(ptr, value_copy) catch |err| {
                        // NOTE: zig bug--using "switch (err) {...}" doesn't compile!
                        if (err == error.ParseError) {
                            try self.setError("Can't set flag \"--{s}\" to \"{s}\"", .{ flag_name, value });
                        }
                        return err;
                    };
                },
            }

            return action_taken;
        }

        fn fillShortValue(self: *Self, token: []const u8, remainder: [][]const u8) !Action {
            var flag_name = token[0];
            var defn: FlagDefinition = getFlagByShortName(self.flags.items, flag_name) orelse {
                try self.setError("Unrecognized option \"-{c}\"", .{flag_name});
                return error.ParseError;
            };

            var action_taken: Action = undefined;

            const ptr = defn.val_ptr.ptr;
            const conv_fn = defn.val_ptr.conv_fn;

            switch (defn.parse_type) {
                .Bool => {
                    if (token.len > 1 and token[1] == '=') {
                        action_taken = Action.ContinueToNextToken; // didn't use any of the remainder
                        conv_fn(ptr, token[2..]) catch |err| {
                            // NOTE: zig bug--using "switch (err) {...}" doesn't compile!
                            if (err == error.ParseError) {
                                try self.setError("Can't set flag \"-{c}\" to \"{s}\"", .{ flag_name, token[2..] });
                            }
                            return err;
                        };
                    } else {
                        action_taken = Action.AdvanceOneCharacter;
                        try conv_fn(ptr, "true"); // This should never give a parse error
                    }
                },
                .Str => {
                    var value: []const u8 = undefined;

                    if (token.len > 1 and token[1] == '=') {
                        action_taken = Action.ContinueToNextToken;
                        value = token[2..];
                    } else if (token.len > 1) {
                        try self.setError("Missing value for option \"{c}\"", .{flag_name}); // TODO: test case
                        return error.ParseError;
                    } else if (extractNextValue(remainder)) |v| {
                        action_taken = Action.SkipNextToken;
                        value = v;
                    } else {
                        try self.setError("Missing value for option \"{c}\"", .{flag_name});
                        return error.ParseError; // missing a string value
                    }

                    // We want our own, backing copy of the value...
                    const value_copy = try self.allocator.dupe(u8, value);
                    errdefer self.allocator.free(value_copy);

                    // Remember this value so we can free it on deinit()
                    try self.values.append(value_copy);
                    errdefer _ = self.values.pop();

                    // Attempt the conversion
                    conv_fn(ptr, value_copy) catch |err| {
                        // NOTE: zig bug--using "switch (err) {...}" doesn't compile!
                        if (err == error.ParseError) {
                            try self.setError("Can't set flag \"-{c}\" to \"{s}\"", .{ flag_name, token[2..] });
                        }
                        return err;
                    };
                },
            }

            return action_taken;
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

        fn getFlagByLongName(flags: []FlagDefinition, flag_name: []const u8) ?FlagDefinition {
            for (flags) |defn| {
                if (defn.long_name) |long_name| {
                    if (std.mem.eql(u8, long_name, flag_name)) {
                        return defn;
                    }
                }
            }

            return null;
        }

        fn getFlagByShortName(flags: []FlagDefinition, flag_name: u8) ?FlagDefinition {
            for (flags) |defn| {
                if (defn.short_name) |short_name| {
                    if (short_name == flag_name) {
                        return defn;
                    }
                }
            }

            return null;
        }
    };
}

const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

test "anyflag" {
    var args = Args.init(std.testing.allocator);
    defer args.deinit();

    var flag0: ?bool = null;
    var flag1: bool = false;
    var flag2: ?[]const u8 = null;
    var flag3: []const u8 = "fail";
    var flag4: enum { One, Two, Three, Four } = .Three;
    var flag5: ?enum { Red, Orange, Yellow } = null;

    try args.flag("flag0", null, &flag0);
    try args.flag("flag1", null, &flag1);
    try args.flag("flag2", null, &flag2);
    try args.flag("flag3", null, &flag3);
    try args.flag("flag4", null, &flag4);
    try args.flag("flag5", null, &flag5);

    var argv = [_][]const u8{
        "--flag0=yes", "--flag1=1", "--flag2=pass", "--flag3=pass", "--flag4=two", "--flag5=YelloW",
    };
    try args.parseSlice(argv[0..]);

    expect(flag0 orelse false);
    expect(flag1);
    expectEqualStrings("pass", flag2 orelse "fail");
    expectEqualStrings("pass", flag3);
    expect(flag4 == .Two);
    expect(flag5.? == .Yellow);
}

test "Omitted flags get default values" {
    var args = Args.init(std.testing.allocator);
    defer args.deinit();

    var flag0: ?bool = null;
    var flag1: ?bool = true;
    var flag2: ?[]const u8 = null;
    var flag3: ?[]const u8 = "default";

    try args.flag("flag0", 'a', &flag0);
    try args.flag("flag1", 'b', &flag1);
    try args.flag("flag2", 'c', &flag2);
    try args.flag("flag3", 'd', &flag3);

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

    try args.flag("flag0", 'a', &flag0);
    try args.flag("flag1", 'b', &flag1);
    try args.flag("flag2", 'c', &flag2);
    try args.flag("flag3", 'd', &flag3);

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

    try args.flag("flag_equal", 'a', &flag_equal);
    try args.flag("flag_posn", 'b', &flag_posn);

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

    try args.flag("flag0", 'a', &flag0);
    try args.flag("flag1", 'b', &flag1);

    var argv = [_][]const u8{"--flag10=aaa"};
    expectError(error.ParseError, args.parseSlice(argv[0..]));

    argv = [_][]const u8{"-c"};
    expectError(error.ParseError, args.parseSlice(argv[0..]));

    argv = [_][]const u8{"-ac"};
    expectError(error.ParseError, args.parseSlice(argv[0..]));

    argv = [_][]const u8{"--flag0=not_right"};
    expectError(error.ParseError, args.parseSlice(argv[0..]));

    argv = [_][]const u8{"positional_argument"};
    expectError(error.ParseError, args.parseSlice(argv[0..]));

    argv = [_][]const u8{"-ba=anything"};
    expectError(error.ParseError, args.parseSlice(argv[0..]));
}

test "Missing string argument" {
    var args = Args.init(std.testing.allocator);
    defer args.deinit();

    var miss0: ?[]const u8 = null;
    var miss1: []const u8 = "";

    try args.flag("miss0", 'm', &miss0);
    try args.flag("miss1", 'n', &miss1);

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

    try args.flag("flag_basic", 'a', &flag_basic);
    try args.flag("flag_true", 'b', &flag_true);
    try args.flag("flag_yes", 'c', &flag_yes);
    try args.flag("flag_on", 'd', &flag_on);
    try args.flag("flag_y", 'e', &flag_y);
    try args.flag("flag_1", 'f', &flag_1);

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

    try args.flag("flag_basic", 'a', &flag_basic);
    try args.flag("flag_true", 'b', &flag_true);
    try args.flag("flag_yes", 'c', &flag_yes);
    try args.flag("flag_on", 'd', &flag_on);
    try args.flag("flag_y", 'e', &flag_y);
    try args.flag("flag_1", 'f', &flag_1);

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

test "Number support" {
    var args = Args.init(std.testing.allocator);
    defer args.deinit();

    var flag0: u1 = 0;
    var flag1: ?u2 = null;
    var flag2: u32 = 0;
    var flag3: ?u64 = null;

    var flag4: i2 = 0;
    var flag5: ?i2 = null;
    var flag6: i32 = 0;
    var flag7: ?i64 = null;

    try args.flag("flag0", null, &flag0);
    try args.flag("flag1", null, &flag1);
    try args.flag("flag2", null, &flag2);
    try args.flag("flag3", null, &flag3);

    try args.flag("flag4", null, &flag4);
    try args.flag("flag5", null, &flag5);
    try args.flag("flag6", null, &flag6);
    try args.flag("flag7", null, &flag7);

    var argv = [_][]const u8{
        "--flag0=1",  "--flag1=1", "--flag2=300000", "--flag3=300000",
        "--flag4=-1", "--flag5=1", "--flag6=-20",    "--flag7=-10000",
    };
    try args.parseSlice(argv[0..]);

    expect(flag0 == 1);
    expect(flag1.? == 1);
    expect(flag2 == 300000);
    expect(flag3.? == 300000);

    expect(flag4 == -1);
    expect(flag5.? == 1);
    expect(flag6 == -20);
    expect(flag7.? == -10000);
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

    try args.flag(null, 'a', &flag_a);
    try args.flag(null, 'b', &flag_b);
    try args.flag(null, 'c', &flag_c);

    try args.flag(null, 'd', &flag_d);
    try args.flag(null, 'e', &flag_e);

    try args.flag(null, 'f', &flag_f);
    try args.flag(null, 'g', &flag_g);

    try args.flag(null, 'h', &flag_h);
    try args.flag(null, 'i', &flag_i);

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

test "Positional functionality" {
    var args = Args.init(std.testing.allocator);
    defer args.deinit();

    var flag0: bool = false;
    var flag1: u16 = 0;
    var arg0: []const u8 = "";
    var arg1: ?u64 = null;
    var files: [][]const u8 = undefined;

    try args.flag("flag0", null, &flag0);
    try args.flag("flag1", null, &flag1);
    try args.arg(&arg0);
    try args.arg(&arg1);
    try args.extra(&files);

    var argv_missing = [_][]const u8{};
    try args.parseSlice(argv_missing[0..]);
    expect(arg0.len == 0);
    expect(arg1 == null);
    expect(files.len == 0);

    var argv = [_][]const u8{ "--flag0", "--flag1", "1234", "*.txt", "200000", "one.txt", "two.txt" };
    try args.parseSlice(argv[0..]);

    expect(flag0);
    expect(flag1 == 1234);
    expectEqualStrings("*.txt", arg0);
    expect(arg1.? == 200000);
    expect(files.len == 2);
    expectEqualStrings("one.txt", files[0]);
    expectEqualStrings("two.txt", files[1]);
}

test "Basic SubCommands" {
    const Cmd = enum {
        Move,
        Turn,
    };

    var opts = CmdArgs(Cmd).init(std.testing.allocator);
    defer opts.deinit();

    const MoveCfg = struct {
        x: i32 = 0,
        y: i32 = 0,
    };

    var move_cfg: MoveCfg = .{};

    var move_opts = try opts.commandDecl("move", Cmd.Move);
    try move_opts.flag(null, 'x', &move_cfg.x);
    try move_opts.flag(null, 'y', &move_cfg.y);

    const TurnCfg = struct {
        angle: i32 = 0,
    };

    var turn_cfg: TurnCfg = .{};

    var turn_opts = try opts.commandDecl("turn", Cmd.Turn);
    try turn_opts.flag("angle", 'a', &turn_cfg.angle);

    var argv1 = [_][]const u8{ "move", "-x=10", "-y", "20" };
    try opts.parseSlice(argv1[0..]);

    if (opts.getCommand()) |cmd| {
        switch (cmd) {
            .Move => {
                expect(move_cfg.x == 10);
                expect(move_cfg.y == 20);
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
            expect(turn_cfg.angle == 270);
        },
    } else {
        @panic("No subcommands were run!");
    }

    var args: [][]const u8 = undefined;
    try opts.extra(&args);

    var argv3 = [_][]const u8{ "no", "subcommand", "specified" };
    try opts.parseSlice(argv3[0..]);

    expect(opts.getCommand() == null);
}
