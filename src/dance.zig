const std = @import("std");

/// Get the preferred vector bit size as specified in the features list
/// Use this for functions that work better with larger block sizes
pub fn getPreferredBitSize() u16 {
    comptime var preferred: u16 = 64;

    comptime for (std.Target.current.cpu.arch.allFeaturesList()) |feature| {
        if (std.mem.eql(u8, feature.name, "prefer_128_bit") and 128 > preferred)
            preferred = 128
        else if (std.mem.eql(u8, feature.name, "prefer_256_bit") and 256 > preferred)
            preferred = 256;
    };

    return preferred;
}

test {
    _ = getPreferredBitSize();
}

pub fn BoolVectorInt(comptime len: u32) type {
    return std.meta.Int(.unsigned, len);
}

pub fn boolVectorToInt(comptime len: u32, vec: std.meta.Vector(len, bool)) BoolVectorInt(len) {
    return @ptrCast(*const BoolVectorInt(len), &vec).*;
}

pub fn findFirst(comptime T: type, comptime len: u32, vec: std.meta.Vector(len, T), value: T) std.meta.Int(.unsigned, len) {
    const I = BoolVectorInt(len);
    const mask = @splat(len, value);

    var result = vec == mask;
    return @ctz(I, boolVectorToInt(len, result));
}

test "findFirst" {
    const joe = "joe{bidenkamalah";
    var vec: std.meta.Vector(16, u8) = joe[0..16].*;
    try std.testing.expectEqual(@as(u16, 3), findFirst(u8, 16, vec, '{'));
}

pub fn countSet(comptime len: u32, vec: std.meta.Vector(len, bool)) BoolVectorInt(len) {
    return @popCount(BoolVectorInt(len), boolVectorToInt(len, vec));
}

test "countSet" {
    const joe = "joe{bidenkamalah";
    var vec: std.meta.Vector(16, u8) = joe[0..16].*;
    try std.testing.expectEqual(@as(u16, 3), countSet(16, vec == @splat(16, @as(u8, 'a'))));
}

/// Uses vector blocks to quickly determine equality
/// Runs 20x faster on my machine; larger blocks are better (use getPreferredBitSize!)
pub fn eql(comptime T: type, comptime block_size: usize, a: []const T, b: []const T) bool {
    if (a.len != b.len) return false;

    const Vector = std.meta.Vector(block_size, T);
    var index: usize = 0;

    while (index + block_size < a.len) : (index += block_size) {
        var av: Vector = a[index..][0..block_size].*;
        var bv: Vector = b[index..][0..block_size].*;

        if (!@reduce(.And, av == bv)) return false;
    } else index += block_size;

    return std.mem.eql(u8, a[index - block_size ..], b[index - block_size ..]);
}

test "eql" {
    try std.testing.expect(eql(u8, 2, "abcd", "abcd"));

    try std.testing.expect(eql(u8, 8, "abc", "abc"));
    try std.testing.expect(!eql(u8, 8, "abc", "abcd"));

    try std.testing.expect(eql(u8, 8, "abcdfty78uhgfdxsedrtyghvfxdzesr80hBRUHugyt799t8oguvhckdi9rtgvc", "abcdfty78uhgfdxsedrtyghvfxdzesr80hBRUHugyt799t8oguvhckdi9rtgvc"));
    try std.testing.expect(!eql(u8, 8, "abcdfty78uhgfdxsedrtyghvfxdzesr80hBRUHugyt799t8oguvhckdi9rtgvc", "abcdfty78uhgfdxsedrtyghvfxdzesr80hBRUHugyt799t8oguvhckdi9rtgvca"));
}

/// Uses a mask to find a char in a string; 11-20x as fast as std.mem.indexOfScalar on long strings
/// Recommended mask sizes are multiples of 8; 16 seems to perform the best on my machine
/// TODO: This can probably be optimized to not use a "subscan" at all by using more masks and @shuffle
pub fn indexOfScalar(comptime T: type, comptime block_size: usize, slice: []const T, value: T) ?usize {
    const Vector = std.meta.Vector(block_size, T);
    const mask = @splat(block_size, value);
    var index: usize = 0;

    while (index + block_size < slice.len) : (index += block_size) {
        var subslice = slice[index .. index + block_size];
        var vector: Vector = subslice[0..block_size].*;

        // Once a region is verified, subscan
        if (@reduce(.Min, vector ^ mask) == 0) {
            return index + @intCast(usize, findFirst(T, block_size, vector, value));
        }
    } else index += block_size;

    // Subscan the remaining bytes
    for (slice[index - block_size ..]) |subvalue, subindex| {
        if (subvalue == value) return (index - block_size) + subindex;
    }

    return null;
}

