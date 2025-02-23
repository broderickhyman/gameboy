const std = @import("std");
const Self = @This();
const RomBank = @import("RomBank.zig");
const Ram = @import("Ram.zig");
const JoyPad = @import("../io/Joypad.zig");
const Mapper = @import("../utils.zig").Mapper;
const utils = @import("../utils.zig");
const zdt = @import("zdt");

mapper: Mapper,
rom_banks: []RomBank,
rom_1: *RomBank,
rom_2: *RomBank,
selected_rom: u7,
vram: *Ram,
external_ram_banks: []Ram,
external_ram: ?*Ram,
external_ram_enabled: bool,
wram_1: *Ram,
wram_2: *Ram,
oam: *Ram,
io: *Ram,
hram: *Ram,
ie: u8,
joypad: *JoyPad,
banking_mode: u1,
rtc_register: u4,
latch_last_write: u8,
latched_time: zdt.Datetime,

pub fn create(
    allocator: *const std.mem.Allocator,
    file_data: []u8,
    bank_count: u9,
    ram_size: u8,
    mapper: Mapper,
) !*Self {
    var rom_banks = std.ArrayList(RomBank).init(allocator.*);
    var counter: u24 = 0;
    while (counter < bank_count) : (counter += 1) {
        const start: u24 = @as(u24, 0x4000) * counter;
        const end: u24 = (@as(u24, 0x4000) * (counter + 1));
        var new_rom = try RomBank.create(allocator);
        new_rom.load(file_data[start..end]);
        try rom_banks.append(new_rom.*);
    }
    var external_ram_banks = std.ArrayList(Ram).init(allocator.*);
    counter = 0;
    const ram_banks = ram_size / 8;
    while (counter < ram_banks) : (counter += 1) {
        const new_ram = try Ram.create(allocator, 0xA000, 0xBFFF);
        try external_ram_banks.append(new_ram.*);
    }
    const mem = try allocator.create(Self);
    mem.* = .{
        .mapper = mapper,
        .rom_banks = rom_banks.items,
        .rom_1 = &rom_banks.items[0],
        .rom_2 = &rom_banks.items[1],
        .selected_rom = 0,
        .vram = try Ram.create(allocator, 0x8000, 0x9FFF),
        .external_ram_banks = external_ram_banks.items,
        .external_ram = null,
        .external_ram_enabled = false,
        .wram_1 = try Ram.create(allocator, 0xC000, 0xCFFF),
        .wram_2 = try Ram.create(allocator, 0xD000, 0xDFFF),
        .oam = try Ram.create(allocator, 0xFE00, 0xFE9F),
        .io = try Ram.create(allocator, 0xFF00, 0xFF7F),
        .hram = try Ram.create(allocator, 0xFF80, 0xFFFE),
        .ie = 0,
        .joypad = try JoyPad.create(allocator),
        .banking_mode = 0,
        .rtc_register = 0,
        .latch_last_write = 0xFF,
        .latched_time = zdt.Datetime.nowUTC(),
    };
    if (external_ram_banks.items.len > 0) {
        mem.*.external_ram = &external_ram_banks.items[0];
    }
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
        0x4000...0x7FFF => self.rom_2.read(address - 0x4000),
        0x8000...0x9FFF => self.vram.read(address),
        0xA000...0xBFFF => {
            if (self.rtc_register > 0) {
                switch (self.rtc_register) {
                    8 => return self.latched_time.second,
                    9 => return self.latched_time.minute,
                    0xA => return self.latched_time.hour,
                    0xB => return @truncate(self.latched_time.dayOfYear()),
                    0xC => {
                        // TODO
                        return 0;
                    },
                    else => return 0,
                }
            } else {
                if (self.external_ram) |external_ram| {
                    return external_ram.read(address);
                }
                return 0xFF;
            }
        },
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
    if (address <= 0x7FFF) {
        switch (self.mapper) {
            Mapper.None => {},
            Mapper.MBC1 => mbc1_write(self, address, value),
            Mapper.MBC3 => mbc3_write(self, address, value),
            else => {
                std.debug.panic("Unknown mapper: {s}", .{utils.getMapperName(self.mapper)});
            },
        }
        return;
    }

    switch (address) {
        0x8000...0x9FFF => self.vram.write(address, value),
        0xA000...0xBFFF => {
            if (self.external_ram) |external_ram| {
                external_ram.write(address, value);
            }
        },
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

fn mbc1_write(self: *Self, address: u16, value: u8) void {
    switch (address) {
        0...0x1FFF => {
            const lower = value & 0b1111;
            if (lower == 0xA) {
                self.external_ram_enabled = true;
            } else {
                self.external_ram_enabled = false;
            }
        },
        0x2000...0x3FFF => {
            var lower: u5 = @as(u5, @truncate(value)) % @as(u5, @truncate(self.rom_banks.len));
            if (lower == 0) {
                lower = 1;
            }
            self.selected_rom = (self.selected_rom & 0b1100000) | lower;
            self.updateSelectedRom();
        },
        0x4000...0x5FFF => {
            if (self.banking_mode == 0) {
                return;
            }
            if (self.external_ram_banks.len == 4) {
                const lower: u2 = @truncate(value);
                self.external_ram = &self.external_ram_banks[lower];
            } else if (self.rom_banks.len >= 64) {
                const upper = @as(u2, @truncate(value));
                self.selected_rom = (self.selected_rom & 0b0011111) | upper;
                self.updateSelectedRom();
            }
        },
        0x6000...0x7FFF => self.banking_mode = @truncate(value),
        else => {},
    }
}

fn mbc3_write(self: *Self, address: u16, value: u8) void {
    switch (address) {
        0...0x1FFF => {
            const lower = value & 0b1111;
            if (lower == 0xA) {
                self.external_ram_enabled = true;
            } else {
                self.external_ram_enabled = false;
            }
        },
        0x2000...0x3FFF => {
            self.selected_rom = @truncate(value);
            if (self.selected_rom == 0) {
                self.selected_rom = 1;
            }
            self.updateSelectedRom();
        },
        0x4000...0x5FFF => {
            switch (value) {
                0...3 => {
                    self.external_ram = &self.external_ram_banks[value];
                    self.rtc_register = 0;
                },
                8...0xC => self.rtc_register = @truncate(value),
                else => {},
            }
        },
        0x6000...0x7FFF => {
            if (self.latch_last_write == 0 and value == 1) {
                self.latched_time = zdt.Datetime.nowUTC();
            }
            self.latch_last_write = value;
        },
        else => {},
    }
}

fn updateSelectedRom(self: *Self) void {
    self.rom_2 = &self.rom_banks[self.selected_rom];
    // var counter: u16 = 0;
    // while (counter < 100) : (counter += 1) {
    //     std.debug.print("Rom: {X:02}\n", .{self.rom_2.read(counter)});
    // }
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
