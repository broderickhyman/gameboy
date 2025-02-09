pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // const file = try std.fs.cwd().openFile("roms/dmg_boot.bin", .{});
    // const fileName = "01-special.gb";
    // const fileName = "02-interrupts.gb";
    // const fileName = "03-op sp,hl.gb";
    // const fileName = "04-op r,imm.gb";
    // const fileName = "05-op rp.gb";
    // const fileName = "06-ld r,r.gb";
    const fileName = "07-jr,jp,call,ret,rst.gb";
    // const fileName = "08-misc instrs.gb";
    // const fileName = "09-op r,r.gb";
    // const fileName = "10-bit ops.gb";
    // const fileName = "11-op a,(hl).gb";
    const file = try std.fs.cwd().openFile("../gb-test-roms/cpu_instrs/individual/" ++ fileName, .{});
    defer file.close();

    const main_memory = try file.readToEndAlloc(allocator, 32 * 1024);
    defer allocator.free(main_memory);

    // var cpu = Cpu{ .memory = main_memory, .index = 0 };
    // var cpu = Cpu{ .memory = main_memory, .index = 0x008f };
    var cpu = Cpu{ .memory = main_memory, .index = 0x0100 };

    // const end = cpu.index + 50;
    // const end = cpu.index + 500;
    const end = cpu.memory.len;
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
        // cpu.print("{x:02} {d:>2} {d:>2}\n", .{ op_code, first, second });
        // cpu.print("\n{x:02} {x} {x}\n", .{ op_code, first, second });
        // cpu.print("{b:08} 0x{x:02} {d:>2} {d:>2} x:{d} y:{d} z:{d} p:{d} q:{d}\n", .{ op_code, op_code, first, second, x, y, z, p, q });
        // cpu.print("{d:>2} {d:>2}\n", .{ first, second });
        cpu.print("${x:04} - ", .{cpu.index - 1});
        op_lookup[op_code](&cpu, op_code);
        cpu.print("\n", .{});
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
        self.print("Current Index: {0d} {0x}\n", .{self.index});
    }
    fn print(_: *Cpu, comptime fmt: []const u8, args: anytype) void {
        const shouldPrint = false;
        if (shouldPrint) {
            std.debug.print(fmt, args);
        }
    }
};

fn nop(_: *Cpu, op_code: u8) void {
    // std.debug.print("********** NOP ********** ${x:04}\n", .{cpu.index - 1});
    std.debug.print("********** NOP **********\n", .{});
    std.debug.print("{X:02}\n", .{op_code});
    // std.debug.panic("", .{});
}

fn un_nop(_: *Cpu, _: u8) void {}

// Load

fn ld_rp_n16(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const p = y >> 1;
    const register = reg_p[p];
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("LD {s},${x:04}\n", .{ register, address });
}

fn ld_r_n8(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    const address = cpu.read();
    cpu.print("LD {s},${x:04}\n", .{ register, address });
}

fn ld_r_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const z = op_code & 0b111;
    const register1 = reg_8[y];
    const register2 = reg_8[z];
    cpu.print("LD {s},{s}\n", .{ register1, register2 });
}

fn ld_bc_a(cpu: *Cpu, _: u8) void {
    cpu.print("LD (BC),A\n", .{});
}

fn ld_de_a(cpu: *Cpu, _: u8) void {
    cpu.print("LD (DE),A\n", .{});
}

fn ld_a_bc(cpu: *Cpu, _: u8) void {
    cpu.print("LD A,(BC)\n", .{});
}

fn ld_a_de(cpu: *Cpu, _: u8) void {
    cpu.print("LD A,(DE)\n", .{});
}

fn ld_hli_a(cpu: *Cpu, _: u8) void {
    cpu.print("LD (HL+),A\n", .{});
}

fn ld_hld_a(cpu: *Cpu, _: u8) void {
    cpu.print("LD (HL-),A\n", .{});
}

fn ld_a_hli(cpu: *Cpu, _: u8) void {
    cpu.print("LD A,(HL+)\n", .{});
}

fn ld_a_hld(cpu: *Cpu, _: u8) void {
    cpu.print("LD A,(HL-)\n", .{});
}

fn ld_a16_a(cpu: *Cpu, _: u8) void {
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("LD (${X:04}),A\n", .{address});
}

