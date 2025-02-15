const std = @import("std");
const Cpu = @import("Cpu.zig");
const SDL = @import("sdl2");

// /home/broderick/code/zig/gameboy/zig-out/bin/gameboy | /home/broderick/code/zig/gameboy/../gameboy-doctor/gameboy-doctor - cpu_instrs 7

pub fn main() !void {
    var buffer: [0xFFFF + 1]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const fba_allocator = fba.allocator();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();

    const std_out = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(gpa_allocator);
    defer std.process.argsFree(gpa_allocator, args);
    // std.debug.print("${s}\n", .{args});
    var verbose = false;
    var debug = false;
    var should_print = false;
    var file_num: u4 = 7;
    var args_index: u3 = 1;
    while (args_index < args.len) : (args_index += 1) {
        const arg = args[args_index];
        if (std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--debug")) {
            debug = true;
            should_print = false;
        } else {
            file_num = try std.fmt.parseInt(u4, arg, 10);
        }
    }
    if (verbose) {
        should_print = true;
    }
    const file_name: []const u8 = switch (file_num) {
        0 => "dmg_boot.bin",
        1 => "01-special.gb", // Passed
        2 => "02-interrupts.gb",
        3 => "03-op sp,hl.gb", // Passed
        4 => "04-op r,imm.gb", // Passed
        5 => "05-op rp.gb", // Passed
        6 => "06-ld r,r.gb", // Passed
        7 => "07-jr,jp,call,ret,rst.gb", // Passed
        8 => "08-misc instrs.gb", // Passed
        9 => "09-op r,r.gb", // Passed
        10 => "10-bit ops.gb", // Passed
        11 => "11-op a,(hl).gb", // Passed
        12 => "dmg-acid2.gb",
        13 => "red.gb",
        else => "",
    };
    var paths: [2][]const u8 = undefined;
    var start_pc: u16 = 0x0100;
    if (file_num == 0) {
        paths[0] = "roms/";
        start_pc = 0;
    } else if (file_num > 11) {
        paths[0] = "../roms/";
    } else {
        should_print = true;
        paths[0] = "../gb-test-roms/cpu_instrs/individual/";
    }
    paths[1] = file_name;
    const path = try std.fs.path.join(gpa_allocator, &paths);
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const main_memory = try fba_allocator.alloc(u8, 0xFFFF + 1);
    defer fba_allocator.free(main_memory);
    @memset(main_memory, 0);
    _ = try file.readAll(main_memory);

    const cpu = try gpa_allocator.create(Cpu);
    defer gpa_allocator.destroy(cpu);
    // zig fmt: off
    cpu.* = .{
        .memory = main_memory,
        .pc = start_pc,
        .counter = 1,
        .should_print = should_print,
        .debug = debug,
        .verbose = verbose,
        .std_out = std_out
        };
    // zig fmt: on

    if (file_num == 0) {
        fakeCartridge(cpu);
    }
    if (file_num == 0 or file_num > 11) {
        try runDisplay(cpu, file_num);
    } else {
        try runGameboyDoctor(cpu);
    }
}

