const std = @import("std");
const Self = @This();

data: []u8,

pub fn create(allocator: *const std.mem.Allocator) !*Self {
    const rom = try allocator.create(Self);
    rom.* = .{
        .data = try allocator.alloc(u8, 0x4000),
    };
    @memset(rom.data, 0);
    return rom;
}

pub fn read(self: *Self, address: u16) u8 {
    return self.data[address];
}

pub fn load(self: *Self, data: []u8) void {
    @memcpy(self.data, data);
}
