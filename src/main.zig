pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const file = try std.fs.cwd().openFile("roms/dmg_boot.bin", .{});
    // const fileName = "01-special.gb";
    // const fileName = "06-ld r,r.gb";
    // const fileName = "07-jr,jp,call,ret,rst.gb";
    // const file = try std.fs.cwd().openFile("../gb-test-roms/cpu_instrs/individual/" ++ fileName, .{});
    defer file.close();

    const memory = try file.readToEndAlloc(allocator, 32 * 1024);
    defer allocator.free(memory);

    var index: u32 = 0;
    const end = 20;
    // var index: u32 = 0x100;
    // const end = 0x100 + 50;
    while (index < end and index < memory.len) {
        const opCode = memory[index];
        index += 1;
        const x = opCode >> 6;
        // const x2 = opCode & 3;
        const y = opCode >> 3 & 7;
        const z = opCode & 7;
        const p = y >> 1;
        const q = y % 2;
        const first = opCode >> 4;
        const second = opCode & 7;
        // if (second == 1) {
        // if (outputByte != 0) {
        std.debug.print("{b} - 0x{x} - {d} - {d}\n", .{ opCode, opCode, first, second });
        std.debug.print("x:{d} y:{d} z:{d} p:{d} q:{d}\n", .{ x, y, z, p, q });
        // }
        // }
    }

    // var buf_reader = std.io.bufferedReader(file.reader());
    // const reader = buf_reader.reader();

    // while (reader.readByte()) |outputByte| {
    //     if (outputByte != 0) {
    //         std.debug.print("0x{x}\n", .{outputByte});
    //     }
    // } else |err| switch (err) {
    //     error.EndOfStream => {
    //         std.debug.print("End of file\n", .{});
    //     },
    //     else => return err,
    // }
}

const std = @import("std");
