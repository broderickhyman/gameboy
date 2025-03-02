const std = @import("std");
const Self = @This();
const Cpu = @import("../cpu/Cpu.zig");
const SDL = @import("sdl2");
const utils = @import("../utils.zig");

line_progress: u32,
cpu: *Cpu,
ly_ptr: *u8,
lyc_ptr: *u8,
stat_ptr: *u8,
current_mode: u3,
lcdc_ptr: *u8,
bg_color_ptr: *u8,
obj0_color_ptr: *u8,
obj1_color_ptr: *u8,
window_triggered: bool,
window_index: u8,
bg_pixels: []Pixel,
obj_pixels: []Pixel,

pub fn create(allocator: *const std.mem.Allocator, cpu: *Cpu) !*Self {
    const ppu = try allocator.create(Self);
    const bg_pixels = try allocator.alloc(Pixel, 160);
    const obj_pixels = try allocator.alloc(Pixel, 160);
    const io_memory = cpu.memory.io;
    ppu.* = .{
        .cpu = cpu,
        .line_progress = 0,
        .stat_ptr = io_memory.getMemoryPointer(0xFF41),
        .ly_ptr = io_memory.getMemoryPointer(0xFF44),
        .lyc_ptr = io_memory.getMemoryPointer(0xFF45),
        .current_mode = 2,
        .lcdc_ptr = io_memory.getMemoryPointer(0xFF40),
        .bg_color_ptr = io_memory.getMemoryPointer(0xFF47),
        .obj0_color_ptr = io_memory.getMemoryPointer(0xFF48),
        .obj1_color_ptr = io_memory.getMemoryPointer(0xFF49),
        .window_triggered = false,
        .window_index = 0,
        .bg_pixels = bg_pixels,
        .obj_pixels = obj_pixels,
    };
    return ppu;
}

pub fn render(self: *Self, dots: u32, pixel_data: *SDL.Texture.PixelData) !void {
    const lcd_on = (self.lcdc_ptr.* >> 7) == 1;
    if (!lcd_on) {
        self.ly_ptr.* = 0;
        return;
    }
    const mode_2_length = 80;
    const mode_3_length = 226;
    var current_dots = dots;
    while (current_dots > 0) {
        self.line_progress += 1;
        current_dots -= 1;

        if (self.current_mode == 2 and self.line_progress > mode_2_length) {
            self.setPpuMode(3);
            try renderLine(self, pixel_data);
            continue;
        }
        if (self.current_mode == 3 and self.line_progress > mode_2_length + mode_3_length) {
            self.setPpuMode(0);
            self.requestInterruptIfSelected(3);
            continue;
        }
        if (self.current_mode == 0 and self.line_progress > 456) {
            self.newLine();
            if (self.ly_ptr.* <= 143) {
                self.setPpuMode(2);
                self.requestInterruptIfSelected(5);
            } else {
                self.setPpuMode(1);
                self.cpu.requestInterrupt(0);
                self.requestInterruptIfSelected(4);
            }
            self.checkLy();
            continue;
        }
        if (self.current_mode == 1 and self.line_progress > 456) {
            self.newLine();
            if (self.ly_ptr.* > 153) {
                self.setPpuMode(2);
                self.requestInterruptIfSelected(5);
                self.ly_ptr.* = 0;
                self.window_index = 0;
                self.window_triggered = false;
            }
            self.checkLy();
            continue;
        }
    }
}

fn newLine(self: *Self) void {
    const result = @addWithOverflow(self.ly_ptr.*, 1);
    self.ly_ptr.* = result[0];
    self.line_progress = 1;
    // std.debug.print("Y:{d:03} 7:{b} 6:{b} 5:{b} 4:{b} 3:{b} 2:{b} 1:{b} 0:{b}\n", .{
    //     self.ly_ptr.*,
    //     @intFromBool(self.getLcdcValue(7)),
    //     @intFromBool(self.getLcdcValue(6)),
    //     @intFromBool(self.getLcdcValue(5)),
    //     @intFromBool(self.getLcdcValue(4)),
    //     @intFromBool(self.getLcdcValue(3)),
    //     @intFromBool(self.getLcdcValue(2)),
    //     @intFromBool(self.getLcdcValue(1)),
    //     @intFromBool(self.getLcdcValue(0)),
    // });
}

fn checkLy(self: *Self) void {
    const wy = self.cpu.memory.read(0xFF4A);
    if (self.ly_ptr.* == wy) {
        self.window_triggered = true;
    }
    if (self.cpu.paused) {
        return;
    }
    if (self.ly_ptr.* == self.lyc_ptr.*) {
        utils.setBit(self.stat_ptr, 2);
        self.requestInterruptIfSelected(6);
    } else {
        utils.resetBit(self.stat_ptr, 2);
    }
}

