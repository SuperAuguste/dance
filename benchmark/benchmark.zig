const std = @import("std");
const dance = @import("dance");

// TODO: Actually make this work good

pub fn main() anyerror!void {
    var beemovie = @embedFile("beemovie.txt");

    var timer = try std.time.Timer.start();

    var value1 = std.mem.indexOfScalar(u8, beemovie, '@');
    var time1 = timer.read();

    timer.reset();

    var value2 = dance.indexOfScalar(u8, 64, beemovie, '@');
    var time2 = timer.read();

    // std.debug.assert(value1 == value2);

    std.debug.print("std took: {d}\n", .{time1});
    std.debug.print("simd took: {d}", .{time2});
}
