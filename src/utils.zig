const std = @import("std");

pub fn resetBit(pointer: *u8, shift: u3) void {
    const mask = ~(@as(u8, 1) << shift);
    pointer.* = pointer.* & mask;
}

pub fn resetBitValue(value: u8, shift: u3) u8 {
    const mask = ~(@as(u8, 1) << shift);
    return value & mask;
}

pub fn setBit(pointer: *u8, shift: u3) void {
    const mask = @as(u8, 1) << shift;
    pointer.* = pointer.* | mask;
}

pub fn setBitValue(value: u8, shift: u3) u8 {
    const mask = @as(u8, 1) << shift;
    return value | mask;
}

pub const Mapper = enum {
    None,
    MBC1,
    MBC2,
    MBC3,
};

pub fn getMapperName(mapper: Mapper) []const u8 {
    return switch (mapper) {
        Mapper.MBC1 => "MBC1",
        Mapper.MBC2 => "MBC2",
        else => "None",
    };
}

/// Must close the file yourself
pub fn openFileWrite(allocator: *const std.mem.Allocator, test_num: u8, file_name: []const u8) !std.fs.File {
    const file_path = getFilePath(allocator, test_num, null, file_name);
    defer allocator.free(file_path);
    return try std.fs.cwd().createFile(file_path, .{});
}

/// Must close the file yourself
pub fn openFileRead(allocator: *const std.mem.Allocator, test_num: u8, file_name: []const u8) std.fs.File.OpenError!std.fs.File {
    const file_path = getFilePath(allocator, test_num, null, file_name);
    defer allocator.free(file_path);
    return std.fs.cwd().openFile(file_path, .{});
}

pub fn getFilePath(allocator: *const std.mem.Allocator, test_num: u8, custom_name: ?[]const u8, file_name: []const u8) []u8 {
    const cwd = std.fs.cwd();
    var directory_name_buf: [256]u8 = undefined;
    var directory_name: []const u8 = undefined;

    if (custom_name) |name| {
        // For custom ROMs, use sanitized filename
        directory_name = sanitizeFilename(name, &directory_name_buf) catch unreachable;
    } else {
        // For test ROMs, use numeric test_num
        const buffer = allocator.alloc(u8, 10) catch unreachable;
        defer allocator.free(buffer);
        directory_name = std.fmt.bufPrintZ(buffer, "{d:02}", .{test_num}) catch unreachable;
    }

    const directory_parts = [_][]const u8{ "output", directory_name };
    const dir_path = std.fs.path.join(allocator.*, &directory_parts) catch unreachable;
    defer allocator.free(dir_path);
    cwd.makePath(dir_path) catch unreachable;
    const file_parts = [_][]const u8{ dir_path, file_name };
    const result = std.fs.path.join(allocator.*, &file_parts) catch unreachable;
    return result;
}

fn sanitizeFilename(path: []const u8, buffer: *[256]u8) ![]u8 {
    // Extract basename from path
    var basename_start: usize = 0;
    for (0..path.len) |i| {
        if (path[i] == '/' or path[i] == '\\') {
            basename_start = i + 1;
        }
    }
    var basename = path[basename_start..];

    // Remove file extension
    var basename_end = basename.len;
    for (0..basename.len) |i| {
        if (basename[i] == '.') {
            basename_end = i;
            break;
        }
    }
    basename = basename[0..basename_end];

    // Replace non-alphanumeric characters with underscore
    var result_idx: usize = 0;
    for (basename) |char| {
        if (result_idx >= 255) break;
        const c = char;
        if ((c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9')) {
            buffer[result_idx] = c;
        } else {
            buffer[result_idx] = '_';
        }
        result_idx += 1;
    }

    return buffer[0..result_idx];
}

pub fn writeData(writer: *std.fs.File.Writer, data: *const []u8) !void {
    try writer.interface.writeAll(data.*);
}

pub fn readData(reader: *std.fs.File.Reader, data: *const []u8) !void {
    try reader.interface.readSliceAll(data.*);
}

pub fn writeInt(writer: *std.fs.File.Writer, comptime T: type, value: T, endian: std.builtin.Endian) !void {
    var buf: [8]u8 = undefined;
    const size = @sizeOf(T);
    std.mem.writeInt(T, buf[0..size], value, endian);
    try writer.interface.writeAll(buf[0..size]);
}

pub fn readInt(reader: *std.fs.File.Reader, comptime T: type, endian: std.builtin.Endian) !T {
    var buf: [8]u8 = undefined;
    const size = @sizeOf(T);
    try reader.interface.readSliceAll(buf[0..size]);
    return std.mem.readInt(T, buf[0..size], endian);
}
