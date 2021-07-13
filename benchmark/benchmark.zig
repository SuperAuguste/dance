const std = @import("std");
const dance = @import("dance");

// TODO: Actually make this work good

const bee_movie = @embedFile("bee_movie.txt");

fn bench(timer: *std.time.Timer, comptime label: []const u8, comptime ReturnType: type, comptime std_fn: fn () anyerror!ReturnType, comptime simd_fn: fn () anyerror!ReturnType) !void {
    const iterations = 10_000;

    var std_out: ReturnType = undefined;
    var simd_out: ReturnType = undefined;
    var index: usize = 0;

    index = 0;
    while (index < iterations) : (index += 1)
        simd_out = try @call(.{ .modifier = .always_inline }, simd_fn, .{});
    timer.reset();
    index = 0;
    while (index < iterations) : (index += 1)
        simd_out = try @call(.{ .modifier = .always_inline }, simd_fn, .{});
    var simd_time_took = timer.read();

    var amogo = try std.heap.page_allocator.alloc(u8, 1024);
    try std.os.getrandom(amogo);
    std.heap.page_allocator.free(amogo);

    index = 0;
    while (index < iterations) : (index += 1)
        std_out = try @call(.{ .modifier = .always_inline }, std_fn, .{});
    timer.reset();
    index = 0;
    while (index < iterations) : (index += 1)
        std_out = try @call(.{ .modifier = .always_inline }, std_fn, .{});
    var std_time_took = timer.read();

    if (std_out != simd_out) {
        std.log.info("{d} {d}", .{ std_out, simd_out });
        @panic("No!");
    }

    std.debug.print(label ++ " from std took: {d}ns | {d}ms\n", .{ std_time_took, @intToFloat(f64, std_time_took) / @intToFloat(f64, std.time.ns_per_ms) });
    std.debug.print(label ++ " from dance took: {d}ns | {d}ms\n", .{ simd_time_took, @intToFloat(f64, simd_time_took) / @intToFloat(f64, std.time.ns_per_ms) });
    std.debug.print(label ++ " speedup: {d}\n\n", .{@intToFloat(f64, std_time_took) / @intToFloat(f64, simd_time_took)});
}

pub fn main() anyerror!void {
    std.log.info("Using preferred vector bit size of {d}\n", .{comptime dance.getPreferredBitSize()});

    var timer = try std.time.Timer.start();

    const zz = "a" ** 10000;
    const xx = "a" ** 10000;

    try bench(&timer, "eql", bool, struct {
        fn b() anyerror!bool {
            return std.mem.eql(u8, zz, xx);
        }
    }.b, struct {
        fn b() anyerror!bool {
            return dance.eql(u8, comptime dance.getPreferredBitSize(), zz, xx);
        }
    }.b);

    try bench(&timer, "indexOfScalar", usize, struct {
        fn b() anyerror!usize {
            return std.mem.indexOfScalar(u8, bee_movie, '.').?;
        }
    }.b, struct {
        fn b() anyerror!usize {
            return dance.indexOfScalar(u8, 16, bee_movie, '.').?;
        }
    }.b);

    const num = "5678987654";
    try bench(&timer, "parseInt", usize, struct {
        fn b() anyerror!usize {
            return std.fmt.parseInt(usize, num, 10);
        }
    }.b, struct {
        fn b() anyerror!usize {
            return dance.parseInt(usize, num.len, num, 10);
        }
    }.b);

    try bench(&timer, "min", u8, struct {
        fn b() anyerror!u8 {
            return std.mem.min(u8, bee_movie);
        }
    }.b, struct {
        fn b() anyerror!u8 {
            return dance.min(u8, comptime dance.getPreferredBitSize(), bee_movie);
        }
    }.b);

    try bench(&timer, "max", u8, struct {
        fn b() anyerror!u8 {
            return std.mem.max(u8, bee_movie);
        }
    }.b, struct {
        fn b() anyerror!u8 {
            return dance.max(u8, comptime dance.getPreferredBitSize(), bee_movie);
        }
    }.b);
}