fn ld_a_a16(cpu: *Cpu, _: u8) void {
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("LD A,${X:04},A\n", .{address});
}

fn ld_a16_sp(cpu: *Cpu, _: u8) void {
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("LD ${X:04},SP\n", .{address});
}

fn ldh_c_a(cpu: *Cpu, _: u8) void {
    cpu.print("LD ($FF00+C),A\n", .{});
}

fn ldh_a_c(cpu: *Cpu, _: u8) void {
    cpu.print("LD A,($FF00+C)\n", .{});
}

fn ldh_a8_a(cpu: *Cpu, _: u8) void {
    const displacement = cpu.read();
    cpu.print("LD ($FF00+${X}),A\n", .{displacement});
}

fn ldh_a_a8(cpu: *Cpu, _: u8) void {
    const displacement = cpu.read();
    cpu.print("LD A,($FF00+${X})\n", .{displacement});
}

fn ld_sp_hl(cpu: *Cpu, _: u8) void {
    cpu.print("LD SP,HL\n", .{});
}

fn ld_hl_sp_e8(cpu: *Cpu, _: u8) void {
    const displacement = cpu.read();
    const address = @as(u16, @bitCast(@as(i16, @bitCast(cpu.index)) + @as(i8, @bitCast(displacement))));
    cpu.print("LD HL,SP+${X:02}\n", .{address});
}

// Jumps

fn call_a16(cpu: *Cpu, _: u8) void {
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("CALL ${X:04}\n", .{address});
}

fn call_cc_a16(cpu: *Cpu, op_code: u8) void {
    const register_index = op_code & 3;
    const condition = reg_cc[register_index];
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("CALL {s},${X:04}\n", .{ condition, address });
}

fn jr_cc_e8(cpu: *Cpu, op_code: u8) void {
    const register_index = op_code & 3;
    const condition = reg_cc[register_index];
    const displacement = cpu.read();

    const address = @as(u16, @bitCast(@as(i16, @bitCast(cpu.index)) + @as(i8, @bitCast(displacement))));
    cpu.print("JR {s},Addr_{x:04}\n", .{ condition, address });
}

fn jr_e8(cpu: *Cpu, _: u8) void {
    const displacement = cpu.read();
    const address = @as(u16, @bitCast(@as(i16, @bitCast(cpu.index)) + @as(i8, @bitCast(displacement))));
    cpu.print("JR Addr_{x:04}\n", .{address});
}

fn ret(cpu: *Cpu, _: u8) void {
    cpu.print("RET\n", .{});
}

fn reti(cpu: *Cpu, _: u8) void {
    cpu.print("RETI\n", .{});
}

fn ret_cc(cpu: *Cpu, op_code: u8) void {
    const register_index = op_code & 3;
    const condition = reg_cc[register_index];
    cpu.print("RET {s}\n", .{condition});
}

fn jp_a16(cpu: *Cpu, _: u8) void {
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("JP Addr_{x:04}\n", .{address});
}

fn jp_cc_a16(cpu: *Cpu, op_code: u8) void {
    const register_index = op_code & 3;
    const condition = reg_cc[register_index];

    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("JP {s},Addr_{x:04}\n", .{ condition, address });
}

fn jp_hl(cpu: *Cpu, _: u8) void {
    cpu.print("JP HL\n", .{});
}

fn rst(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const vec = y * 8;
    cpu.print("RST Addr_{x:04}\n", .{vec});
}

// Arithmetic

fn inc_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("INC {s}\n", .{register});
}

fn inc_rp(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const p = y >> 1;
    const register = reg_p[p];
    cpu.print("INC {s}\n", .{register});
}

fn dec_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("DEC {s}\n", .{register});
}

fn dec_rp(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const p = y >> 1;
    const register = reg_p[p];
    cpu.print("DEC {s}\n", .{register});
}

fn add_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("ADD {s}\n", .{register});
}

fn add_hl_rp(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const p = y >> 1;
    const register = reg_p[p];
    cpu.print("ADD HL,{s}\n", .{register});
}

fn add_sp_e8(cpu: *Cpu, _: u8) void {
    const displacement = cpu.read();
    const address = @as(u16, @bitCast(@as(i16, @bitCast(cpu.index)) + @as(i8, @bitCast(displacement))));
    cpu.print("ADD SP,ADDR_${X:02}\n", .{address});
}

fn sub_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("SUB {s}\n", .{register});
}