test "indexOfScalar" {
    var short_array = [_]u32{ 12, 18, 27, 78 };

    try std.testing.expectEqual(@as(usize, 2), indexOfScalar(u32, 8, &short_array, 27).?);

    var array = [_]u32{ 12, 18, 27, 78, 39, 0, 67, 38, 30, 12, 87, 21, 3 };

    try std.testing.expectEqual(@as(usize, 2), indexOfScalar(u32, 8, &array, 27).?);
    try std.testing.expectEqual(@as(usize, 5), indexOfScalar(u32, 8, &array, 0).?);
    try std.testing.expectEqual(@as(usize, array.len - 1), indexOfScalar(u32, 2, &array, 3).?);
    try std.testing.expectEqual(@as(usize, 8), indexOfScalar(u32, 8, &array, 30).?);

    try std.testing.expect(indexOfScalar(u32, 8, &array, 82) == null);
    try std.testing.expect(indexOfScalar(u32, 8, &array, 13) == null);
}

pub fn countScalar(comptime T: type, comptime block_size: usize, slice: []const T, value: T) usize {
    const Vector = std.meta.Vector(block_size, T);
    const mask = @splat(block_size, value);
    var index: usize = 0;
    var count: usize = 0;

    while (index + block_size < slice.len) : (index += block_size) {
        var subslice = slice[index .. index + block_size];
        var vector: Vector = subslice[0..block_size].*;

        // Once a region is verified, subscan
        if (@reduce(.Min, vector ^ mask) == 0) {
            count += countSet(block_size, vector == mask);
        }
    } else index += block_size;

    // Subscan the remaining bytes
    for (slice[index - block_size ..]) |subvalue| {
        if (subvalue == value) count += 1;
    }

    return count;
}

test "countScalar" {
    var string = "gyuijhvcfygh hfcygb";
    try std.testing.expectEqual(@as(usize, 3), countScalar(u8, 8, string, 'g'));
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

    // Our accumulator for our "multiplication mask" (radix pow 0, radix pow 1, radix pow 2, etc.)
    comptime var acc: T = 1;
    comptime var acci: usize = 0;

    // Preload the vector with our powers of radix
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

pub fn formatIntBuf(comptime T: type, comptime length: usize, buf: []u8, num: T, comptime radix: u8) void {
    std.debug.assert(buf.len == length);

    const VectorT = std.meta.Vector(length, T);

    comptime var multi_mask: VectorT = undefined;
    const add_mask = @splat(length, @intCast(T, 48));
    const mod_mask = @splat(length, @intCast(T, radix));

    // Our accumulator for our "multiplication mask" (radix pow 0, radix pow 1, radix pow 2, etc.)
    comptime var acc: T = 1;
    comptime var acci: usize = 0;

    // Preload the vector with our powers of radix
    comptime while (acci < length) : ({
        acc *= radix;
        acci += 1;
    }) {
        multi_mask[length - acci - 1] = acc;
    };

    var op_vec = @splat(length, num);
    op_vec /= multi_mask;
    op_vec %= mod_mask;
    op_vec += add_mask;

    for (buf) |*v, i| v.* = @intCast(u8, op_vec[i]);
}

/// Runs ~80x faster on my machine; larger blocks are better (use getPreferredBitSize!)
pub fn min(comptime T: type, comptime block_size: usize, slice: []const T) T {
    const Vector = std.meta.Vector(block_size, T);
    var index: usize = 1;
    var best_vec = @splat(block_size, slice[0]);

    while (index + block_size < slice.len) : (index += block_size) {
        var vector: Vector = slice[index..][0..block_size].*;
        best_vec = @minimum(best_vec, vector);
    } else index += block_size;

    var best = @reduce(.Min, best_vec);

    for (slice[index - block_size ..]) |subvalue| {
        if (subvalue < best)
            best = subvalue;
    }

    return best;
}

test "min" {
    var small_array = [_]i32{ 12, 18, 27 };
    try std.testing.expectEqual(@as(i32, 12), min(i32, 4, &small_array));

    var array = [_]i32{ 12, 18, 27, 78, 39, 0, 67, 38, 30, 12, 87, 21, 3, -89, 712, 90 };
    try std.testing.expectEqual(@as(i32, -89), min(i32, 4, &array));
}

/// Runs ~80x faster on my machine; larger blocks are better (use getPreferredBitSize!)
pub fn max(comptime T: type, comptime block_size: usize, slice: []const T) T {
    const Vector = std.meta.Vector(block_size, T);
    var index: usize = 1;
    var best_vec = @splat(block_size, slice[0]);

    while (index + block_size < slice.len) : (index += block_size) {
        var vector: Vector = slice[index..][0..block_size].*;
        best_vec = @maximum(best_vec, vector);
    } else index += block_size;

    var best = @reduce(.Max, best_vec);

    for (slice[index - block_size ..]) |subvalue| {
        if (subvalue > best)
            best = subvalue;
    }

    return best;
}

test "max" {
    var small_array = [_]i32{ 12, 18, 27 };
    try std.testing.expectEqual(@as(i32, 27), max(i32, 4, &small_array));

    var array = [_]i32{ 69, 87, 42, 420, 696969, 89, 45678987 };
    try std.testing.expectEqual(@as(i32, 45678987), max(i32, 4, &array));
}
