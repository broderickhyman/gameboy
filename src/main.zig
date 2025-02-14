const std = @import("std");
const Cpu = @import("Cpu.zig");
const SDL = @import("sdl2");

// /home/broderick/code/zig/gameboy/zig-out/bin/gameboy | /home/broderick/code/zig/gameboy/../gameboy-doctor/gameboy-doctor - cpu_instrs 7

pub fn main() !void {
    try SDL.init(.{
        .video = true,
        .events = true,
        .audio = true,
    });
    defer SDL.quit();

    const scale: u16 = 1;
    const scale_i: i16 = @bitCast(scale);
    const screen_width = 256 * scale;
    const screen_height = 256 * scale;

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
    var should_print = true;
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
            file_num = try std.fmt.parseInt(u4, args[1], 10);
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
        else => "",
    };
    var paths: [2][]const u8 = undefined;
    var start_pc: u16 = 0x0100;
    if (file_num == 0) {
        paths[0] = "roms/";
        start_pc = 0;
    } else {
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

    if (file_num == 0) {
        var logo_index: u16 = 0;
        while (logo_index < 0x30) : (logo_index += 1) {
            main_memory[0x104 + logo_index] = main_memory[0xA8 + logo_index];
            // std.debug.print("{X:02}\n", .{main_memory[0x104 + logo_index]});

        }
        // Checksum
        main_memory[0x14D] = 0xE7;
    }

    // zig fmt: off
    var cpu = Cpu{
        .memory = main_memory,
        .pc = start_pc,
        .counter = 1,
        .should_print = should_print,
        .should_break = debug,
        .debug = debug,
        .verbose = verbose,
        .std_out = std_out
        };
    // zig fmt: on

    // const end: u32 = 10;

    try cpu.logState();
    while (cpu.pc < cpu.memory.len) {
        // if (cpu.should_break and cpu.counter > end) {
        //     break;
        // }
        // if (cpu.should_break and cpu.counter >= 250) {
        if (cpu.should_break and cpu.pc == 0xF9) {
            // if (cpu.should_break and sp == 0xdf7e) {
            // cpu.should_print = true;
            // cpu.printFlags();
            // @breakpoint();
        }
        if (cpu.counter % 100000 == 0) {
            std.debug.print("Counter: {d}\n", .{cpu.counter});
        }
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
        if (main_memory[0xFF50] > 0) {
            std.debug.print("Disable Boot ROM\n", .{});
            // @breakpoint();
            break;
        }
    }

    // std.debug.print("\nCount: {d}\n", .{cpu.counter});
    mainLoop: while (true) {
        while (SDL.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :mainLoop,
                else => {},
            }
        }

        try renderer.setColorRGB(0xFF, 0xFF, 0xFF);
        try renderer.clear();

        try renderer.setColorRGB(0xFF, 0, 0);
        const scx: u9 = main_memory[0xFF43];
        const scy: u9 = main_memory[0xFF42];
        const width = 160 * scale;
        const height = 144 * scale;
        var x_coord: i16 = (((scx + 159) % 256) * scale_i) - width;
        var y_coord: i16 = (((scy + 143) % 256) * scale_i) - height;
        var background_viewport = SDL.Rectangle{ .x = x_coord, .y = y_coord, .width = width, .height = height };
        try renderer.drawRect(background_viewport);
        if (x_coord < 0 or y_coord < 0) {
            if (x_coord < 0) {
                x_coord += 256 * scale;
            }
            if (y_coord < 0) {
                y_coord += 256 * scale;
            }
            background_viewport = SDL.Rectangle{ .x = x_coord, .y = y_coord, .width = width, .height = height };
            try renderer.drawRect(background_viewport);
        }

        try renderer.setColorRGB(0, 0, 0);
        var x: u6 = 0;
        var y: u6 = 0;
        var row: u4 = 0;
        var chunk_index: u4 = 0;
        const address_offset: u16 = 0x9800;
        while (y < 32) : (y += 1) {
            x = 0;
            while (x < 32) : (x += 1) {
                const address = address_offset + (@as(u16, y) * 32) + x;
                const tile_map_index = main_memory[address];
                if (tile_map_index <= 0) {
                    continue;
                }
                const tile_address: u16 = @as(u16, 0x8000) + (@as(u16, tile_map_index) * 16);
                const tile_x = @as(u8, x) * 8 * scale;
                const tile_y = @as(u8, y) * 8 * scale;
                // const temp_rect = SDL.Rectangle{ .x = tile_x, .y = tile_y, .width = 8 * scale, .height = 8 * scale };
                // try renderer.drawRect(temp_rect);
                row = 0;
                while (row < 8) : (row += 1) {
                    const current_byte_address = tile_address + (row * 2);
                    const chunk_1 = main_memory[current_byte_address];
                    const chunk_2 = main_memory[current_byte_address + 1];
                    chunk_index = 0;
                    while (chunk_index < 8) : (chunk_index += 1) {
                        const shift: u3 = @truncate(7 - chunk_index);
                        const bit_1: u1 = @truncate(chunk_1 >> shift);
                        const bit_2: u1 = @truncate(chunk_2 >> shift);
                        if (bit_1 == 0 and bit_2 == 0) {
                            continue;
                        }
                        const chunk_x = tile_x + (chunk_index * scale);
                        const chunk_y = tile_y + (row * scale);
                        const rect = SDL.Rectangle{ .x = chunk_x, .y = chunk_y, .width = scale, .height = scale };
                        try renderer.fillRect(rect);
                    }
                }
            }
        }

        renderer.present();
    }
}