fn requestInterruptIfSelected(self: *Self, select_num: u3) void {
    if (self.cpu.paused) {
        return;
    }
    const selected = (self.stat_ptr.* >> select_num) & 0b1 == 1;
    if (selected) {
        self.cpu.requestInterrupt(1);
    }
}

fn setPpuMode(self: *Self, mode: u2) void {
    self.current_mode = mode;
    if (self.cpu.paused) {
        return;
    }
    const mask = ~(@as(u8, 0b11));
    self.stat_ptr.* = (self.stat_ptr.* & mask) | mode;
}

fn renderLine(self: *Self, pixel_data: *SDL.Texture.PixelData) !void {
    var obj_index: usize = 0;
    while (obj_index < self.obj_pixels.len) : (obj_index += 1) {
        self.obj_pixels[obj_index].color_index = 0;
        self.obj_pixels[obj_index].palette = self.obj0_color_ptr;
        self.obj_pixels[obj_index].priority = false;
        self.obj_pixels[obj_index].obj_x = 0;
    }
    var bg_index: usize = 0;
    while (bg_index < self.bg_pixels.len) : (bg_index += 1) {
        self.bg_pixels[bg_index].color_index = 0;
        self.bg_pixels[bg_index].palette = self.bg_color_ptr;
    }

    const current_line: u10 = self.ly_ptr.*;

    const bg_window_enabled = self.getLcdcValue(0);
    const scy = self.cpu.memory.read(0xFF42);
    const scx = self.cpu.memory.read(0xFF43);
    const wx = self.cpu.memory.read(0xFF4B);
    const fetcher_y = (current_line + scy) & 255;
    const window_enabled = self.getLcdcValue(5);
    var window_rendered = false;
    const address_mode_8000 = self.getLcdcValue(4);
    var current_x: u8 = 0;
    while (current_x < 160) : (current_x += 8) {
        var adjusted_y = fetcher_y;
        var fetcher_x: u8 = undefined;
        var background_tile_address: u16 = 0x9800;
        if (self.window_triggered and window_enabled and wx <= current_x + 7) {
            window_rendered = true;
            fetcher_x = ((current_x - (wx - 7)) / 8) & 31;
            adjusted_y = self.window_index;
            if (self.getLcdcValue(6)) {
                background_tile_address = 0x9C00;
            }
        } else {
            fetcher_x = ((scx / 8) + (current_x / 8)) & 31;
            if (self.getLcdcValue(3)) {
                background_tile_address = 0x9C00;
            }
        }

        const tile_map_y = adjusted_y / 8;
        const tile_index_address: u16 = background_tile_address + (@as(u16, tile_map_y) * 32) + fetcher_x;
        const tile_map_index = self.cpu.memory.read(tile_index_address);
        var tile_address: u16 = undefined;
        if (address_mode_8000) {
            tile_address = @as(u16, 0x8000) + (@as(u16, tile_map_index) * 16);
        } else {
            const tile_map_index_signed: i8 = @bitCast(tile_map_index);
            tile_address = @bitCast(@as(i16, @truncate(@as(i17, 0x9000) + (@as(i17, tile_map_index_signed) * 16))));
        }
        const inner_y = adjusted_y % 8;
        const tile_row_address = tile_address + (inner_y * 2);
        const tile_low = self.cpu.memory.read(tile_row_address);
        const tile_high = self.cpu.memory.read(tile_row_address + 1);
        var byte_index: u4 = 0;
        while (byte_index < 8) : (byte_index += 1) {
            const shift: u3 = @truncate(7 - byte_index);
            const bit_low: u1 = @truncate(tile_low >> shift);
            const bit_high: u1 = @truncate(tile_high >> shift);
            var color_index: u2 = (@as(u2, bit_high) << 1) | bit_low;
            if (!bg_window_enabled) {
                color_index = 0;
            }
            var pixel = &self.bg_pixels[current_x + byte_index];
            pixel.color_index = color_index;
            pixel.palette = self.bg_color_ptr;
            pixel.priority = false;
        }
    }
    if (window_rendered) {
        self.window_index += 1;
    }

    const obj_enable = self.getLcdcValue(1);
    if (obj_enable) {
        var object_height: u8 = undefined;
        if (self.getLcdcValue(2)) {
            object_height = 16;
        } else {
            object_height = 8;
        }
        var object_map_index: u8 = 0;
        var found: u8 = 0;
        while (object_map_index < 40 and found <= 9) : (object_map_index += 1) {
            const oam_address: u16 = @as(u16, 0xFE00) + object_map_index * 4;
            const obj_y: u10 = self.cpu.memory.read(oam_address);
            const obj_bottom = obj_y + object_height;
            if (obj_bottom > current_line + 16 and obj_y <= current_line + 16 and obj_y < 160) {
                found += 1;
                // Need u9 to handle the byte offset
                const obj_x: u9 = self.cpu.memory.read(oam_address + 1);
                if (obj_x == 0 or obj_x >= 168) {
                    // Won't be displayed
                    continue;
                }
                const obj_attributes = self.cpu.memory.read(oam_address + 3);
                const priority = (obj_attributes >> 7) & 1 == 1;
                const obj_inner_y = (current_line + 16) - obj_y;
                var tile_inner_y = obj_inner_y % 8;
                const y_flip = (obj_attributes >> 6) & 1 == 1;
                const obj_tile_index: u16 = self.cpu.memory.read(oam_address + 2);
                var tile_address: u16 = 0x8000;
                if (object_height == 8) {
                    tile_address += obj_tile_index * 16;
                } else {
                    if ((!y_flip and obj_inner_y >= 8) or (y_flip and obj_inner_y <= 7)) {
                        // Bottom
                        tile_address += (obj_tile_index | 0x01) * 16;
                    } else {
                        // Top
                        tile_address += (obj_tile_index & 0xFE) * 16;
                    }
                }
                if (y_flip) {
                    tile_inner_y = 8 - 1 - tile_inner_y;
                }
                const x_flip = (obj_attributes >> 5) & 1 == 1;
                var palette_ptr: *u8 = undefined;
                if ((obj_attributes >> 4) & 1 == 1) {
                    palette_ptr = self.obj1_color_ptr;
                } else {
                    palette_ptr = self.obj0_color_ptr;
                }
                const tile_row_address = tile_address + (tile_inner_y * 2);
                const tile_low = self.cpu.memory.read(tile_row_address);
                const tile_high = self.cpu.memory.read(tile_row_address + 1);
                var byte_index: u4 = 0;
                while (byte_index < 8) : (byte_index += 1) {
                    if (obj_x + byte_index < 8 or obj_x + byte_index >= 168) {
                        continue;
                    }
                    var pixel = &self.obj_pixels[obj_x + byte_index - 8];
                    if (pixel.obj_x > 0 and pixel.obj_x < obj_x) {
                        // Lower X has priority
                        continue;
                    }
                    if (pixel.obj_x == obj_x and pixel.color_index > 0) {
                        // Then lower OAM index has priority
                        continue;
                    }
                    var shift: u3 = undefined;
                    if (x_flip) {
                        shift = @truncate(byte_index);
                    } else {
                        shift = @truncate(7 - byte_index);
                    }
                    const bit_low: u1 = @truncate(tile_low >> shift);
                    const bit_high: u1 = @truncate(tile_high >> shift);
                    const color_index: u2 = (@as(u2, bit_high) << 1) | bit_low;
                    pixel.color_index = color_index;
                    pixel.palette = palette_ptr;
                    pixel.priority = priority;
                    pixel.obj_x = @truncate(obj_x);
                }
            }
        }
    }
    var pixel_index: u8 = 0;
    while (pixel_index < 160) : (pixel_index += 1) {
        const obj_pixel = &self.obj_pixels[pixel_index];
        const bg_pixel = &self.bg_pixels[pixel_index];
        if (obj_pixel.color_index == 0 or (obj_pixel.priority and bg_pixel.color_index > 0)) {
            try self.drawPixel(pixel_data, bg_pixel, pixel_index);
        } else {
            try self.drawPixel(pixel_data, obj_pixel, pixel_index);
        }
    }
}

fn drawPixel(self: *Self, pixel_data: *SDL.Texture.PixelData, pixel: *const Pixel, x: u8) !void {
    const color = getColor(pixel.palette, pixel.color_index);
    const index: u32 = (@as(u32, self.ly_ptr.*) * 160 * 4) + @as(u32, x) * 4;
    pixel_data.pixels[index] = color;
    pixel_data.pixels[index + 1] = color;
    pixel_data.pixels[index + 2] = color;
}

fn getColor(pointer: *u8, index: u2) u8 {
    const colors = [_]u8{ 0xFF, 0xAA, 0x55, 0x00 };
    return colors[(pointer.* >> (@as(u3, index) * 2)) & 0b11];
}

fn getLcdcValue(self: *Self, bit_num: u3) bool {
    return ((self.lcdc_ptr.* >> bit_num) & 1) == 1;
}

const Pixel = struct {
    color_index: u2,
    palette: *u8,
    priority: bool,
    obj_x: u8,
};
