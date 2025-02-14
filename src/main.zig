const std = @import("std");
const Cpu = @import("Cpu.zig");

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
    var should_print = true;
    var file_num: u4 = 7;
    var i: u3 = 1;
    while (i < args.len) {
        const arg = args[i];
        i += 1;
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
        while (logo_index < 0x30) {
            main_memory[0x104 + logo_index] = main_memory[0xA8 + logo_index];
            // std.debug.print("{X:02}\n", .{main_memory[0x104 + logo_index]});
            logo_index += 1;
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

    const end: u32 = 5000000;

    try cpu.logState();
    while (cpu.pc < cpu.memory.len) {
        if (cpu.should_break and cpu.counter > end) {
            break;
        }
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
        const scx: u9 = main_memory[0xFF43];
        const scy: u9 = main_memory[0xFF42];
        if (scy > 0 and cpu.counter % 100 == 0) {
            const x_coord = (scx + 159) % 256;
            const y_coord = (scy + 143) % 256;
            std.debug.print("SCX:{d:3} SCY:{d:3} X:{d:3} Y:{d:3}\n", .{ scx, scy, x_coord, y_coord });
        }
        if (main_memory[0xFF50] > 0) {
            std.debug.print("Disable Boot ROM\n", .{});
            // @breakpoint();
            break;
        }
    }
    // std.debug.print("\nCount: {d}\n", .{cpu.counter});
}
