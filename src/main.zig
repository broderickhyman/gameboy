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
    var file_num: u4 = 7;
    var i: u3 = 1;
    while (i < args.len) {
        const arg = args[i];
        i += 1;
        if (std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--debug")) {
            debug = true;
        } else {
            file_num = try std.fmt.parseInt(u4, args[1], 10);
        }
    }
    const file_name: []const u8 = switch (file_num) {
        0 => "dmg_boot.bin",
        1 => "01-special.gb",
        2 => "02-interrupts.gb",
        3 => "03-op sp,hl.gb",
        4 => "04-op r,imm.gb",
        5 => "05-op rp.gb",
        6 => "06-ld r,r.gb",
        7 => "07-jr,jp,call,ret,rst.gb",
        8 => "08-misc instrs.gb",
        9 => "09-op r,r.gb",
        10 => "10-bit ops.gb",
        11 => "11-op a,(hl).gb",
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

    // zig fmt: off
    var cpu = Cpu{
        .memory = main_memory,
        .pc = start_pc,
        .counter = 1,
        .should_print = verbose or !debug,
        .should_break = debug,
        .debug = debug,
        .verbose = verbose,
        .std_out = std_out
        };
    // zig fmt: on

    const end: u32 = 1600000;

    try cpu.logState();
    while (cpu.pc < cpu.memory.len) {
        if (cpu.should_break and cpu.counter > end) {
            break;
        }
        if (cpu.should_break and cpu.counter >= 1413059) {
            // if (verbose and cpu.pc == 0xdefb) {
            // if (verbose and sp == 0xdf7e) {
            cpu.should_print = true;
            cpu.printFlags();
            @breakpoint();
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
    }
    // std.debug.print("\nCount: {d}\n", .{cpu.counter});
}
