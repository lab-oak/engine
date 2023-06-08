const std = @import("std");
const pkmn = @import("../pkmn.zig");

const assert = std.debug.assert;

const c = @cImport({
    @cDefine("NAPI_VERSION", "8");
    @cInclude("node_api.h");
});

export fn napi_register_module_v1(env: c.napi_env, exports: c.napi_value) c.napi_value {
    const properties = [_]c.napi_property_descriptor{
        Property.init("options", .{ .value = flags(env) }),
        Property.init("bindings", .{ .value = bindings(env) }),
    };
    assert(c.napi_define_properties(env, exports, properties.len, &properties) == c.napi_ok);
    return exports;
}

fn flags(env: c.napi_env) c.napi_value {
    var object = Object.init(env);
    const properties = [_]c.napi_property_descriptor{
        Property.init("showdown", .{ .value = Boolean.init(env, pkmn.options.showdown) }),
        Property.init("log", .{ .value = Boolean.init(env, pkmn.options.log) }),
        Property.init("chance", .{ .value = Boolean.init(env, pkmn.options.chance) }),
        Property.init("calc", .{ .value = Boolean.init(env, pkmn.options.calc) }),
    };
    assert(c.napi_define_properties(env, object, properties.len, &properties) == c.napi_ok);
    return object;
}

fn bindings(env: c.napi_env) c.napi_value {
    var array = Array.init(env, .{ .length = 1 });
    Array.set(env, array, 0, bind(env, pkmn.gen1));
    return array;
}

fn bind(env: c.napi_env, gen: anytype) c.napi_value {
    const choices_size = @intCast(u32, gen.CHOICES_SIZE);
    const logs_size = @intCast(u32, gen.LOGS_SIZE);
    var object = Object.init(env);
    const properties = [_]c.napi_property_descriptor{
        Property.init("CHOICES_SIZE", .{ .value = Number.init(env, choices_size) }),
        Property.init("LOGS_SIZE", .{ .value = Number.init(env, logs_size) }),
        Property.init("options", .{ .method = options(gen) }),
        Property.init("update", .{ .method = update(gen) }),
        Property.init("choices", .{ .method = choices(gen) }),
    };
    assert(c.napi_define_properties(env, object, properties.len, &properties) == c.napi_ok);
    return object;
}

fn Options(gen: anytype) type {
    return struct {
        const Self = @This();
        buf: [gen.LOGS_SIZE]u8,
        stream: pkmn.protocol.ByteStream,
        log: pkmn.protocol.FixedLog,
        chance: gen.Chance(pkmn.Rational(f64)),
        calc: gen.Calc,

        // FIXME expose???
        pub fn reset(self: *Self) void {
            if (pkmn.options.log) self.stream.reset();
            if (pkmn.options.chance) self.chance = .{ .probability = .{}, .actions = .{} };
            if (pkmn.options.calc) self.calc = .{};
        }
    };
}

