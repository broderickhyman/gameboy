const std = @import("std");
const Self = @This();

data: []u8,
start_address: u16,

pub fn create(allocator: *const std.mem.Allocator, start_address: u16, end_address: u16) !*Self {
    const rom = try allocator.create(Self);
    rom.* = .{
        .data = try allocator.alloc(u8, end_address - start_address),
        .start_address = start_address,
    };
    @memset(rom.data, 0);
    return rom;
}

pub fn read(self: *Self, address: u16) u8 {
    return self.data[address - self.start_address];
}

pub fn load(self: *Self, data: []u8) void {
    @memcpy(self.data, data);
}
