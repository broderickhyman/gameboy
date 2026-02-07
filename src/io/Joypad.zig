const std = @import("std");
const Self = @This();
const utils = @import("../utils.zig");

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
    // const val = self.read();
    // std.debug.print("Joy Write: {b:08} - {b}\n", .{ val, self.right });
}

pub fn read(self: *Self) u8 {
    var base: u8 = (0b11 << 6) | (@as(u8, self.buttons_selected) << 5) | (@as(u8, self.pad_selected) << 4);
    if (self.pad_selected == 1 and self.buttons_selected == 1) {
        base = base | 0xF;
        return base;
    }
    if (self.buttons_selected == 0) {
        base = base | (@as(u8, self.start) << 3) | (@as(u8, self.select) << 2) | (@as(u8, self.b) << 1) | self.a;
    } else if (self.pad_selected == 0) {
        base = base | (@as(u8, self.down) << 3) | (@as(u8, self.up) << 2) | (@as(u8, self.left) << 1) | self.right;
    }
    return base;
}

pub fn reset(self: *Self) void {
    self.buttons_selected = 1;
    self.pad_selected = 1;
    self.start = 1;
    self.down = 1;
    self.select = 1;
    self.up = 1;
    self.b = 1;
    self.left = 1;
    self.a = 1;
    self.right = 1;
}

pub fn saveState(self: *Self, writer: *std.fs.File.Writer) !void {
    try utils.writeInt(writer, u8, self.read(), std.builtin.Endian.big);
}

pub fn loadState(self: *Self, reader: *std.fs.File.Reader) !void {
    self.write(try utils.readInt(reader, u8, std.builtin.Endian.big));
}
