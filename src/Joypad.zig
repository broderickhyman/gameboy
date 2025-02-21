const std = @import("std");
const Self = @This();

buttons_selected: u1,
pad_selected: u1,
start: u1,
down: u1,
select: u1,
up: u1,
b: u1,
left: u1,
a: u1,
right: u1,

pub fn create(allocator: *const std.mem.Allocator) !*Self {
    const joypad = try allocator.create(Self);

    joypad.* = .{
        .buttons_selected = 1,
        .pad_selected = 1,
        .start = 1,
        .down = 1,
        .select = 1,
        .up = 1,
        .b = 1,
        .left = 1,
        .a = 1,
        .right = 1,
    };
    return joypad;
}

pub fn write(self: *Self, value: u8) void {
    self.buttons_selected = @truncate(value >> 5);
    self.pad_selected = @truncate(value >> 4);
}

pub fn read(self: *Self) u8 {
    var base: u8 = (@as(u8, self.buttons_selected) << 5) | (@as(u8, self.pad_selected) << 4);
    if (self.buttons_selected == 0) {
        base = base | (@as(u8, self.start) << 3) | (@as(u8, self.select) << 2) | (@as(u8, self.b) << 1) | self.a;
    }
    if (self.pad_selected == 0) {
        base = base | (@as(u8, self.down) << 3) | (@as(u8, self.up) << 2) | (@as(u8, self.left) << 1) | self.right;
    }
    if (self.pad_selected == 1 and self.buttons_selected == 1) {
        base = base | 0xF;
    }
    return base;
}

pub fn reset(self: *Self) void {
    self.start = 1;
    self.down = 1;
    self.select = 1;
    self.up = 1;
    self.b = 1;
    self.left = 1;
    self.a = 1;
    self.right = 1;
}
