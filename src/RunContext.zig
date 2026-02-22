const std = @import("std");
const Self = @This();

allocator: *const std.mem.Allocator,
dir_name: []const u8,

pub fn create(allocator: *const std.mem.Allocator, dir_name: []const u8) Self {
    return .{
        .allocator = allocator,
        .dir_name = dir_name,
    };
}
