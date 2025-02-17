const std = @import("std");
const Self = @This();
const Cpu = @import("Cpu.zig");
const SDL = @import("sdl2");
const utils = @import("utils.zig");

line_progress: u32,
cpu: *Cpu,
renderer: *SDL.Renderer,
ly_pointer: *u8,
lyc_pointer: *u8,
stat_pointer: *u8,
current_mode: u3,

pub fn create(allocator: *const std.mem.Allocator, cpu: *Cpu, renderer: *SDL.Renderer) !*Self {
    const ppu = try allocator.create(Self);
    ppu.* = .{
        .cpu = cpu,
        .renderer = renderer,
        .line_progress = 0,
        .ly_pointer = cpu.getMemoryPointer(0xFF44),
        .lyc_pointer = cpu.getMemoryPointer(0xFF45),
        .stat_pointer = cpu.getMemoryPointer(0xFF41),
        .current_mode = 2,
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
        if (self.ly_pointer.* == self.lyc_pointer.*) {
            utils.setBit(self.stat_pointer, 2);
            self.requestInterruptIfSelected(6);
        } else {
            utils.resetBit(self.stat_pointer, 2);
        }

        if (self.current_mode == 2 and self.line_progress > mode_2_length) {
            self.setPpuMode(3);
            // try renderLine(self);
            continue;
        }
        if (self.current_mode == 3 and self.line_progress > mode_2_length + mode_3_length) {
            self.setPpuMode(0);
            self.requestInterruptIfSelected(3);
            continue;
        }
        if (self.current_mode == 0 and self.line_progress > 456) {
            self.ly_pointer.* += 1;
            self.line_progress = 1;
            if (self.ly_pointer.* <= 143) {
                self.setPpuMode(2);
                self.requestInterruptIfSelected(5);
            } else {
                self.setPpuMode(1);
                self.requestInterruptIfSelected(4);
            }
            continue;
        }
        if (self.current_mode == 1 and self.line_progress > 456) {
            self.ly_pointer.* += 1;
            self.line_progress = 1;
            if (self.ly_pointer.* > 153) {
                self.setPpuMode(2);
                self.requestInterruptIfSelected(5);
                self.ly_pointer.* = 0;
            }
            continue;
        }
    }
}

fn requestInterruptIfSelected(self: *Self, select_num: u3) void {
    const selected = self.stat_pointer.* >> select_num & 0b1;
    if (selected == 1) {
        self.cpu.requestInterrupt(0);
    }
}

fn setPpuMode(self: *Self, mode: u2) void {
    self.current_mode = mode;
    const mask = ~(@as(u8, 0b11));
    self.stat_pointer.* = (self.stat_pointer.* & mask) & mode;
}

fn renderLine(self: *Self) !void {
    try self.renderer.setColor(SDL.Color.black);
    try self.renderer.drawLine(0, self.ly_pointer.*, 160, self.ly_pointer.*);
}
