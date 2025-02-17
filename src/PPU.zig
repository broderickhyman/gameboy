const std = @import("std");
const Self = @This();
const Cpu = @import("Cpu.zig");
const SDL = @import("sdl2");
const utils = @import("utils.zig");

line_progress: u32,
cpu: *Cpu,
renderer: *SDL.Renderer,
ly_ptr: *u8,
lyc_ptr: *u8,
stat_ptr: *u8,
current_mode: u3,
lcdc_ptr: *u8,

pub fn create(allocator: *const std.mem.Allocator, cpu: *Cpu, renderer: *SDL.Renderer) !*Self {
    const ppu = try allocator.create(Self);
    ppu.* = .{
        .cpu = cpu,
        .renderer = renderer,
        .line_progress = 0,
        .ly_ptr = cpu.getMemoryPointer(0xFF44),
        .lyc_ptr = cpu.getMemoryPointer(0xFF45),
        .stat_ptr = cpu.getMemoryPointer(0xFF41),
        .current_mode = 2,
        .lcdc_ptr = cpu.getMemoryPointer(0xFF40),
    };
    return ppu;
}

pub fn render(self: *Self, dots: u32) !void {
    const mode_2_length = 80;
    const mode_3_length = 226;
    // const mode_0_length = 150;
    var current_dots = dots;
    while (current_dots > 0) {
        self.line_progress += 1;
        current_dots -= 1;
        if (self.ly_ptr.* == self.lyc_ptr.*) {
            utils.setBit(self.stat_ptr, 2);
            self.requestInterruptIfSelected(6);
        } else {
            utils.resetBit(self.stat_ptr, 2);
        }

        if (self.current_mode == 2 and self.line_progress > mode_2_length) {
            self.setPpuMode(3);
            try renderLine(self);
            continue;
        }
        if (self.current_mode == 3 and self.line_progress > mode_2_length + mode_3_length) {
            self.setPpuMode(0);
            self.requestInterruptIfSelected(3);
            continue;
        }
        if (self.current_mode == 0 and self.line_progress > 456) {
            self.ly_ptr.* += 1;
            self.line_progress = 1;
            if (self.ly_ptr.* <= 143) {
                self.setPpuMode(2);
                self.requestInterruptIfSelected(5);
            } else {
                self.setPpuMode(1);
                self.requestInterruptIfSelected(4);
            }
            continue;
        }
        if (self.current_mode == 1 and self.line_progress > 456) {
            self.ly_ptr.* += 1;
            self.line_progress = 1;
            if (self.ly_ptr.* > 153) {
                self.setPpuMode(2);
                self.requestInterruptIfSelected(5);
                self.ly_ptr.* = 0;
            }
            continue;
        }
    }
}

fn requestInterruptIfSelected(self: *Self, select_num: u3) void {
    const selected = self.stat_ptr.* >> select_num & 0b1;
    if (selected == 1) {
        self.cpu.requestInterrupt(0);
    }
}

fn setPpuMode(self: *Self, mode: u2) void {
    self.current_mode = mode;
    const mask = ~(@as(u8, 0b11));
    self.stat_ptr.* = (self.stat_ptr.* & mask) & mode;
}

fn renderLine(self: *Self) !void {
    const lcd_on = (self.lcdc_ptr.* >> 7) == 1;
    if (!lcd_on) {
        return;
    }
    const colors = [_]u8{ 0xFF, 0xAA, 0x55, 0x00 };
    const current_line: u16 = self.ly_ptr.*;

    const bg_window_enabled = self.getLcdcValue(0);
    if (bg_window_enabled) {
        const scx = self.cpu.memory[0xFF43];
        const scy = self.cpu.memory[0xFF42];
        const fetcher_y = (current_line + scy) & 255;
        const tile_map_y = fetcher_y / 8;
        // const window_enabled = self.getLcdcValue(5);
        // if (window_enabled) {
        //     var window_tile_address: u16 = 0x9800;
        //     if (self.getLcdcValue(6)) {
        //         window_tile_address = 0x9C00;
        //     }
        // }
        var background_tile_address: u16 = 0x9800;
        if (self.getLcdcValue(3)) {
            background_tile_address = 0x9C00;
        }
        const address_mode_8000 = self.getLcdcValue(4);
        var current_x: u8 = 0;
        while (current_x < 160) : (current_x += 8) {
            const fetcher_x = ((scx / 8) + (current_x / 8)) & 31;
            const tile_index_address: u16 = background_tile_address + (tile_map_y * 32) + fetcher_x;
            const tile_map_index = self.cpu.memory[tile_index_address];
            var tile_address: u16 = undefined;
            if (address_mode_8000) {
                tile_address = @as(u16, 0x8000) + (@as(u16, tile_map_index) * 16);
            } else {
                const tile_map_index_signed: i8 = @bitCast(tile_map_index);
                tile_address = @bitCast(@as(i16, @truncate(@as(i17, 0x9000) + tile_map_index_signed)));
            }
            const tile_y = fetcher_y % 8;
            const tile_row_address = tile_address + (tile_y * 2);
            const tile_low = self.cpu.memory[tile_row_address];
            const tile_high = self.cpu.memory[tile_row_address + 1];
            var byte_index: u4 = 0;
            while (byte_index < 8) : (byte_index += 1) {
                const shift: u3 = @truncate(7 - byte_index);
                const bit_low: u1 = @truncate(tile_low >> shift);
                const bit_high: u1 = @truncate(tile_high >> shift);
                if (bit_low == 0 and bit_high == 0) {
                    continue;
                }
                const color_index: u2 = (@as(u2, bit_high) << 1) | bit_low;
                const color = colors[color_index];
                try self.renderer.setColorRGB(color, color, color);
                try self.renderer.drawPoint(current_x + byte_index, current_line);
            }
        }
    }

    const obj_enable = self.getLcdcValue(1);
    if (obj_enable) {
        const obj_double_size = self.getLcdcValue(2);
        _ = obj_double_size;
    }
}

fn getLcdcValue(self: *Self, bit_num: u3) bool {
    return ((self.lcdc_ptr.* >> bit_num) & 1) == 1;
}
