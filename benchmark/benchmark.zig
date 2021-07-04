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

    if (std_out != simd_out) @panic("No!");

    std.debug.print(label ++ " from std took: {d}ns | {d}ms\n", .{ std_time_took, @intToFloat(f64, std_time_took) / @intToFloat(f64, std.time.ns_per_ms) });
    std.debug.print(label ++ " from dance took: {d}ns | {d}ms\n", .{ simd_time_took, @intToFloat(f64, simd_time_took) / @intToFloat(f64, std.time.ns_per_ms) });
    std.debug.print(label ++ " speedup: {d}\n\n", .{@intToFloat(f64, std_time_took) / @intToFloat(f64, simd_time_took)});
}

pub fn main() anyerror!void {
    var timer = try std.time.Timer.start();

    try bench(&timer, "indexOfScalar", usize, struct {
        fn b() anyerror!usize {
            return std.mem.indexOfScalar(u8, bee_movie, '.').?;
        }
    }.b, struct {
        fn b() anyerror!usize {
            return dance.indexOfScalar(u8, 64, bee_movie, '.').?;
        }
    }.b);

    try bench(&timer, "min", u8, struct {
        fn b() anyerror!u8 {
            return std.mem.min(u8, bee_movie);
        }
    }.b, struct {
        fn b() anyerror!u8 {
            return dance.min(u8, 64, bee_movie);
        }
    }.b);
}
