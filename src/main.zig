pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    // const allocator = gpa.allocator();

    // const file = try std.fs.cwd().openFile("roms/dmg_boot.bin", .{});
    // const file = try std.fs.cwd().openFile("roms/01-special.gb", .{});
    const file = try std.fs.cwd().openFile("../gb-test-roms/cpu_instrs/individual/01-special.gb", .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    while (reader.readByte()) |outputByte| {
        std.debug.print("0x{x}\n", .{outputByte});
    } else |err| switch (err) {
        error.EndOfStream => {
            std.debug.print("End of file\n", .{});
        },
        else => return err,
    }
}

const std = @import("std");
