const std = @import("std");
const Self = @This();

data: []u8,
start_address: u16,

pub fn create(allocator: *const std.mem.Allocator, start_address: u16, size: u16) !*Self {
    const ram = try allocator.create(Self);
    ram.* = .{
        .data = try allocator.alloc(u8, size),
        .start_address = start_address,
    };
    @memset(ram.data, 0);
    return ram;
}

pub fn read(self: *Self, address: u16) u8 {
    return self.data[address - self.start_address];
}

pub fn write(self: *Self, address: u16, value: u8) void {
    self.data[address - self.start_address] = value;
}

pub fn getMemoryPointer(self: *Self, address: u16) *u8 {
    return &self.data[address - self.start_address];
}
