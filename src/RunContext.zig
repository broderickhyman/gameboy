const std = @import("std");
const Self = @This();

allocator: *const std.mem.Allocator,
dir_name: []const u8,
std_out: std.fs.File.Writer,
log_out: ?std.fs.File.Writer,

pub fn create(allocator: *const std.mem.Allocator, dir_name: []const u8, std_out: std.fs.File.Writer, log_out: ?std.fs.File.Writer) Self {
    return .{
        .allocator = allocator,
        .dir_name = dir_name,
        .std_out = std_out,
        .log_out = log_out,
    };
}
