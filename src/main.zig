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

    const main_memory = try file.readToEndAlloc(allocator, 32 * 1024);
    defer allocator.free(main_memory);

    var cpu = Cpu{ .memory = main_memory, .index = 0 };

    // var index: u32 = 0;
    const end = 30;
    // var index: u32 = 0x100;
    // const end = 0x100 + 50;
    while (cpu.index < end and cpu.index < cpu.memory.len) {
        const op_code = cpu.read();
        // const op_code = cpu.memory[cpu.index];
        // cpu.index += 1;
        // const x = op_code >> 6 & 0b11;
        // const y = op_code >> 3 & 0b111;
        // const z = op_code & 0b111;
        // const p = y >> 1;
        // const q = y & 1;
        const first = op_code >> 4;
        const second = op_code & 0xF;
        // if (second == 1) {
        // if (outputByte != 0) {
        // std.debug.print("{x:02} {d:>2} {d:>2}\n", .{ op_code, first, second });
        std.debug.print("\n{x:02} {x} {x}\n", .{ op_code, first, second });
        // std.debug.print("{b:08} 0x{x:02} {d:>2} {d:>2} x:{d} y:{d} z:{d} p:{d} q:{d}\n", .{ op_code, op_code, first, second, x, y, z, p, q });
        // std.debug.print("{d:>2} {d:>2}\n", .{ first, second });
        // }
        // }

        op_lookup[op_code](&cpu, op_code);
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

const Cpu = struct {
    memory: []u8,
    index: u16,
    fn read(self: *Cpu) u8 {
        const memory_value = self.memory[self.index];
        self.index += 1;
        return memory_value;
    }
    fn printIndex(self: *Cpu) void {
        std.debug.print("Current Index: {0d} {0x}\n", .{self.index});
    }
};

fn nop(_: *Cpu, _: u8) void {
    std.debug.print("NOP\n", .{});
}

fn ld_sp_n16(cpu: *Cpu, _: u8) void {
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    std.debug.print("LD SP,${x:04}\n", .{address});
}

fn ld_rp_n16(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const p = y >> 1;
    const register = reg_p[p];
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    std.debug.print("LD {s},${x:04}\n", .{ register, address });
}

fn ld_r_n8(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    const address = cpu.read();
    std.debug.print("LD {s},${x:04}\n", .{ register, address });
}

fn ld_hld_a(_: *Cpu, _: u8) void {
    std.debug.print("LD (HL-),A\n", .{});
}

fn xor_a(_: *Cpu, op_code: u8) void {
    const register_index = op_code & 7;
    const register = reg_8[register_index];
    std.debug.print("XOR A,{s}\n", .{register});
}

fn jr_cond_e8(cpu: *Cpu, op_code: u8) void {
    const register_index = op_code & 3;
    const condition = reg_cc[register_index];
    const displacement = cpu.read();

    const address = @as(u16, @bitCast(@as(i16, @bitCast(cpu.index)) + @as(i8, @bitCast(displacement))));
    std.debug.print("JR {s},Addr_{x:04}\n", .{ condition, address });
}

fn cb_prefix(cpu: *Cpu, _: u8) void {
    const op_code = cpu.read();
    const left = op_code >> 4;
    if (left >= 4 and left <= 7) {
        // BIT
        const y = op_code >> 3 & 0b111;
        const z = op_code & 0b111;
        const register = reg_8[z];
        std.debug.print("BIT {d},{s}\n", .{ y, register });
    } else {
        std.debug.print("NOP CB\n", .{});
    }
    // switch (y) {
    // 7 => {
    // },
    // }
}

const reg_8: [8][]const u8 = .{ "B", "C", "D", "E", "H", "L", "(HL)", "A" };

const reg_p: [4][]const u8 = .{ "BC", "DE", "HL", "SP" };
const reg_p2: [4][]const u8 = .{ "BC", "DE", "HL", "AF" };

const reg_cc: [4][]const u8 = .{ "NZ", "Z", "NC", "C" };

const reg_alu: [8][]const u8 = .{ "ADD A", "ADC A", "SUB", "SBC A", "AND", "XOR", "OR", "CP" };

const reg_rot: [8][]const u8 = .{ "RLC", "RRC", "RL", "RR", "SLA", "SRA", "SWAP", "SRL" };

// zig fmt: off
const op_lookup = [256] *const fn (*Cpu, u8) void { 
//  0           1          2         3          4    5    6    7
//  8           9          A         B          C    D    E    F
    nop,        nop,       nop,      nop,       nop, nop, nop, nop, // 0
    nop,        nop,       nop,      nop,       nop, nop, ld_r_n8, nop,
    nop,        nop,       nop,      nop,       nop, nop, nop, nop, // 1
    nop,        nop,       nop,      nop,       nop, nop, nop, nop,
    jr_cond_e8, ld_rp_n16, nop,      nop,       nop, nop, nop, nop, // 2
    nop,        nop,       nop,      nop,       nop, nop, nop, nop,
    nop,        ld_sp_n16, ld_hld_a, nop,       nop, nop, nop, nop, // 3
    nop,        nop,       nop,      nop,       nop, nop, nop, nop,
    nop,        nop,       nop,      nop,       nop, nop, nop, nop, // 4
    nop,        nop,       nop,      nop,       nop, nop, nop, nop,
    nop,        nop,       nop,      nop,       nop, nop, nop, nop, // 5
    nop,        nop,       nop,      nop,       nop, nop, nop, nop,
    nop,        nop,       nop,      nop,       nop, nop, nop, nop, // 6
    nop,        nop,       nop,      nop,       nop, nop, nop, nop,
    nop,        nop,       nop,      nop,       nop, nop, nop, nop, // 7
    nop,        nop,       nop,      nop,       nop, nop, nop, nop,
    nop,        nop,       nop,      nop,       nop, nop, nop, nop, // 8
    nop,        nop,       nop,      nop,       nop, nop, nop, nop,
    nop,        nop,       nop,      nop,       nop, nop, nop, nop, // 9
    nop,        nop,       nop,      nop,       nop, nop, nop, nop,
    nop,        nop,       nop,      nop,       nop, nop, nop, nop, // A
    xor_a,      xor_a,     xor_a,    xor_a,     xor_a, xor_a, xor_a, xor_a,
    nop,        nop,       nop,      nop,       nop, nop, nop, nop, // B
    nop,        nop,       nop,      nop,       nop, nop, nop, nop,
    nop,        nop,       nop,      nop,       nop, nop, nop, nop, // C
    nop,        nop,       nop,      cb_prefix, nop, nop, nop, nop,
    nop,        nop,       nop,      nop,       nop, nop, nop, nop, // D
    nop,        nop,       nop,      nop,       nop, nop, nop, nop,
    nop,        nop,       nop,      nop,       nop, nop, nop, nop, // E
    nop,        nop,       nop,      nop,       nop, nop, nop, nop,
    nop,        nop,       nop,      nop,       nop, nop, nop, nop, // F
    nop,        nop,       nop,      nop,       nop, nop, nop, nop
    };
// zig fmt: on

// inline fn u2i(v: usize) isize {
//     return @intCast(v);
// }

const std = @import("std");
