const std = @import("std");
const Cpu = @import("cpu/Cpu.zig");
const Ppu = @import("display/PPU.zig");
const SDL = @import("sdl2");
const Memory = @import("memory/Memory.zig");
const Timer = @import("cpu/Timer.zig");
const Mapper = @import("utils.zig").Mapper;
const utils = @import("utils.zig");

// ./zig-out/bin/gameboy 2 | ../gameboy-doctor/gameboy-doctor - cpu_instrs 2

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();

    const stdout_buffer = gpa_allocator.alloc(u8, 100) catch unreachable;
    defer gpa_allocator.free(stdout_buffer);
    const std_out = std.fs.File.stdout().writer(stdout_buffer);

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
    var fast = false;
    while (args_index < args.len) : (args_index += 1) {
        const arg = args[args_index];
        if (std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--debug")) {
            debug = true;
        } else if (std.mem.eql(u8, arg, "--display")) {
            display = true;
        } else if (std.mem.eql(u8, arg, "--log")) {
            log_enabled = true;
        } else if (std.mem.eql(u8, arg, "--mem")) {
            output_memory = true;
        } else if (std.mem.eql(u8, arg, "--fast")) {
            fast = true;
        } else {
            file_num = try std.fmt.parseInt(u8, arg, 10);
        }
    }
    if (verbose) {
        should_print = true;
    }
    const path: []const u8 = switch (file_num) {
        0 => "roms/dmg_boot.bin",
        1 => "../gb-test-roms/cpu_instrs/individual/01-special.gb", // Passed
        2 => "../gb-test-roms/cpu_instrs/individual/02-interrupts.gb", // Passed using display, not cli
        3 => "../gb-test-roms/cpu_instrs/individual/03-op sp,hl.gb", // Passed
        4 => "../gb-test-roms/cpu_instrs/individual/04-op r,imm.gb", // Passed
        5 => "../gb-test-roms/cpu_instrs/individual/05-op rp.gb", // Passed
        6 => "../gb-test-roms/cpu_instrs/individual/06-ld r,r.gb", // Passed
        7 => "../gb-test-roms/cpu_instrs/individual/07-jr,jp,call,ret,rst.gb", // Passed
        8 => "../gb-test-roms/cpu_instrs/individual/08-misc instrs.gb", // Passed
        9 => "../gb-test-roms/cpu_instrs/individual/09-op r,r.gb", // Passed
        10 => "../gb-test-roms/cpu_instrs/individual/10-bit ops.gb", // Passed
        11 => "../gb-test-roms/cpu_instrs/individual/11-op a,(hl).gb", // Passed
        12 => "../gb-test-roms/cpu_instrs/cpu_instrs.gb", // Passed
        13 => "../gb-test-roms/instr_timing/instr_timing.gb", // Passed
        14 => "../gb-test-roms/interrupt_time/interrupt_time.gb", // Failed
        15 => "../gb-test-roms/mem_timing/mem_timing.gb", // Passed
        16 => "../gb-test-roms/mem_timing-2/mem_timing.gb", // Passed
        17 => "../roms/dmg-acid2.gb", // Passed
        18 => "./roms/red.gb",
        19 => "../roms/tetris.gb",
        20 => "../roms/sml.gb",
        21 => "../roms/alleyway.gb",
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/bits/mem_oam.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/bits/reg_f.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/bits/unused_hwio-GS.gb", // Failed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/instr/daa.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/interrupts/ie_push.gb", // Failed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/oam_dma/basic.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/oam_dma/reg_read.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/oam_dma/sources-GS.gb", // Failed, need MBC5
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/timer/div_write.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/timer/rapid_toggle.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/timer/tim00.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/timer/tim00_div_trigger.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/timer/tim01.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/timer/tim01_div_trigger.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/timer/tim10.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/timer/tim10_div_trigger.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/timer/tim11.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/timer/tim11_div_trigger.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/timer/tima_reload.gb", // Failed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/timer/tima_write_reloading.gb", // Failed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/timer/tma_write_reloading.gb", // Failed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/add_sp_e_timing.gb", // Crashed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/boot_div-dmgABCmgb.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/boot_hwio-dmgABCmgb.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/boot_regs-dmgABC.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/call_cc_timing.gb", // Crashed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/call_cc_timing2.gb", // Failed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/call_timing.gb", // Crashed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/call_timing2.gb", // Failed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/di_timing-GS.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/div_timing.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/ei_sequence.gb", // Failed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/ei_timing.gb", // Failed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/halt_ime0_ei.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/halt_ime0_nointr_timing.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/halt_ime1_timing.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/halt_ime1_timing2-GS.gb", // Failed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/if_ie_registers.gb", // Failed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/intr_timing.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/jp_cc_timing.gb", // Crashed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/jp_timing.gb", // Crashed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/ld_hl_sp_e_timing.gb", // Crashed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/oam_dma_restart.gb", // Passed
        22 => "../mts-20240926-1737-443f6e1/acceptance/oam_dma_start.gb", // Failed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/oam_dma_timing.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/pop_timing.gb", // Passed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/push_timing.gb", // Failed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/rapid_di_ei.gb", // Failed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/ret_cc_timing.gb", // Crashed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/ret_timing.gb", // Crashed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/reti_intr_timing.gb", // Failed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/reti_timing.gb", // Crashed
        // 22 => "../mts-20240926-1737-443f6e1/acceptance/rst_timing.gb", // Failed
        else => "",
    };
    var start_pc: u16 = 0x0100;
    if (file_num == 0) {
        start_pc = 0;
    } else if (file_num <= 11) {
        is_doctor_test = !display;
    } else {
        if (file_num < 17) {
            is_doctor_test = !display;
        } else {
            display = true;
        }
    }
    std.debug.print("Path: {s}\n", .{path});
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    // 8 MiB max rom size
    const file_data = try file.readToEndAlloc(gpa_allocator, 0x800000);
    defer gpa_allocator.free(file_data);

    const title = file_data[0x0134..0x0143];
    std.debug.print("Title: {s}\n", .{title});
    const cartridge = file_data[0x0147];
    var mapper = Mapper.None;
    var ram = false;
    switch (cartridge) {
        0x0 => {}, // ROM only
        0x1 => mapper = Mapper.MBC1,
        0x2 => {
            mapper = Mapper.MBC1;
            ram = true;
        },
        0x3 => {
            // Also battery
            mapper = Mapper.MBC1;
            ram = true;
        },
        0x13 => {
            // Also battery
            mapper = Mapper.MBC3;
            ram = true;
        },
        else => std.debug.panic("Unknown Cartridge", .{}),
    }
    std.debug.print("Cartridge: {s}, RAM: {d}\n", .{ utils.getMapperName(mapper), @intFromBool(ram) });
    const rom_value: u4 = @truncate(file_data[0x0148]);
    const bank_count = @as(u9, 1) << (rom_value + 1);
    const rom_size: u16 = @as(u16, 32) * (@as(u16, 1) << rom_value);
    std.debug.print("ROM Size: {d} KiB\n", .{rom_size});
    std.debug.print("ROM Banks: {d}\n", .{bank_count});
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

    var log_out: ?std.fs.File.Writer = null;
    if (log_enabled) {
        const log_file = try std.fs.cwd().createFile(
            "output/output.log",
            .{},
        );
        defer log_file.close();
        log_out = log_file.writer(stdout_buffer);
    }

    const timer = try Timer.create(&gpa_allocator);

    const memory = try Memory.create(&gpa_allocator, timer, file_data, bank_count, ram_size, mapper, file_num, log_out);

    const cpu = try Cpu.create(&gpa_allocator, memory, timer, start_pc, std_out, log_out);
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
        try runDisplay(cpu, file_num, &gpa_allocator, fast);
    } else {
        try runGameboyDoctor(cpu);
    }
}

