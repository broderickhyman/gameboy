const std = @import("std");
const Cpu = @import("Cpu.zig");
const Ppu = @import("PPU.zig");
const SDL = @import("sdl2");

// ./zig-out/bin/gameboy 2 | ../gameboy-doctor/gameboy-doctor - cpu_instrs 2

pub fn main() !void {
    var buffer: [0xFFFF + 1]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const fba_allocator = fba.allocator();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();

    const std_out = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(gpa_allocator);
    defer std.process.argsFree(gpa_allocator, args);
    var verbose = false;
    var debug = false;
    var should_print = false;
    var file_num: u8 = 7;
    var args_index: u3 = 1;
    var is_doctor_test = false;
    var display = false;
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
        12 => "../roms/dmg-acid2.gb",
        13 => "../roms/red.gb",
        14 => "../gb-test-roms/cpu_instrs/cpu_instrs.gb",
        15 => "../gb-test-roms/instr_timing/instr_timing.gb", // Passed
        16 => "../gb-test-roms/interrupt_time/interrupt_time.gb",
        17 => "../gb-test-roms/mem_timing/mem_timing.gb",
        18 => "../gb-test-roms/mem_timing-2/mem_timing.gb",
        19 => "../roms/tetris.gb",
        20 => "../roms/sml.gb",
        else => "",
    };
    var paths: [2][]const u8 = undefined;
    var start_pc: u16 = 0x0100;
    if (file_num == 0) {
        paths[0] = "roms/";
        start_pc = 0;
    } else if (file_num > 11) {
        paths[0] = "";
    } else {
        is_doctor_test = !display;
        should_print = !debug and !display;
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

    const cpu = try Cpu.create(&gpa_allocator, main_memory, start_pc, std_out);
    defer gpa_allocator.destroy(cpu);

    cpu.should_print = should_print;
    cpu.debug = debug;
    cpu.verbose = verbose;
    cpu.is_doctor_test = is_doctor_test;

    if (file_num == 0) {
        fakeCartridge(cpu);
    }
    if (!is_doctor_test) {
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

        try renderer.setColor(SDL.Color.green);
        try renderer.clear();

        if (run_cpu) {
            var dots: u32 = 0;
            while (dots < 70224) {
                const current_dots = try runCpu(cpu);
                if (file_num == 0 and cpu.memory[0xFF50] > 0) {
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
        if (cpu.counter % 100000 == 0) {
            std.debug.print("Counter: {d}\n", .{cpu.counter});
        }
        if (cpu.debug and cpu.counter > 151000) {
            // cpu.should_print = true;
        }
        _ = try runCpu(cpu);
    }
}

fn runCpu(cpu: *Cpu) !u8 {
    const dots = cpu.cycle();
    if (!cpu.halted) {
        try cpu.logState();
    }
    const serial_value = cpu.memory[0xFF01];
    if (serial_value > 0) {
        std.debug.print("{c}", .{serial_value});
        cpu.memory[0xFF01] = 0;
    }
    cpu.handleTimer(dots);
    const interrupt_dots = cpu.handleInterrupts();
    cpu.handleTimer(interrupt_dots);
    return dots + interrupt_dots;
}

fn fakeCartridge(cpu: *Cpu) void {
    var logo_index: u16 = 0;
    while (logo_index < 0x30) : (logo_index += 1) {
        cpu.memory[0x104 + logo_index] = cpu.memory[0xA8 + logo_index];
    }
    // Checksum
    cpu.memory[0x14D] = 0xE7;
}
