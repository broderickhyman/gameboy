const std = @import("std");
const Endian = std.builtin.Endian;
const Self = @This();
const utils = @import("../utils.zig");
const Memory = @import("../memory/Memory.zig");
const Cpu = @import("Cpu.zig");

halted: bool,
internal_counter: u16,
timer: u8,
tac: u8,
modulo: u8,
falling_edge: u1,
tac_enabled: u1,
clock_bit: u4,
overflow_counter: u4,

pub fn create(
    allocator: *const std.mem.Allocator,
) !*Self {
    const timer = try allocator.create(Self);
    timer.* = .{
        .halted = false,
        .internal_counter = 0xABD4,
        .timer = 0,
        .tac = 0xF8,
        .modulo = 0,
        .falling_edge = 0,
        .tac_enabled = 0,
        .clock_bit = 0,
        .overflow_counter = 0,
    };
    return timer;
}

pub fn handleDots(self: *Self, cpu: *Cpu, starting_dots: u8) void {
    var dots = starting_dots;
    while (dots > 0) : ({
        dots -= 1;
    }) {
        if (self.overflow_counter > 0) {
            self.overflow_counter -= 1;
            if (self.overflow_counter == 0) {
                // Set timer interrupt
                cpu.memory.requestInterrupt(2);
                // Timer modulo
                self.timer = self.modulo;
            }
        }
        const counter_result = @addWithOverflow(self.internal_counter, 1);
        self.internal_counter = counter_result[0];
        handleTimerEdge(self, cpu.memory);
    }
}

fn handleTimerEdge(self: *Self, _: *Memory) void {
    const counter_bit: u1 = @truncate(self.internal_counter >> self.clock_bit);
    const edge_value = self.tac_enabled & counter_bit;
    if (self.falling_edge == 0) {
        self.falling_edge = edge_value;
    } else if (self.falling_edge == 1 and edge_value == 0) {
        self.falling_edge = 0;
        const timer_result = @addWithOverflow(self.timer, 1);
        if (timer_result[1] == 1) {
            self.timer = 0;
            self.overflow_counter = 4;
        } else {
            self.timer = timer_result[0];
        }
    }
}

pub fn read(self: *Self, address: u16) u8 {
    return switch (address) {
        0xFF04 => return @truncate(self.internal_counter >> 8),
        0xFF05 => self.timer,
        0xFF06 => self.modulo,
        0xFF07 => self.tac,
        else => std.debug.panic("Unknown address", .{}),
    };
}

pub fn write(self: *Self, address: u16, value: u8, memory: *Memory) void {
    switch (address) {
        0xFF04 => {
            self.internal_counter = 0;
            handleTimerEdge(self, memory);
        },
        0xFF05 => {
            self.timer = value;
        },
        0xFF06 => {
            self.modulo = value;
        },
        0xFF07 => {
            self.tac = value;
            self.tac_enabled = @truncate((self.tac >> 2) & 0b1);
            self.clock_bit = switch (self.tac & 0b11) {
                1 => 3,
                2 => 5,
                3 => 7,
                else => 9,
            };
            handleTimerEdge(self, memory);
        },
        else => {},
    }
}

pub fn saveState(self: *Self, writer: *const std.fs.File.Writer) !void {
    try writer.writeInt(u8, @intFromBool(self.halted), Endian.big);
    try writer.writeInt(u16, self.internal_counter, Endian.big);
    try writer.writeInt(u8, self.timer, Endian.big);
    try writer.writeInt(u8, self.tac, Endian.big);
    try writer.writeInt(u8, self.modulo, Endian.big);
    try writer.writeInt(u8, self.falling_edge, Endian.big);
    try writer.writeInt(u8, self.tac_enabled, Endian.big);
    try writer.writeInt(u8, self.clock_bit, Endian.big);
    try writer.writeInt(u8, self.overflow_counter, Endian.big);
}

pub fn loadState(self: *Self, reader: *const std.fs.File.Reader) !void {
    self.halted = try reader.readInt(u8, Endian.big) == 1;
    self.internal_counter = @truncate(try reader.readInt(u16, Endian.big));
    self.timer = try reader.readInt(u8, Endian.big);
    self.tac = try reader.readInt(u8, Endian.big);
    self.modulo = try reader.readInt(u8, Endian.big);
    self.falling_edge = @truncate(try reader.readInt(u8, Endian.big));
    self.tac_enabled = @truncate(try reader.readInt(u8, Endian.big));
    self.clock_bit = @truncate(try reader.readInt(u8, Endian.big));
    self.overflow_counter = @truncate(try reader.readInt(u8, Endian.big));
}