fn runDisplay(cpu: *Cpu, file_num: u8, allocator: *const std.mem.Allocator, fast: bool) !void {
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

    const ppu = try Ppu.create(allocator, cpu);
    defer allocator.destroy(ppu);

    const font = try SDL.ttf.openFont("./resources/input.ttf", 48);

    var run_cpu = true;
    const smoothing = 0.9;
    const ideal_frame_time = 16740 * std.time.ns_per_us;
    var current_fps: f64 = 60.0;
    const fps_buf = try allocator.alloc(u8, 10);
    defer allocator.free(fps_buf);
    var frame_counter: u64 = 0;
    var output_timer = try std.time.Instant.now();

    const frame_texture = try SDL.createTexture(renderer, SDL.PixelFormatEnum.rgb888, SDL.Texture.Access.streaming, 160, 144);

    printData(cpu);

    mainLoop: while (true) {
        frame_counter += 1;
        const start = try std.time.Instant.now();
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
                        SDL.Keycode.d => cpu.should_print = true,
                        else => {},
                    }
                },
                .key_up => |key_up| {
                    switch (key_up.keycode) {
                        SDL.Keycode.q => break :mainLoop,
                        SDL.Keycode.@"return" => joypad.start = 1,
                        SDL.Keycode.right_shift => joypad.select = 1,
                        SDL.Keycode.s => joypad.a = 1,
                        SDL.Keycode.a => joypad.b = 1,
                        SDL.Keycode.up => joypad.up = 1,
                        SDL.Keycode.down => joypad.down = 1,
                        SDL.Keycode.left => joypad.left = 1,
                        SDL.Keycode.right => joypad.right = 1,
                        SDL.Keycode.p, SDL.Keycode.escape => cpu.paused = !cpu.paused,
                        SDL.Keycode.r => try cpu.saveRam(allocator, file_num),
                        SDL.Keycode.u => try cpu.saveState(allocator, file_num),
                        SDL.Keycode.l => try cpu.loadState(allocator, file_num),
                        else => {},
                    }
                },
                else => {},
            }
        }

        if (start.since(output_timer) > std.time.ns_per_s) {
            output_timer = try std.time.Instant.now();
            printData(cpu);
        }

        try renderer.setColor(SDL.Color.black);
        try renderer.clear();

        var pixel_data = try SDL.Texture.lock(frame_texture, SDL.Rectangle{ .x = 0, .y = 0, .height = 144, .width = 160 });

        // if (frame_counter % 100 == 0) {
        //     std.debug.print("LY: {d}\n", .{ppu.ly_ptr.*});
        // }

        if (run_cpu) {
            var frameDots: u32 = 70224;
            if (fast) {
                frameDots *= 2;
            }
            var dots: u32 = 0;
            while (dots < frameDots) {
                const current_dots: u32 = try runCpu(cpu);
                dots += current_dots;
                // if (dots > frameDots) {
                //     current_dots = dots - frameDots;
                // }
                try ppu.render(current_dots, &pixel_data);
            }
            if (cpu.memory.ram_save_requested) {
                try cpu.saveRam(allocator, file_num);
            }
            if (file_num == 0 and cpu.memory.read(0xFF50) > 0) {
                std.debug.print("Disable Boot ROM\n", .{});
                // @breakpoint();
                run_cpu = false;
            }
        }
        pixel_data.release();
        try renderer.copy(frame_texture, SDL.Rectangle{ .x = 0, .y = 0, .height = 144, .width = 160 }, null);

        if (cpu.paused) {
            const surface = try font.renderTextSolid("Paused", SDL.Color.red);
            defer surface.destroy();
            const texture = try SDL.createTextureFromSurface(renderer, surface);
            defer texture.destroy();
            const text_rect = SDL.Rectangle{ .x = 60, .y = 60, .height = 10, .width = 40 };
            try renderer.copy(texture, text_rect, null);
        }

        const fps_str = try std.fmt.bufPrintZ(fps_buf, "{d:.1}", .{current_fps});
        const surface = try font.renderTextSolid(fps_str, SDL.Color.red);
        defer surface.destroy();
        const texture = try SDL.createTextureFromSurface(renderer, surface);
        defer texture.destroy();
        const text_rect = SDL.Rectangle{ .x = 0, .y = 0, .height = 10, .width = 20 };
        // _ = text_rect;
        try renderer.copy(texture, text_rect, null);
        renderer.present();

        const end = try std.time.Instant.now();
        var elapsed = end.since(start);
        if (!fast and elapsed < ideal_frame_time) {
            const delay: u64 = @intCast(ideal_frame_time - elapsed);
            // if (frame_counter % 10 == 0) {
            // std.debug.print("Elapsed: {d}, Delay: {d}\n", .{
            //     @divTrunc(elapsed, std.time.ns_per_ms),
            //     @divTrunc(delay, std.time.ns_per_ms),
            // });
            // }
            elapsed += delay;
            std.Thread.sleep(delay);
        }
        // if (frame_counter % 10 == 0) {
        //     std.debug.print("Elapsed: {d}\n", .{@divTrunc(elapsed, std.time.ns_per_ms)});
        // }
        const new_fps = 1 / (@as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s);
        current_fps = (current_fps * smoothing) + (new_fps * (1 - smoothing));
    }
}

