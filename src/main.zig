const std = @import("std");
const Cpu = @import("cpu/Cpu.zig");
const Ppu = @import("display/PPU.zig");
const SDL = @import("sdl2");
const Memory = @import("memory/Memory.zig");

// ./zig-out/bin/gameboy 2 | ../gameboy-doctor/gameboy-doctor - cpu_instrs 2

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();

    const std_out = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(gpa_allocator);
    defer std.process.argsFree(gpa_allocator, args);
    var verbose = false;
    var debug = false;
    var log_enabled = false;
    var should_print = false;
    var file_num: u8 = 7;
    var args_index: u3 = 1;
    var is_doctor_test = false;
    var display = false;
    var output_memory = false;
    while (args_index < args.len) : (args_index += 1) {
        const arg = args[args_index];
        if (std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--debug")) {
            debug = true;
            should_print = false;
        } else if (std.mem.eql(u8, arg, "--display")) {
            display = true;
            should_print = false;
        } else if (std.mem.eql(u8, arg, "--log")) {
            log_enabled = true;
        } else if (std.mem.eql(u8, arg, "--mem")) {
            output_memory = true;
        } else {
            file_num = try std.fmt.parseInt(u8, arg, 10);
        }
    }
    if (verbose) {
        should_print = true;
    }
    const file_name: []const u8 = switch (file_num) {
        0 => "dmg_boot.bin",
        1 => "01-special.gb", // Passed
        2 => "02-interrupts.gb", // Passed using display, not cli
        3 => "03-op sp,hl.gb", // Passed
        4 => "04-op r,imm.gb", // Passed
        5 => "05-op rp.gb", // Passed
        6 => "06-ld r,r.gb", // Passed
        7 => "07-jr,jp,call,ret,rst.gb", // Passed
        8 => "08-misc instrs.gb", // Passed
        9 => "09-op r,r.gb", // Passed
        10 => "10-bit ops.gb", // Passed
        11 => "11-op a,(hl).gb", // Passed
        12 => "../gb-test-roms/cpu_instrs/cpu_instrs.gb",
        13 => "../gb-test-roms/instr_timing/instr_timing.gb", // Passed
        14 => "../gb-test-roms/interrupt_time/interrupt_time.gb",
        15 => "../gb-test-roms/mem_timing/mem_timing.gb",
        16 => "../gb-test-roms/mem_timing-2/mem_timing.gb",
        17 => "../roms/dmg-acid2.gb", // Passed
        18 => "../roms/red.gb",
        19 => "../roms/tetris.gb",
        20 => "../roms/sml.gb",
        21 => "../roms/alleyway.gb",
        else => "",
    };
    var paths: [2][]const u8 = undefined;
    var start_pc: u16 = 0x0100;
    if (file_num == 0) {
        paths[0] = "roms/";
        start_pc = 0;
    } else if (file_num <= 11) {
        output_memory = true;
        is_doctor_test = true;
        should_print = !debug and !display;
        paths[0] = "../gb-test-roms/cpu_instrs/individual/";
    } else {
        paths[0] = "";
        if (file_num < 17) {
            is_doctor_test = true;
            should_print = !debug and !display;
        } else {
            display = true;
        }
    }
    paths[1] = file_name;
    const path = try std.fs.path.join(gpa_allocator, &paths);
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    // 8 MiB max rom size
    const file_data = try file.readToEndAlloc(gpa_allocator, 0x800000);
    defer gpa_allocator.free(file_data);

    const title = file_data[0x0134..0x0143];
    std.debug.print("Title: {s}\n", .{title});
    const cartridge = file_data[0x0147];
    std.debug.print("Cartridge: {X:02}\n", .{cartridge});
    const rom_size: u16 = @as(u16, 32) * (@as(u16, 1) << @as(u4, @truncate(file_data[0x0148])));
    std.debug.print("ROM Size: {d} KiB\n", .{rom_size});
    const ram_code = file_data[0x0149];
    const ram_size: u8 = switch (ram_code) {
        0 => 0,
        2 => 8,
        3 => 32,
        4 => 128,
        5 => 64,
        else => std.debug.panic("Unknown RAM", .{}),
    };
    std.debug.print("RAM Size: {d} KiB\n", .{ram_size});

    // switch (cartridge) {
    //     0 => {}, // ROM only
    //     else => std.debug.panic("Unknown Cartridge", .{}),
    // }

    // var mem_index: usize = 0;
    // while (mem_index < 0x100) : (mem_index += 1) {
    //     std.debug.print("{X:2}\n", .{file_data[0xC300 + mem_index]});
    // }
    // @breakpoint();

    var log_out: ?std.fs.File.Writer = null;
    if (log_enabled) {
        const log_file = try std.fs.cwd().createFile(
            "output.log",
            .{},
        );
        // defer log_file.close();
        log_out = log_file.writer();
    }

    const memory = try Memory.create(&gpa_allocator);
    memory.rom_1.load(file_data[0..0x3FFF]);
    memory.rom_2.load(file_data[0x4000..0x7FFF]);

    const cpu = try Cpu.create(&gpa_allocator, memory, start_pc, std_out, log_out);
    defer gpa_allocator.destroy(cpu);

    cpu.should_print = should_print;
    cpu.debug = debug;
    cpu.verbose = verbose;
    cpu.is_doctor_test = is_doctor_test;
    cpu.output_memory = output_memory;

    if (file_num == 0) {
        fakeCartridge(cpu);
    }
    if (display) {
        try runDisplay(cpu, file_num, &gpa_allocator);
    } else {
        try runGameboyDoctor(cpu);
    }
}

