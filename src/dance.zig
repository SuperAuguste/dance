const std = @import("std");

/// Uses a mask to find a char in a string; 11-20x as fast as std.mem.indexOfScalar on long strings
/// Recommended mask sizes: 8, 16, 32, 64
/// TODO: This can probably be optimized to not use a "subscan" at all by using more masks and @shuffle
pub fn indexOfScalar(comptime T: type, comptime block_size: usize, slice: []const T, value: T) ?usize {
    const Vector = std.meta.Vector(block_size, T);
    const mask = @splat(block_size, value);
    var index: usize = 0;

    // Vector scanning
    while (index < slice.len - block_size) : (index += block_size) {
        var subslice = slice[index .. index + block_size];
        var vector: Vector = subslice[0..block_size].*;

        // Once a region is verified, subscan
        if (@reduce(.Min, vector ^ mask) == 0) {
            for (subslice) |subvalue, subindex| {
                if (subvalue == value) return index + subindex;
            }

            // Impossible; the char must be in this region
            unreachable;
        }
    }

    // Subscan the remaining bytes
    for (slice[index - block_size ..]) |subvalue, subindex| {
        if (subvalue == value) return (index - block_size) + subindex;
    }

    return null;
}

test "indexOfScalar" {
    var array = [_]u32{ 12, 18, 27, 78, 39, 0, 67, 38, 30, 12, 87, 21, 3 };

    try std.testing.expectEqual(@as(usize, 2), indexOfScalar(u32, 2, &array, 27).?);
    try std.testing.expectEqual(@as(usize, 5), indexOfScalar(u32, 2, &array, 0).?);
    try std.testing.expectEqual(@as(usize, array.len - 1), indexOfScalar(u32, 2, &array, 3).?);
    try std.testing.expectEqual(@as(usize, 8), indexOfScalar(u32, 2, &array, 30).?);

    try std.testing.expect(indexOfScalar(u32, 2, &array, 82) == null);
    try std.testing.expect(indexOfScalar(u32, 2, &array, 13) == null);
}

/// Parses an integer of a comptime-known length and radix
/// Type T must be large enough to not overflow on operations (usize recommended!)
/// Input **must** have absolutely no padding or non-numeral characters for this to work properly
pub fn parseInt(comptime T: type, comptime length: usize, buf: []const u8, comptime radix: u8) T {
    std.debug.assert(buf.len == length);

    const VectorT = std.meta.Vector(length, T);

    // The size of our Vector is required to be known at compile time,
    // so let's compute our "multiplication mask" at compile time too!
    comptime var multi_mask: VectorT = undefined;
    // This "subtraction mask" Turns ASCII numbers into actual numbers
    // by subtracting 48, the ASCII value of '0'
    const sub_mask = @splat(length, @intCast(T, 48));

    // Our accumulator for our "multiplication mask" (1, 8, 64, etc.)
    comptime var acc: T = 1;
    comptime var acci: usize = 0;

    // Preload the vector with our powers of 8
    comptime while (acci < length) : ({
        acc *= radix;
        acci += 1;
    }) {
        multi_mask[length - acci - 1] = acc;
    };

    // Let's actually do the math now!
    var vec: VectorT = undefined;
    for (buf) |b, i| vec[i] = b;
    // Applies our "subtraction mask"
    vec -= sub_mask;
    // Applies our "multiplication mask"
    vec *= multi_mask;

    // Finally sum things up
    return @reduce(.Add, vec);
}

test "parseInt" {
    try std.testing.expectEqual(@as(usize, 1234), parseInt(usize, 4, "1234", 10));
    try std.testing.expectEqual(@as(usize, 78), parseInt(usize, 4, "0078", 10));

    try std.testing.expectEqual(@as(usize, 87), parseInt(usize, 3, "127", 8));

    try std.testing.expectEqual(@as(usize, 69), parseInt(usize, 7, "1000101", 2));
}

pub fn min(comptime T: type, comptime block_size: usize, slice: []const T) T {
    const Vector = std.meta.Vector(block_size, T);
    var index: usize = 1;
    var best: T = slice[0];

    while (index < slice.len - block_size) : (index += block_size) {
        var vector: Vector = slice[index .. index + block_size][0..block_size].*;
        var maybe_min = @reduce(.Min, vector);

        if (maybe_min < best)
            best = maybe_min;
    }

    for (slice[index - block_size ..]) |subvalue| {
        if (subvalue < best)
            best = subvalue;
    }

    return best;
}

test "min" {
    var array = [_]i32{ 12, 18, 27, 78, 39, 0, 67, 38, 30, 12, 87, 21, 3, -89, 712, 90 };
    try std.testing.expectEqual(@as(i32, -89), min(i32, 4, &array));
}

pub fn max(comptime T: type, comptime block_size: usize, slice: []const T) T {
    const Vector = std.meta.Vector(block_size, T);
    var index: usize = 1;
    var best: T = slice[0];

    while (index < slice.len - block_size) : (index += block_size) {
        var vector: Vector = slice[index .. index + block_size][0..block_size].*;
        var maybe_max = @reduce(.Max, vector);

        if (maybe_max > best)
            best = maybe_max;
    }

    for (slice[index - block_size ..]) |subvalue| {
        if (subvalue > best)
            best = subvalue;
    }

    return best;
}

test "max" {
    var array = [_]i32{ 69, 87, 42, 420, 696969, 89, 45678987 };
    try std.testing.expectEqual(@as(i32, 45678987), max(i32, 4, &array));
}
