const std = @import("std");
const Self = @This();
const RomBank = @import("RomBank.zig");
const Ram = @import("Ram.zig");
const JoyPad = @import("../io/Joypad.zig");

rom_1: *RomBank,
rom_2: *RomBank,
vram: *Ram,
external_ram: *Ram,
wram_1: *Ram,
wram_2: *Ram,
oam: *Ram,
io: *Ram,
hram: *Ram,
ie: u8,
joypad: *JoyPad,

pub fn create(allocator: *const std.mem.Allocator) !*Self {
    const mem = try allocator.create(Self);
    mem.* = .{
        .rom_1 = try RomBank.create(allocator, 0, 0x3FFF),
        .rom_2 = try RomBank.create(allocator, 0x4000, 0x7FFF),
        .vram = try Ram.create(allocator, 0x8000, 0x9FFF),
        .external_ram = try Ram.create(allocator, 0xA000, 0xBFFF),
        .wram_1 = try Ram.create(allocator, 0xC000, 0xCFFF),
        .wram_2 = try Ram.create(allocator, 0xD000, 0xDFFF),
        .oam = try Ram.create(allocator, 0xFE00, 0xFE9F),
        .io = try Ram.create(allocator, 0xFF00, 0xFF7F),
        .hram = try Ram.create(allocator, 0xFF80, 0xFFFE),
        .ie = 0,
        .joypad = try JoyPad.create(allocator),
    };
    return mem;
}

pub fn read(self: *Self, address: u16) u8 {
    // self.breakOnAddress(address);

    const result = self.read_int(address);

    // self.debugWrite(address, result);

    return result;
}

fn read_int(self: *Self, address: u16) u8 {
    if (address == 0xFF00) {
        return self.joypad.read();
    }

    return switch (address) {
        0...0x3FFF => self.rom_1.read(address),
        0x4000...0x7FFF => self.rom_2.read(address),
        0x8000...0x9FFF => self.vram.read(address),
        0xA000...0xBFFF => self.external_ram.read(address),
        0xC000...0xCFFF => self.wram_1.read(address),
        0xD000...0xDFFF => self.wram_2.read(address),
        0xFE00...0xFE9F => self.oam.read(address),
        0xFF00...0xFF7F => self.io.read(address),
        0xFF80...0xFFFE => self.hram.read(address),
        0xFFFF => self.ie,
        else => 0,
    };
}

pub fn write(self: *Self, address: u16, value: u8) void {
    switch (address) {
        0xFF46 => {
            // OAM DMA
            self.dma(value);
            return;
        },
        0xFF00 => {
            self.joypad.write(value);
            return;
        },
        0xFF04 => {
            // DIV
            self.io.write(0xFF04, 0);
            return;
        },
        else => {},
    }
    // self.breakOnAddress(address);

    switch (address) {
        0x8000...0x9FFF => self.vram.write(address, value),
        0xA000...0xBFFF => self.external_ram.write(address, value),
        0xC000...0xCFFF => self.wram_1.write(address, value),
        0xD000...0xDFFF => self.wram_2.write(address, value),
        0xFE00...0xFE9F => self.oam.write(address, value),
        0xFF00...0xFF7F => self.io.write(address, value),
        0xFF80...0xFFFE => self.hram.write(address, value),
        0xFFFF => self.ie = value,
        else => {},
    }
    // self.debugWrite(address, value);
}

fn breakOnAddress(_: *Self, address: u16) void {
    switch (address) {
        // 0xFF00 => @breakpoint(),
        // 0xFF04 => @breakpoint(),
        else => {},
    }
    if (address == 0xFF40) {
        // @breakpoint();
    }
}

fn debugWrite(self: *Self, address: u16, value: u8) void {
    if (address == 0xFF40) {
        // std.debug.print("{X}\n", .{address});
        std.debug.print("Current_value: {b:08} Value: {b:08}\n", .{ self.read_int(address), value });
    }
}

fn dma(self: *Self, address_index: u8) void {
    // @breakpoint();
    // std.debug.print("DMA: Index: {x}\n", .{address_index});
    const source_start: u16 = @as(u16, address_index) << 8;
    const destination_start: u16 = 0xFE00;
    var index: u16 = 0;
    while (index < 0x9F) : (index += 1) {
        self.write(destination_start + index, self.read(source_start + index));
    }
}