fn printData(_: *Cpu) void {
    // fn printData(cpu: *Cpu) void {
    // const first = cpu.memory.read(0xFF01);
    // const second = cpu.memory.read(0xFF02);
    // std.debug.print("0xFF01:{X:02} 0xFF02:{X:02}\n", .{
    //     first,
    //     second,
    // });
    // std.debug.print("Joy: {b:08}\n", .{cpu.memory.joypad.read()});
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
        _ = try runCpu(cpu);
        if (!cpu.timer.halted) {
            try cpu.logState();
        }
    }
}

fn runCpu(cpu: *Cpu) !u8 {
    if (cpu.paused) {
        return 4;
    }
    const dots = cpu.cycle();
    const serial_control = cpu.memory.read(0xFF02);
    const serial_enabled = serial_control >> 7 & 1 == 1;
    if (cpu.debug and serial_enabled) {
        // std.debug.print("Serial: {b}\n", .{serial_control});
        // const serial_value = cpu.memory.read(0xFF01);
        // if (serial_value > 0) {
        //     std.debug.print("{c}", .{serial_value});
        //     cpu.memory.write(0xFF01, 0);
        // }
        // cpu.memory.read(0xFF02) = (~(@as(u8, 1) << 7)) & serial_control;
        // std.debug.print("Serial: {b}\n", .{cpu.memory.read(0xFF02)});
    }
    if (cpu.debug) {
        // cpu.should_print = cpu.counter >= 0x000032A0 and cpu.counter <= 0x00004CF5;
    }
    if (!cpu.timer.halted) {
        try cpu.logState();
    }
    return dots;
}

fn fakeCartridge(cpu: *Cpu) void {
    var logo_index: u16 = 0;
    while (logo_index < 0x30) : (logo_index += 1) {
        cpu.memory.write(0x104 + logo_index, cpu.memory.read(0xA8 + logo_index));
    }
    // Checksum
    cpu.memory.write(0x14D, 0xE7);
}
