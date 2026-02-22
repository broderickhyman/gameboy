const std = @import("std");
const Self = @This();

allocator: *const std.mem.Allocator,
dir_name: []const u8,
fast: bool,
std_out: std.fs.File.Writer,
log_out: ?std.fs.File.Writer,

pub fn create(allocator: *const std.mem.Allocator, dir_name: []const u8, fast: bool, std_out: std.fs.File.Writer, log_out: ?std.fs.File.Writer) Self {
    return .{
        .allocator = allocator,
        .dir_name = dir_name,
        .fast = fast,
        .std_out = std_out,
        .log_out = log_out,
    };
}