fn runDisplay(cpu: *Cpu, file_num: u8, gpa_allocator: *const std.mem.Allocator) !void {
    try SDL.init(.{
        .video = true,
        .events = true,
        .audio = true,
    });
    defer SDL.quit();
    try SDL.ttf.init();
    defer SDL.ttf.quit();

    const new_scale: u16 = 5;
    const screen_width = 160 * new_scale;
    const screen_height = 144 * new_scale;

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
    try renderer.setScale(new_scale, new_scale);
    try renderer.setDrawBlendMode(SDL.BlendMode.none);

    const ppu = try Ppu.create(gpa_allocator, cpu, &renderer);
    defer gpa_allocator.destroy(ppu);

    const font = try SDL.ttf.openFont("./resources/input.ttf", 48);

    var run_cpu = true;
    const smoothing = 0.9;
    const ideal_frame_time = 16.74;
    var current_fps: f64 = 60.0;
    const fps_buf = try gpa_allocator.alloc(u8, 10);
    defer gpa_allocator.free(fps_buf);

    mainLoop: while (true) {
        const start = SDL.getPerformanceCounter();
        const joypad = cpu.memory.joypad;
        while (SDL.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :mainLoop,
                .key_down => |key_down| {
                    switch (key_down.keycode) {
                        SDL.Keycode.@"return" => joypad.start = 0,
                        SDL.Keycode.right_shift => joypad.select = 0,
                        SDL.Keycode.s => joypad.a = 0,
                        SDL.Keycode.a => joypad.b = 0,
                        SDL.Keycode.up => joypad.up = 0,
                        SDL.Keycode.down => joypad.down = 0,
                        SDL.Keycode.left => joypad.left = 0,
                        SDL.Keycode.right => joypad.right = 0,
                        else => {},
                    }
                },
                .key_up => |key_up| {
                    switch (key_up.keycode) {
                        SDL.Keycode.escape => break :mainLoop,
                        SDL.Keycode.@"return" => joypad.start = 1,
                        SDL.Keycode.right_shift => joypad.select = 1,
                        SDL.Keycode.s => joypad.a = 1,
                        SDL.Keycode.a => joypad.b = 1,
                        SDL.Keycode.up => joypad.up = 1,
                        SDL.Keycode.down => joypad.down = 1,
                        SDL.Keycode.left => joypad.left = 1,
                        SDL.Keycode.right => joypad.right = 1,
                        else => {},
                    }
                },
                else => {},
            }
        }

        try renderer.setColor(SDL.Color.black);
        try renderer.clear();

        if (run_cpu) {
            var dots: u32 = 0;
            while (dots < 70224) {
                const current_dots = try runCpu(cpu);
                if (file_num == 0 and cpu.memory.read(0xFF50) > 0) {
                    std.debug.print("Disable Boot ROM\n", .{});
                    // @breakpoint();
                    run_cpu = false;
                }
                try ppu.render(current_dots);

                dots += current_dots;
            }
        }

        var end = SDL.getPerformanceCounter();
        var elapsed = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(SDL.getPerformanceFrequency())) * 1000;
        if (elapsed <= ideal_frame_time) {
            SDL.delay(@intFromFloat(ideal_frame_time - elapsed));
        }
        end = SDL.getPerformanceCounter();
        elapsed = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(SDL.getPerformanceFrequency()));
        const new_fps = 1 / elapsed;
        current_fps = (current_fps * smoothing) + (new_fps * (1 - smoothing));

        const fps_str = try std.fmt.bufPrintZ(fps_buf, "{d:.1}", .{current_fps});
        const surface = try font.renderTextSolid(fps_str, SDL.Color.red);
        defer surface.destroy();
        const texture = try SDL.createTextureFromSurface(renderer, surface);
        defer texture.destroy();
        const text_rect = SDL.Rectangle{ .x = 0, .y = 0, .height = 10, .width = 20 };
        _ = text_rect;
        // try renderer.copy(texture, text_rect, null);
        renderer.present();
    }
}

