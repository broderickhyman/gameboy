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
    // var cpu = Cpu{ .memory = main_memory, .index = 0x008f };

    // const end = cpu.index + 50;
    const end = cpu.index + 500;
    // var index: u32 = 0x100;
    // const end = 0x100 + 50;
    while (cpu.index < end and cpu.index < cpu.memory.len) {
        const op_code = cpu.read();
        if (op_code == 0) {
            continue;
        }
        if (cpu.index - 1 > 0xa7 and cpu.index - 1 < 0xe0) {
            // Logo and video
            continue;
        }
        // const x = op_code >> 6 & 0b11;
        // const y = op_code >> 3 & 0b111;
        // const z = op_code & 0b111;
        // const p = y >> 1;
        // const q = y & 1;
        // const first = op_code >> 4;
        // const second = op_code & 0xF;
        // std.debug.print("{x:02} {d:>2} {d:>2}\n", .{ op_code, first, second });
        // std.debug.print("\n{x:02} {x} {x}\n", .{ op_code, first, second });
        // std.debug.print("{b:08} 0x{x:02} {d:>2} {d:>2} x:{d} y:{d} z:{d} p:{d} q:{d}\n", .{ op_code, op_code, first, second, x, y, z, p, q });
        // std.debug.print("{d:>2} {d:>2}\n", .{ first, second });
        std.debug.print("${x:04} - ", .{cpu.index - 1});
        op_lookup[op_code](&cpu, op_code);
        std.debug.print("\n", .{});
    }
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

