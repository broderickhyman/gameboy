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
pub fn openFileWrite(allocator: *const std.mem.Allocator, file_num: u8, file_name: []const u8) !std.fs.File {
    const file_path = getFilePath(allocator, file_num, file_name);
    defer allocator.free(file_path);
    return try std.fs.cwd().createFile(file_path, .{});
}

/// Must close the file yourself
pub fn openFileRead(allocator: *const std.mem.Allocator, file_num: u8, file_name: []const u8) std.fs.File.OpenError!std.fs.File {
    const file_path = getFilePath(allocator, file_num, file_name);
    defer allocator.free(file_path);
    return std.fs.cwd().openFile(file_path, .{});
}

pub fn getFilePath(allocator: *const std.mem.Allocator, file_num: u8, file_name: []const u8) []u8 {
    const cwd = std.fs.cwd();
    const buffer = allocator.alloc(u8, 10) catch unreachable;
    defer allocator.free(buffer);
    const directory_name = std.fmt.bufPrintZ(buffer, "{d:02}", .{file_num}) catch unreachable;
    const directory_parts = [_][]const u8{ "output", directory_name };
    const dir_path = std.fs.path.join(allocator.*, &directory_parts) catch unreachable;
    defer allocator.free(dir_path);
    cwd.makePath(dir_path) catch unreachable;
    const file_parts = [_][]const u8{ dir_path, file_name };
    const result = std.fs.path.join(allocator.*, &file_parts) catch unreachable;
    return result;
}

pub fn writeData(writer: *const std.fs.File.Writer, data: *const []u8) !void {
    const bytes_written = try writer.write(data.*);
    if (bytes_written != data.len) {
        std.debug.panic("Did not write all bytes", .{});
    }
}

pub fn readData(reader: *std.fs.File.Reader, data: *const []u8) !void {
    const bytes_read = try reader.interface.readSliceAll(data.*);
    if (bytes_read != data.len) {
        std.debug.panic("Did not read all bytes", .{});
    }
}