fn adc_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("ADC {s}\n", .{register});
}

fn sbc_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("SBC {s}\n", .{register});
}

// fn cp_a_n8(cpu: *Cpu, _: u8) void {
//     const address = cpu.read();
//     cpu.print("CP ${X:02}\n", .{address});
// }

fn cp_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("CP {s}\n", .{register});
}

fn alu_n8(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_alu[y];
    const address = cpu.read();
    cpu.print("{s} A,${X:02}\n", .{ register, address });
}

// Bitwise logic

fn and_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("AND {s}\n", .{register});
}

fn or_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("OR {s}\n", .{register});
}

fn xor_r(cpu: *Cpu, op_code: u8) void {
    const register_index = op_code & 7;
    const register = reg_8[register_index];
    cpu.print("XOR A,{s}\n", .{register});
}

// Stack

fn push_rp2(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const p = y >> 1;
    const register = reg_p2[p];
    cpu.print("PUSH {s}\n", .{register});
}

fn pop_rp2(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const p = y >> 1;
    const register = reg_p2[p];
    cpu.print("POP {s}\n", .{register});
}

// Bit shift

fn rlca(cpu: *Cpu, _: u8) void {
    cpu.print("RLCA\n", .{});
}

fn rrca(cpu: *Cpu, _: u8) void {
    cpu.print("RRCA\n", .{});
}

fn rla(cpu: *Cpu, _: u8) void {
    cpu.print("RLA\n", .{});
}

fn rra(cpu: *Cpu, _: u8) void {
    cpu.print("RRA\n", .{});
}

fn daa(cpu: *Cpu, _: u8) void {
    cpu.print("DAA\n", .{});
}

fn cpl(cpu: *Cpu, _: u8) void {
    cpu.print("CPL\n", .{});
}

fn scf(cpu: *Cpu, _: u8) void {
    cpu.print("SCF\n", .{});
}

fn ccf(cpu: *Cpu, _: u8) void {
    cpu.print("CCF\n", .{});
}

// Interrupt

fn halt(cpu: *Cpu, _: u8) void {
    cpu.print("HALT\n", .{});
}

fn di(cpu: *Cpu, _: u8) void {
    cpu.print("HALT\n", .{});
}

fn ei(cpu: *Cpu, _: u8) void {
    cpu.print("HALT\n", .{});
}

// CB

fn cb_prefix(cpu: *Cpu, _: u8) void {
    const op_code = cpu.read();
    const x = op_code >> 6 & 0b11;
    const y = op_code >> 3 & 0b111;
    const z = op_code & 0b111;
    if (x == 0) {
        const operation = reg_rot[y];
        const register = reg_8[z];
        cpu.print("{s} {s}\n", .{ operation, register });
    } else if (x == 1) {
        const register = reg_8[z];
        cpu.print("BIT {d},{s}\n", .{ y, register });
    } else {
        cpu.print("NOP CB\n", .{});
    }
}

fn stop(cpu: *Cpu, _: u8) void {
    _ = cpu.read();
    cpu.print("STOP\n", .{});
}

const reg_8: [8][]const u8 = .{ "B", "C", "D", "E", "H", "L", "(HL)", "A" };

const reg_p: [4][]const u8 = .{ "BC", "DE", "HL", "SP" };
const reg_p2: [4][]const u8 = .{ "BC", "DE", "HL", "AF" };

const reg_cc: [4][]const u8 = .{ "NZ", "Z", "NC", "C" };

const reg_alu: [8][]const u8 = .{ "ADD A", "ADC A", "SUB", "SBC A", "AND", "XOR", "OR", "CP" };

const reg_rot: [8][]const u8 = .{ "RLC", "RRC", "RL", "RR", "SLA", "SRA", "SWAP", "SRL" };