fn runDisplay(cpu: *Cpu, file_num: u4) !void {
    try SDL.init(.{
        .video = true,
        .events = true,
        .audio = true,
    });
    defer SDL.quit();

    const scale: u16 = 5;
    const scale_i: i16 = @bitCast(scale);
    // const screen_width = 256 * scale;
    // const screen_height = 256 * scale;
    const screen_width = 160 * scale;
    const screen_height = 144 * scale;

    var window = try SDL.createWindow(
        "Gameboy",
        .{ .centered = {} },
        .{ .centered = {} },
        screen_width,
        screen_height,
        .{ .vis = .shown },
    );
    defer window.destroy();

    var renderer = try SDL.createRenderer(window, null, .{ .accelerated = true });
    defer renderer.destroy();

    // Startup
    if (file_num != 0) {
        for (0..80000) |_| {
            try runCpu(cpu);
        }
    }

    var run_cpu = true;
    mainLoop: while (true) {
        const start = SDL.getPerformanceCounter();
        while (SDL.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :mainLoop,
                .key_up => |key_event| {
                    if (key_event.keycode == SDL.Keycode.escape) {
                        break :mainLoop;
                    }
                },
                else => {},
            }
        }
        for (0..200) |_| {
            if (run_cpu) {
                if (cpu.counter % 10000 == 0) {
                    std.debug.print("Counter: {d}\n", .{cpu.counter});
                }
                try runCpu(cpu);
                if (file_num == 0 and cpu.memory[0xFF50] > 0) {
                    std.debug.print("Disable Boot ROM\n", .{});
                    // @breakpoint();
                    run_cpu = false;
                }
            }
        }

        try renderer.setColorRGB(0xFF, 0xFF, 0xFF);
        try renderer.clear();

        const lcdc = cpu.memory[0xFF40];
        const lcd_on = (lcdc >> 7) == 1;
        if (lcd_on) {
            try renderer.setColorRGB(0, 0, 0);
            const scx: u9 = cpu.memory[0xFF43];
            const scy: u9 = cpu.memory[0xFF42];
            const width = 160 * scale;
            const height = 144 * scale;
            const x_coord: i16 = (((scx + 159) % 256) * scale_i) - width;
            const y_coord: i16 = (((scy + 143) % 256) * scale_i) - height;
            const x_offset = x_coord * -1;
            const y_offset = y_coord * -1;

            const address_offset: u16 = 0x9800;
            var y: u6 = 0;
            while (y < 32) : (y += 1) {
                const tile_y = y_offset + (scale_i * y * 8);
                var x: u6 = 0;
                while (x < 32) : (x += 1) {
                    const address = address_offset + (@as(u16, y) * 32) + x;
                    const tile_map_index = cpu.memory[address];
                    if (tile_map_index <= 0) {
                        continue;
                    }
                    const tile_address: u16 = @as(u16, 0x8000) + (@as(u16, tile_map_index) * 16);
                    const tile_x = x_offset + (scale_i * x * 8);
                    // const temp_rect = SDL.Rectangle{ .x = tile_x, .y = tile_y, .width = 8 * scale, .height = 8 * scale };
                    // try renderer.drawRect(temp_rect);
                    var row: u4 = 0;
                    while (row < 8) : (row += 1) {
                        const current_byte_address = tile_address + (row * 2);
                        const chunk_1 = cpu.memory[current_byte_address];
                        const chunk_2 = cpu.memory[current_byte_address + 1];
                        var chunk_index: u4 = 0;
                        while (chunk_index < 8) : (chunk_index += 1) {
                            const shift: u3 = @truncate(7 - chunk_index);
                            const bit_1: u1 = @truncate(chunk_1 >> shift);
                            const bit_2: u1 = @truncate(chunk_2 >> shift);
                            if (bit_1 == 0 and bit_2 == 0) {
                                continue;
                            }
                            const chunk_x = tile_x + (scale_i * chunk_index);
                            const chunk_y = tile_y + (scale_i * row);
                            const rect = SDL.Rectangle{ .x = chunk_x, .y = chunk_y, .width = scale, .height = scale };
                            try renderer.fillRect(rect);
                        }
                    }
                }
            }
        }

        renderer.present();
        const end = SDL.getPerformanceCounter();
        const elapsed = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(SDL.getPerformanceFrequency())) * 1000;
        if (elapsed <= 16.666) {
            SDL.delay(@intFromFloat(16.666 - elapsed));
        }
    }
}

fn runGameboyDoctor(cpu: *Cpu) !void {
    try cpu.logState();
    while (true) {
        if (cpu.counter % 100000 == 0) {
            std.debug.print("Counter: {d}\n", .{cpu.counter});
        }
        try runCpu(cpu);
    }
}

fn runCpu(cpu: *Cpu) !void {
    cpu.cycle();
    try cpu.logState();
    const serial_value = cpu.memory[0xFF01];
    if (serial_value > 0) {
        std.debug.print("{c}", .{serial_value});
        cpu.memory[0xFF01] = 0;
        if (serial_value == 'd') {
            // break;
        }
    }
}

fn fakeCartridge(cpu: *Cpu) void {
    var logo_index: u16 = 0;
    while (logo_index < 0x30) : (logo_index += 1) {
        cpu.memory[0x104 + logo_index] = cpu.memory[0xA8 + logo_index];
        // std.debug.print("{X:02}\n", .{cpu.memory[0x104 + logo_index]});
    }
    // Checksum
    cpu.memory[0x14D] = 0xE7;
}

fn renderBackgroundViewPort() void {
    // const x_offset = x_coord - (scale_i * 256);
    // const y_offset = y_coord - (scale_i * 256);
    // try renderer.setColorRGB(0xFF, 0, 0);
    // var background_viewport = SDL.Rectangle{ .x = x_coord, .y = y_coord, .width = width, .height = height };
    // try renderer.drawRect(background_viewport);
    // if (x_coord < 0 or y_coord < 0) {
    //     if (x_coord < 0) {
    //         x_coord += 256 * scale;
    //     }
    //     if (y_coord < 0) {
    //         y_coord += 256 * scale;
    //     }
    //     background_viewport = SDL.Rectangle{ .x = x_coord, .y = y_coord, .width = width, .height = height };
    //     try renderer.drawRect(background_viewport);
    // }
}