fn nop(_: *Cpu, op_code: u8) void {
    // std.debug.print("********** NOP ********** ${x:04}\n", .{cpu.index - 1});
    std.debug.print("********** NOP **********\n", .{});
    std.debug.print("{X:02}\n", .{op_code});
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

fn ld_r_r(_: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const z = op_code & 0b111;
    const register1 = reg_8[y];
    const register2 = reg_8[z];
    std.debug.print("LD {s},{s}\n", .{ register1, register2 });
}

fn ld_hld_a(_: *Cpu, _: u8) void {
    std.debug.print("LD (HL-),A\n", .{});
}

fn ld_hli_a(_: *Cpu, _: u8) void {
    std.debug.print("LD (HL+),A\n", .{});
}

fn ld_a_ded(_: *Cpu, _: u8) void {
    std.debug.print("LD A,(DE)\n", .{});
}

fn ld_a16_a(cpu: *Cpu, _: u8) void {
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    std.debug.print("LD (${X:04}),A\n", .{address});
}

fn ldh_c_a(_: *Cpu, _: u8) void {
    std.debug.print("LD ($FF00+C),A\n", .{});
}

fn ldh_a8_a(cpu: *Cpu, _: u8) void {
    const displacement = cpu.read();
    std.debug.print("LD ($FF00+${X}),A\n", .{displacement});
}

fn ldh_a_a8(cpu: *Cpu, _: u8) void {
    const displacement = cpu.read();
    std.debug.print("LD A,($FF00+${X})\n", .{displacement});
}

fn jr_cond_e8(cpu: *Cpu, op_code: u8) void {
    const register_index = op_code & 3;
    const condition = reg_cc[register_index];
    const displacement = cpu.read();

    const address = @as(u16, @bitCast(@as(i16, @bitCast(cpu.index)) + @as(i8, @bitCast(displacement))));
    std.debug.print("JR {s},Addr_{x:04}\n", .{ condition, address });
}

fn jr_e8(cpu: *Cpu, _: u8) void {
    const displacement = cpu.read();
    const address = @as(u16, @bitCast(@as(i16, @bitCast(cpu.index)) + @as(i8, @bitCast(displacement))));
    std.debug.print("JR Addr_{x:04}\n", .{address});
}

fn inc_r(_: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    std.debug.print("INC {s}\n", .{register});
}

fn inc_rp(_: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const p = y >> 1;
    const register = reg_p[p];
    std.debug.print("INC {s}\n", .{register});
}

fn dec_r(_: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    std.debug.print("DEC {s}\n", .{register});
}

fn dec_rp(_: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const p = y >> 1;
    const register = reg_p[p];
    std.debug.print("DEC {s}\n", .{register});
}

fn add_r(_: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    std.debug.print("ADD {s}\n", .{register});
}

fn sub_r(_: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    std.debug.print("SUB {s}\n", .{register});
}

fn and_r(_: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    std.debug.print("AND {s}\n", .{register});
}

fn or_r(_: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    std.debug.print("OR {s}\n", .{register});
}

fn adc_r(_: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    std.debug.print("ADC {s}\n", .{register});
}

fn sbc_r(_: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    std.debug.print("SBC {s}\n", .{register});
}

fn xor_r(_: *Cpu, op_code: u8) void {
    const register_index = op_code & 7;
    const register = reg_8[register_index];
    std.debug.print("XOR A,{s}\n", .{register});
}

fn cp_r(_: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    std.debug.print("CP {s}\n", .{register});
}

fn call_a16(cpu: *Cpu, _: u8) void {
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    std.debug.print("CALL ${X:04}\n", .{address});
}

fn cp_a_n8(cpu: *Cpu, _: u8) void {
    const address = cpu.read();
    std.debug.print("CP ${X:02}\n", .{address});
}

fn halt(_: *Cpu, _: u8) void {
    std.debug.print("HALT\n", .{});
}

fn push_rp2(_: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const p = y >> 1;
    const register = reg_p2[p];
    std.debug.print("PUSH {s}\n", .{register});
}

fn pop_rp2(_: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const p = y >> 1;
    const register = reg_p2[p];
    std.debug.print("POP {s}\n", .{register});
}

fn ret(_: *Cpu, _: u8) void {
    std.debug.print("RET\n", .{});
}

fn rla(_: *Cpu, _: u8) void {
    std.debug.print("RLA\n", .{});
}

fn cb_prefix(cpu: *Cpu, _: u8) void {
    const op_code = cpu.read();
    const x = op_code >> 6 & 0b11;
    const y = op_code >> 3 & 0b111;
    const z = op_code & 0b111;
    if (x == 0) {
        const operation = reg_rot[y];
        const register = reg_8[z];
        std.debug.print("{s} {s}\n", .{ operation, register });
    } else if (x == 1) {
        const register = reg_8[z];
        std.debug.print("BIT {d},{s}\n", .{ y, register });
    } else {
        std.debug.print("NOP CB\n", .{});
    }
}

const reg_8: [8][]const u8 = .{ "B", "C", "D", "E", "H", "L", "(HL)", "A" };

const reg_p: [4][]const u8 = .{ "BC", "DE", "HL", "SP" };
const reg_p2: [4][]const u8 = .{ "BC", "DE", "HL", "AF" };

const reg_cc: [4][]const u8 = .{ "NZ", "Z", "NC", "C" };

const reg_alu: [8][]const u8 = .{ "ADD A", "ADC A", "SUB", "SBC A", "AND", "XOR", "OR", "CP" };

const reg_rot: [8][]const u8 = .{ "RLC", "RRC", "RL", "RR", "SLA", "SRA", "SWAP", "SRL" };

// zig fmt: off
const op_lookup = [256] *const fn (*Cpu, u8) void { 
//  0           1          2         3          4       5         6        7
//  8           9          A         B          C       D         E        F
    nop,        ld_rp_n16, nop,      inc_rp,    inc_r,  dec_r,    ld_r_n8, nop,    // 0
    nop,        nop,       nop,      dec_rp,    inc_r,  dec_r,    ld_r_n8, nop,   
    nop,        ld_rp_n16, nop,      inc_rp,    inc_r,  dec_r,    ld_r_n8, rla,    // 1
    jr_e8,      nop,       ld_a_ded, dec_rp,    inc_r,  dec_r,    ld_r_n8, nop,   
    jr_cond_e8, ld_rp_n16, ld_hli_a, inc_rp,    inc_r,  dec_r,    ld_r_n8, nop,    // 2
    jr_cond_e8, nop,       nop,      dec_rp,    inc_r,  dec_r,    ld_r_n8, nop,   
    jr_cond_e8, ld_rp_n16, ld_hld_a, inc_rp,    inc_r,  dec_r,    ld_r_n8, nop,    // 3
    jr_cond_e8, nop,       nop,      dec_rp,    inc_r,  dec_r,    ld_r_n8, nop,   
    ld_r_r,     ld_r_r,    ld_r_r,   ld_r_r,    ld_r_r, ld_r_r,   ld_r_r,  ld_r_r, // 4
    ld_r_r,     ld_r_r,    ld_r_r,   ld_r_r,    ld_r_r, ld_r_r,   ld_r_r,  ld_r_r,
    ld_r_r,     ld_r_r,    ld_r_r,   ld_r_r,    ld_r_r, ld_r_r,   ld_r_r,  ld_r_r, // 5
    ld_r_r,     ld_r_r,    ld_r_r,   ld_r_r,    ld_r_r, ld_r_r,   ld_r_r,  ld_r_r,
    ld_r_r,     ld_r_r,    ld_r_r,   ld_r_r,    ld_r_r, ld_r_r,   ld_r_r,  ld_r_r, // 6
    ld_r_r,     ld_r_r,    ld_r_r,   ld_r_r,    ld_r_r, ld_r_r,   ld_r_r,  ld_r_r,
    ld_r_r,     ld_r_r,    ld_r_r,   ld_r_r,    ld_r_r, ld_r_r,   halt,    ld_r_r, // 7
    ld_r_r,     ld_r_r,    ld_r_r,   ld_r_r,    ld_r_r, ld_r_r,   ld_r_r,  ld_r_r,
    add_r,      add_r,     add_r,    add_r,     add_r,  add_r,    add_r,   add_r,  // 8
    adc_r,      adc_r,     adc_r,    adc_r,     adc_r,  adc_r,    adc_r,   adc_r, 
    sub_r,      sub_r,     sub_r,    sub_r,     sub_r,  sub_r,    sub_r,   sub_r,  // 9
    sbc_r,      sbc_r,     sbc_r,    sbc_r,     sbc_r,  sbc_r,    sbc_r,   sbc_r, 
    and_r,      and_r,     and_r,    and_r,     and_r,  and_r,    and_r,   and_r,  // A
    xor_r,      xor_r,     xor_r,    xor_r,     xor_r,  xor_r,    xor_r,   xor_r,
    or_r,       or_r,      or_r,     or_r,      or_r,   or_r,     or_r,    or_r,   // B
    cp_r,       cp_r,      cp_r,     cp_r,      cp_r,   cp_r,     cp_r,    cp_r,  
    nop,        pop_rp2,   nop,      nop,       nop,    push_rp2, nop,     nop,    // C
    nop,        ret,       nop,      cb_prefix, nop,    call_a16, nop,     nop,   
    nop,        pop_rp2,   nop,      nop,       nop,    push_rp2, nop,     nop,    // D
    nop,        nop,       nop,      nop,       nop,    nop,      nop,     nop,   
    ldh_a8_a,   pop_rp2,   ldh_c_a,  nop,       nop,    push_rp2, nop,     nop,    // E
    nop,        nop,       ld_a16_a, nop,       nop,    nop,      nop,     nop,   
    ldh_a_a8,   pop_rp2,   nop,      nop,       nop,    push_rp2, nop,     nop,    // F
    nop,        nop,       nop,      nop,       nop,    nop,      cp_a_n8, nop
    };
// zig fmt: on

const std = @import("std");