fn renderTile(renderer: *SDL.Renderer, cpu: *Cpu, tile_index: u16, tile_x: i16, tile_y: i16) !void {
    const tile_address: u16 = @as(u16, 0x8000) + (@as(u16, tile_index) * 16);
    const colors = [_]u8{ 0xFF, 0xAA, 0x55, 0x00 };
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
            const color_index: u2 = (@as(u2, bit_2) << 1) | bit_1;
            const color = colors[color_index];
            try renderer.setColorRGB(color, color, color);
            const chunk_x = tile_x + chunk_index;
            const chunk_y = tile_y + row;
            const rect = SDL.Rectangle{ .x = chunk_x, .y = chunk_y, .width = 1, .height = 1 };
            try renderer.fillRect(rect);
        }
    }
}

fn runGameboyDoctor(cpu: *Cpu) !void {
    try cpu.logState();
    while (true) {
        // 144 = VBlank
        cpu.memory.write(0xFF44, 144);
        if (cpu.counter % 100000 == 0) {
            std.debug.print("Counter: {d}\n", .{cpu.counter});
        }
        if (cpu.debug and cpu.counter > 151000) {
            // cpu.should_print = true;
        }
        _ = try runCpu(cpu);
        if (!cpu.halted) {
            try cpu.logState();
        }
    }
}

fn runCpu(cpu: *Cpu) !u8 {
    const dots = cpu.cycle();
    const serial_control = cpu.memory.read(0xFF02);
    const serial_enabled = serial_control >> 7 & 1 == 1;
    if (cpu.is_doctor_test and serial_enabled) {
        // std.debug.print("Serial: {b}\n", .{serial_control});
        const serial_value = cpu.memory.read(0xFF01);
        if (serial_value > 0) {
            std.debug.print("{c}", .{serial_value});
            cpu.memory.write(0xFF01, 0);
        }
        // cpu.memory.read(0xFF02) = (~(@as(u8, 1) << 7)) & serial_control;
        // std.debug.print("Serial: {b}\n", .{cpu.memory.read(0xFF02)});
    }
    cpu.handleTimer(dots);
    const interrupt_dots = cpu.handleInterrupts();
    cpu.handleTimer(interrupt_dots);
    return dots + interrupt_dots;
}

fn fakeCartridge(cpu: *Cpu) void {
    var logo_index: u16 = 0;
    while (logo_index < 0x30) : (logo_index += 1) {
        cpu.memory.write(0x104 + logo_index, cpu.memory.read(0xA8 + logo_index));
    }
    // Checksum
    cpu.memory.write(0x14D, 0xE7);
}