// zig fmt: off
const op_lookup = [256] *const fn (*Cpu, u8) void { 
//  0            1          2          3          4            5         6        7
//  8            9          A          B          C            D         E        F
    nop,         ld_rp_n16, ld_bc_a,   inc_rp,    inc_r,       dec_r,    ld_r_n8, rlca,   // 0
    ld_a16_sp,   add_hl_rp, ld_a_bc,   dec_rp,    inc_r,       dec_r,    ld_r_n8, rrca,   
    stop,        ld_rp_n16, ld_de_a,   inc_rp,    inc_r,       dec_r,    ld_r_n8, rla,    // 1
    jr_e8,       add_hl_rp, ld_a_de,   dec_rp,    inc_r,       dec_r,    ld_r_n8, rra,   
    jr_cc_e8,    ld_rp_n16, ld_hli_a,  inc_rp,    inc_r,       dec_r,    ld_r_n8, daa,    // 2
    jr_cc_e8,    add_hl_rp, ld_a_hli,  dec_rp,    inc_r,       dec_r,    ld_r_n8, cpl,   
    jr_cc_e8,    ld_rp_n16, ld_hld_a,  inc_rp,    inc_r,       dec_r,    ld_r_n8, scf,    // 3
    jr_cc_e8,    add_hl_rp, ld_a_hld,  dec_rp,    inc_r,       dec_r,    ld_r_n8, ccf,   
    ld_r_r,      ld_r_r,    ld_r_r,    ld_r_r,    ld_r_r,      ld_r_r,   ld_r_r,  ld_r_r, // 4
    ld_r_r,      ld_r_r,    ld_r_r,    ld_r_r,    ld_r_r,      ld_r_r,   ld_r_r,  ld_r_r,
    ld_r_r,      ld_r_r,    ld_r_r,    ld_r_r,    ld_r_r,      ld_r_r,   ld_r_r,  ld_r_r, // 5
    ld_r_r,      ld_r_r,    ld_r_r,    ld_r_r,    ld_r_r,      ld_r_r,   ld_r_r,  ld_r_r,
    ld_r_r,      ld_r_r,    ld_r_r,    ld_r_r,    ld_r_r,      ld_r_r,   ld_r_r,  ld_r_r, // 6
    ld_r_r,      ld_r_r,    ld_r_r,    ld_r_r,    ld_r_r,      ld_r_r,   ld_r_r,  ld_r_r,
    ld_r_r,      ld_r_r,    ld_r_r,    ld_r_r,    ld_r_r,      ld_r_r,   halt,    ld_r_r, // 7
    ld_r_r,      ld_r_r,    ld_r_r,    ld_r_r,    ld_r_r,      ld_r_r,   ld_r_r,  ld_r_r,
    add_r,       add_r,     add_r,     add_r,     add_r,       add_r,    add_r,   add_r,  // 8
    adc_r,       adc_r,     adc_r,     adc_r,     adc_r,       adc_r,    adc_r,   adc_r, 
    sub_r,       sub_r,     sub_r,     sub_r,     sub_r,       sub_r,    sub_r,   sub_r,  // 9
    sbc_r,       sbc_r,     sbc_r,     sbc_r,     sbc_r,       sbc_r,    sbc_r,   sbc_r, 
    and_r,       and_r,     and_r,     and_r,     and_r,       and_r,    and_r,   and_r,  // A
    xor_r,       xor_r,     xor_r,     xor_r,     xor_r,       xor_r,    xor_r,   xor_r,
    or_r,        or_r,      or_r,      or_r,      or_r,        or_r,     or_r,    or_r,   // B
    cp_r,        cp_r,      cp_r,      cp_r,      cp_r,        cp_r,     cp_r,    cp_r,  
    ret_cc,      pop_rp2,   jp_cc_a16, jp_a16,    call_cc_a16, push_rp2, alu_n8,  rst,    // C
    ret_cc,      ret,       jp_cc_a16, cb_prefix, call_cc_a16, call_a16, alu_n8,  rst,   
    ret_cc,      pop_rp2,   jp_cc_a16, un_nop,    call_cc_a16, push_rp2, alu_n8,  rst,    // D
    ret_cc,      reti,      jp_cc_a16, un_nop,    call_cc_a16, un_nop,   alu_n8,  rst,   
    ldh_a8_a,    pop_rp2,   ldh_c_a,   un_nop,    un_nop,      push_rp2, alu_n8,  rst,    // E
    add_sp_e8,   jp_hl,     ld_a16_a,  un_nop,    un_nop,      un_nop,   alu_n8,  rst,   
    ldh_a_a8,    pop_rp2,   ldh_a_c,   di,        un_nop,      push_rp2, alu_n8,  rst,    // F
    ld_hl_sp_e8, ld_sp_hl,  ld_a_a16,  ei,        un_nop,      un_nop,   alu_n8,  rst
    };
// zig fmt: on

const std = @import("std");