fn options(gen: anytype) c.napi_callback {
    return struct {
        fn call(env: c.napi_env, info: c.napi_callback_info) callconv(.C) c.napi_value {
            var buf: c.napi_value = undefined;
            var bytes: ?*anyopaque;
            assert(c.napi_create_arraybuffer(env, @sizeOf(Options(gen)), &bytes, &buf) == c.napi_ok);
            assert(bytes != null);

            var aligned = @alignCast(@alignOf(*Options(gen)), bytes.?);
            var opts = @ptrCast(*Options(gen), aligned);
            if (pkmn.options.log) {
                opts.stream = .{ .buffer = &opts.buf };
                opts.log = .{ .writer = opts.stream.writer() };
            }
            if (pkmn.options.chance) {
                opts.chance = .{ .probability = .{}, .actions = .{} };
            }
            if (pkmn.options.calc) {
                opts.calc = .{};
            }

            var data: c.napi_value = undefined;
            assert(c.napi_create_dataview(env, @sizeOf(Options(gen)), buf, 0, &data) == c.napi_ok);

            var log: c.napi_value = undefined;
            assert(c.napi_create_dataview(
                env,
                gen.LOGS_SIZE,
                buf,
                @offsetOf(Options(gen), "buf"),
                &log,
            ) == c.napi_ok);

            var offset = @offsetOf(Options(gen), "chance");
            var chance = Object.init(env);
            {
                var probability: c.napi_value = undefined;
                assert(c.napi_create_dataview(
                    env,
                    @sizeOf(pkmn.Rational(f64)),
                    buf,
                    offset + @offsetOf(gen.Chance, "probability"),
                    &probability,
                ) == c.napi_ok);

                var actions: c.napi_value = undefined;
                assert(c.napi_create_dataview(
                    env,
                    @sizeOf(gen.chance.Actions),
                    buf,
                    offset + @offsetOf(gen.Chance, "actions"),
                    &actions,
                ) == c.napi_ok);

                const properties = [_]c.napi_property_descriptor{
                    Property.init("probability", .{ .value = p }),
                    Property.init("actions", .{ .value = actions }),
                };
                assert(c.napi_define_properties(env, chance, properties.len, &properties) ==
                    c.napi_ok);
            }

            offset = @offsetOf(Options(gen), "calc");
            var calc = Object.init(env);
            {
                var summaries: c.napi_value = undefined;
                assert(c.napi_create_dataview(
                    env,
                    @sizeOf(gen.calc.Summaries),
                    buf,
                    offset + @offsetOf(gen.Calc, "summaries"),
                    &summaries,
                ) == c.napi_ok);

                var overrides: c.napi_value = undefined;
                assert(c.napi_create_dataview(
                    env,
                    @sizeOf(gen.chance.Actions),
                    buf,
                    offset + @offsetOf(gen.Calc, "overrides"),
                    &overrides,
                ) == c.napi_ok);

                const properties = [_]c.napi_property_descriptor{
                    Property.init("summaries", .{ .value = sums }),
                    Property.init("overrides", .{ .value = overrides }),
                };
                assert(c.napi_define_properties(env, calc, properties.len, &properties) ==
                    c.napi_ok);
            }

            var result = Object.init(env);
            {
                const properties = [_]c.napi_property_descriptor{
                    Property.init("data", .{ .value = data }),
                    Property.init("log", .{ .value = log }),
                    Property.init("chance", .{ .value = chance }),
                    Property.init("calc", .{ .value = calc }),
                };
                assert(c.napi_define_properties(env, result, properties.len, &properties) ==
                    c.napi_ok);
            }

            return result;
        }
    }.call;
}

fn update(gen: anytype) c.napi_callback {
    return struct {
        fn call(env: c.napi_env, info: c.napi_callback_info) callconv(.C) c.napi_value {
            var argc: usize = 4;
            var argv: [4]c.napi_value = undefined;
            assert(c.napi_get_cb_info(env, info, &argc, &argv, null, null) == c.napi_ok);
            assert(argc == 4);

            var data: ?*anyopaque = undefined;
            var len: usize = 0;
            assert(c.napi_get_arraybuffer_info(env, argv[0], &data, &len) == c.napi_ok);
            assert(len == @sizeOf(gen.Battle(gen.PRNG)));
            assert(data != null);

            var aligned = @alignCast(@alignOf(*gen.Battle(gen.PRNG)), data.?);
            var battle = @ptrCast(*gen.Battle(gen.PRNG), aligned);
            const c1 = @bitCast(pkmn.Choice, Number.get(env, argv[1], u8));
            const c2 = @bitCast(pkmn.Choice, Number.get(env, argv[2], u8));

            var offset: usize = 0;
            assert(c.napi_get_dataview_info(env, argv[3], &len, &data, null, &offset) ==
                c.napi_ok);
            assert(len == @sizeOf(Options(gen)));
            asssert(offset == 0);
            assert(data != null);

            aligned = @alignCast(@alignOf(*Options(gen)), data.?);
            var opts = @ptrCast(*Options(gen), aligned);

            if (pkmn.options.chance) opts.chance.reset();
            var result = battle.update(c1, c2, opts);
            if (pkmn.options.chance) opts.chance.probability.reduce();
            if (pkmn.options.log) opts.stream.reset();

            return Number.init(env, @bitCast(u8, result));
        }
    }.call;
}

