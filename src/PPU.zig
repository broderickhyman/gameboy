const std = @import("std");
const Self = @This();
const Cpu = @import("Cpu.zig");
const SDL = @import("sdl2");

line_progress: u32,
cpu: *Cpu,
renderer: *SDL.Renderer,
line_index_pointer: *u8,

pub fn create(allocator: *const std.mem.Allocator, cpu: *Cpu, renderer: *SDL.Renderer) !*Self {
    const ppu = try allocator.create(Self);
    ppu.* = .{ .cpu = cpu, .renderer = renderer, .line_progress = 0, .line_index_pointer = cpu.getMemoryPointer(0xFF44) };
    return ppu;
}

pub fn render(self: *Self, dots: u32) !void {
    self.line_progress += dots;
    var lines: u32 = self.line_progress / 456;
    self.line_progress = self.line_progress % 456;
    while (lines > 0) : (lines -= 1) {
        self.line_index_pointer.* += 1;
        if (self.line_index_pointer.* > 153) {
            self.line_index_pointer.* = 0;
        }
        if (self.line_index_pointer.* <= 143) {
            // try renderLine(self);
        }
    }
}

fn renderLine(self: *Self) !void {
    try self.renderer.setColor(SDL.Color.black);
    try self.renderer.drawLine(0, self.line_index_pointer.*, 160, self.line_index_pointer.*);
}