fn choices(gen: anytype) c.napi_callback {
    return struct {
        fn call(env: c.napi_env, info: c.napi_callback_info) callconv(.C) c.napi_value {
            var argc: usize = 4;
            var argv: [4]c.napi_value = undefined;
            assert(c.napi_get_cb_info(env, info, &argc, &argv, null, null) == c.napi_ok);
            assert(argc == 4);

            var data: ?*anyopaque = undefined;
            var len: usize = 0;
            assert(c.napi_get_arraybuffer_info(env, argv[0], &data, &len) == c.napi_ok);
            assert(len == @sizeOf(gen.Battle(gen.PRNG)));
            assert(data != null);

            var aligned = @alignCast(@alignOf(*gen.Battle(gen.PRNG)), data.?);
            var battle = @ptrCast(*gen.Battle(gen.PRNG), aligned);

            const player = @intToEnum(pkmn.Player, Number.get(env, argv[1], u8));
            const request = @intToEnum(pkmn.Choice.Type, Number.get(env, argv[2], u8));

            assert(c.napi_get_arraybuffer_info(env, argv[3], &data, &len) == c.napi_ok);
            assert(len == gen.CHOICES_SIZE);
            assert(data != null);

            var out = @ptrCast([*]pkmn.Choice, data.?)[0..gen.CHOICES_SIZE];
            const n = battle.choices(player, request, out);
            return Number.init(env, @bitCast(u8, n));
        }
    }.call;
}

const Array = struct {
    fn init(env: c.napi_env, o: struct { length: ?usize }) c.napi_value {
        var result: c.napi_value = undefined;
        assert(c.napi_ok == if (o.length) |n|
            c.napi_create_array_with_length(env, n, &result)
        else
            c.napi_create_array(env, &result));
        return result;
    }

    fn set(env: c.napi_env, array: c.napi_value, index: u32, value: c.napi_value) void {
        assert(c.napi_set_element(env, array, index, value) == c.napi_ok);
    }
};

const Boolean = struct {
    fn init(env: c.napi_env, value: bool) c.napi_value {
        var result: c.napi_value = undefined;
        assert(c.napi_get_boolean(env, value, &result) == c.napi_ok);
        return result;
    }

    fn get(env: c.napi_env, value: c.napi_value) bool {
        var result: bool = undefined;
        assert(napi_get_value_bool(env, value, &result) == c.napi_ok);
        return result;
    }
};

const Number = struct {
    fn init(env: c.napi_env, value: anytype) c.napi_value {
        const T = @TypeOf(value);
        var result: c.napi_value = undefined;
        assert(c.napi_ok == switch (@typeInfo(T)) {
            .Int => |info| switch (info.bits) {
                0...32 => switch (info.signedness) {
                    .signed => c.napi_create_int32(env, @as(i32, value), &result),
                    .unsigned => c.napi_create_uint32(env, @as(u32, value), &result),
                },
                33...52 => c.napi_create_int64(env, @as(i64, value), &result),
                else => @compileError("int can't be represented as JS number"),
            },
            else => @compileError("expected number, got: " ++ @typeName(T)),
        });
        return result;
    }

    fn get(env: c.napi_env, value: c.napi_value, comptime T: type) T {
        switch (@typeInfo(T)) {
            .Int => |info| switch (info.bits) {
                0...32 => switch (info.signedness) {
                    .signed => {
                        var result: i32 = undefined;
                        assert(c.napi_get_value_int32(env, value, &result) == c.napi_ok);
                        return if (info.bits == 32) result else @intCast(T, result);
                    },
                    .unsigned => {
                        var result: u32 = undefined;
                        assert(c.napi_get_value_uint32(env, value, &result) == c.napi_ok);
                        return if (info.bits == 32) result else @intCast(T, result);
                    },
                },
                33...63 => {
                    var result: i64 = undefined;
                    assert(c.napi_get_value_int64(env, value, &result) == c.napi_ok);
                    return @intCast(T, result);
                },
                else => {
                    var result: i64 = undefined;
                    assert(c.napi_get_value_int64(env, value, &result) == c.napi_ok);
                    return switch (info.signedness) {
                        .signed => @as(T, value),
                        .unsigned => if (0 <= value) @intCast(T, value) else unreachable,
                    };
                },
            },
            else => @compileError("expected number, got: " ++ @typeName(T)),
        }
    }
};

const Object = struct {
    fn init(env: c.napi_env) c.napi_value {
        var result: c.napi_value = undefined;
        assert(c.napi_create_object(env, &result) == c.napi_ok);
        return result;
    }
};

const Property = union(enum) {
    method: c.napi_callback,
    value: c.napi_value,

    fn init(comptime name: [:0]const u8, property: Property) c.napi_property_descriptor {
        return .{
            .utf8name = name,
            .name = null,
            .method = switch (property) {
                .method => |m| m,
                .value => null,
            },
            .getter = null,
            .setter = null,
            .value = switch (property) {
                .method => null,
                .value => |v| v,
            },
            .attributes = switch (property) {
                .method => c.napi_default,
                .value => c.napi_enumerable,
            },
            .data = null,
        };
    }
};
