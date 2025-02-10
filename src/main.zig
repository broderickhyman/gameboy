pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const std_out = std.io.getStdOut().writer();

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

    const main_memory = try allocator.alloc(u8, 0xFFFF);
    defer allocator.free(main_memory);

    _ = try file.readAll(main_memory);

    // var cpu = Cpu{ .memory = main_memory, .index = 0 };
    // var cpu = Cpu{ .memory = main_memory, .index = 0x008f };

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    // std.debug.print("${s}\n", .{args});
    var shouldPrint = false;
    if (args.len > 1 and std.mem.eql(u8, args[1], "--verbose")) {
        shouldPrint = true;
    }

    // zig fmt: off
    var cpu = Cpu{
        .memory = main_memory,
        .pc = 0x0100,
        .counter = 1,
        .shouldPrint = shouldPrint,
        .stdOut = std_out
        };
    // zig fmt: on

    const end = 5000;
    // const end = cpu.index + 500;
    // const end = cpu.memory.len;
    // var index: u32 = 0x100;
    // const end = 0x100 + 50;

    try cpu.logState();
    // cpu.print_flags();
    while (cpu.counter < end and cpu.pc < cpu.memory.len) {
        const op_code = cpu.read();
        // const x = op_code >> 6 & 0b11;
        // const y = op_code >> 3 & 0b111;
        // const z = op_code & 0b111;
        // const p = y >> 1;
        // const q = y & 1;
        // cpu.print("{d:>2} {d:>2}\n", .{ first, second });
        // cpu.print("${x:04} - ", .{cpu.pc - 1});
        cpu.print("{X:02}\n", .{op_code});

        if (cpu.counter == 70) {
            // @breakpoint();
        }

        op_lookup[op_code](&cpu, op_code);
        cpu.counter += 1;
        try cpu.logState();
        // cpu.print_flags();
        // cpu.print("\n", .{});
    }
}

const Cpu = struct {
    memory: []u8,
    pc: u16,
    counter: u32,
    shouldPrint: bool,
    stdOut: std.fs.File.Writer,
    fn read(self: *Cpu) u8 {
        const memory_value = self.memory[self.pc];
        self.pc += 1;
        return memory_value;
    }
    fn printIndex(self: *Cpu) void {
        self.print("Current Index: {0d} {0x}\n", .{self.pc});
    }
    fn print(self: *Cpu, comptime fmt: []const u8, args: anytype) void {
        if (self.shouldPrint) {
            std.debug.print(fmt, args);
        }
    }
    fn print_flags(self: *Cpu) void {
        self.print("{b}\n", .{af.sp.flag.full});
        self.print("c: {b}\n", .{flags.c});
        self.print("h: {b}\n", .{flags.h});
        self.print("n: {b}\n", .{flags.n});
        self.print("z: {b}\n", .{flags.z});
    }
    fn logState(self: *Cpu) !void {
        try self.stdOut.print("A:{X:02} F:{X:02} B:{X:02} C:{X:02} D:{X:02} E:{X:02} H:{X:02} L:{X:02} SP:{X:04} PC:{X:04} PCMEM:{X:02},{X:02},{X:02},{X:02}", .{ a_reg.*, af.sp.flag.full, bc.sp.hi, bc.sp.lo, de.sp.hi, de.sp.lo, hl.sp.hi, hl.sp.lo, sp, self.pc, self.memory[self.pc], self.memory[self.pc + 1], self.memory[self.pc + 2], self.memory[self.pc + 3] });
        self.print(" - {d}", .{self.counter});
        try self.stdOut.print("\n", .{});
    }
};

const SplitRegister = packed struct { lo: u8, hi: u8 };
const Register = packed union { full: u16, sp: SplitRegister };

const FlagRegister = packed struct { x: u4, c: u1, h: u1, n: u1, z: u1 };
const FlagRegisterUnion = packed union { full: u8, sp: FlagRegister };
const AfRegister = packed struct { flag: FlagRegisterUnion, a: u8 };
const AfRegisterFull = packed union { af: u16, sp: AfRegister };

// var af = Register{ .f = 0x01b0 };
var af = AfRegisterFull{ .af = 0x01b0 };
var bc = Register{ .full = 0x0013 };
var de = Register{ .full = 0x00d8 };
var hl = Register{ .full = 0x014d };
var sp: u16 = 0xfffe;
const a_reg = &af.sp.a;
const flags = &af.sp.flag.sp;

fn nop(_: *Cpu, _: u8) void {
    // std.debug.print("********** NOP ********** ${x:04}\n", .{cpu.index - 1});
    // std.debug.print("********** NOP **********\n", .{});
    // std.debug.print("{X:02}\n", .{op_code});
    // std.debug.panic("", .{});
}

fn un_nop(_: *Cpu, _: u8) void {}

// Load

fn ld_rp_n16(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const p = y >> 1;
    const register = reg_p[p];
    const right = cpu.read();
    const value: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("LD {s},${x:04}\n", .{ register, value });
    reg_p_t[p].* = value;
}

fn ld_r_n8(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    const value = cpu.read();
    cpu.print("LD {s},${x:04}\n", .{ register, value });
    reg_8_t[y].* = value;
}

fn ld_r_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const z = op_code & 0b111;
    const register1 = reg_8[y];
    const register2 = reg_8[z];
    cpu.print("LD {s},{s}\n", .{ register1, register2 });
    reg_8_t[y].* = reg_8_t[z].*;
}

fn ld_bc_a(cpu: *Cpu, _: u8) void {
    cpu.print("LD (BC),A\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn ld_de_a(cpu: *Cpu, _: u8) void {
    cpu.print("LD (DE),A\n", .{});
    cpu.memory[de.full] = a_reg.*;
}

fn ld_a_bc(cpu: *Cpu, _: u8) void {
    cpu.print("LD A,(BC)\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn ld_a_de(cpu: *Cpu, _: u8) void {
    cpu.print("LD A,(DE)\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn ld_hli_a(cpu: *Cpu, _: u8) void {
    cpu.print("LD (HL+),A\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn ld_hld_a(cpu: *Cpu, _: u8) void {
    cpu.print("LD (HL-),A\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn ld_a_hli(cpu: *Cpu, _: u8) void {
    cpu.print("LD A,(HL+)\n", .{});
    a_reg.* = cpu.memory[hl.full];
    hl.full += 1;
}

fn ld_a_hld(cpu: *Cpu, _: u8) void {
    cpu.print("LD A,(HL-)\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn ld_a16_a(cpu: *Cpu, _: u8) void {
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("LD (${X:04}),A\n", .{address});
    std.debug.panic("Not implemented", .{});
}

fn ld_a_a16(cpu: *Cpu, _: u8) void {
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("LD A,${X:04},A\n", .{address});
    std.debug.panic("Not implemented", .{});
}

fn ld_a16_sp(cpu: *Cpu, _: u8) void {
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("LD ${X:04},SP\n", .{address});
    std.debug.panic("Not implemented", .{});
}

fn ldh_c_a(cpu: *Cpu, _: u8) void {
    cpu.print("LD ($FF00+C),A\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn ldh_a_c(cpu: *Cpu, _: u8) void {
    cpu.print("LD A,($FF00+C)\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn ldh_a8_a(cpu: *Cpu, _: u8) void {
    const displacement = cpu.read();
    cpu.print("LD ($FF00+${X}),A\n", .{displacement});
    std.debug.panic("Not implemented", .{});
}

fn ldh_a_a8(cpu: *Cpu, _: u8) void {
    const displacement = cpu.read();
    cpu.print("LD A,($FF00+${X})\n", .{displacement});
    std.debug.panic("Not implemented", .{});
}

fn ld_sp_hl(cpu: *Cpu, _: u8) void {
    cpu.print("LD SP,HL\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn ld_hl_sp_e8(cpu: *Cpu, _: u8) void {
    const displacement = cpu.read();
    const address = @as(u16, @bitCast(@as(i16, @bitCast(cpu.pc)) + @as(i8, @bitCast(displacement))));
    cpu.print("LD HL,SP+${X:02}\n", .{address});
    std.debug.panic("Not implemented", .{});
}

// Jumps

fn call_a16(cpu: *Cpu, _: u8) void {
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("CALL ${X:04}\n", .{address});
    std.debug.panic("Not implemented", .{});
}

fn call_cc_a16(cpu: *Cpu, op_code: u8) void {
    const register_index = op_code & 3;
    const condition = reg_cc[register_index];
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("CALL {s},${X:04}\n", .{ condition, address });
    std.debug.panic("Not implemented", .{});
}

fn jr_cc_e8(cpu: *Cpu, op_code: u8) void {
    const register_index = op_code & 3;
    const condition = reg_cc[register_index];
    const displacement = cpu.read();

    const address = @as(u16, @bitCast(@as(i16, @bitCast(cpu.pc)) + @as(i8, @bitCast(displacement))));
    cpu.print("JR {s},Addr_{x:04}\n", .{ condition, address });
    if (register_index == 0) {
        // NZ
        if (flags.z == 0) {
            cpu.pc = address;
        }
    } else if (register_index == 1) {
        // Z
        if (flags.z != 0) {
            cpu.pc = address;
        }
    } else {
        std.debug.panic("Not implemented", .{});
    }
}

fn jr_e8(cpu: *Cpu, _: u8) void {
    const displacement = cpu.read();
    const address = @as(u16, @bitCast(@as(i16, @bitCast(cpu.pc)) + @as(i8, @bitCast(displacement))));
    cpu.print("JR Addr_{x:04}\n", .{address});
    std.debug.panic("Not implemented", .{});
}

fn ret(cpu: *Cpu, _: u8) void {
    cpu.print("RET\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn reti(cpu: *Cpu, _: u8) void {
    cpu.print("RETI\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn ret_cc(cpu: *Cpu, op_code: u8) void {
    const register_index = op_code & 3;
    const condition = reg_cc[register_index];
    cpu.print("RET {s}\n", .{condition});
    std.debug.panic("Not implemented", .{});
}

fn jp_a16(cpu: *Cpu, _: u8) void {
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("JP Addr_{x:04}\n", .{address});
    cpu.pc = address;
}

fn jp_cc_a16(cpu: *Cpu, op_code: u8) void {
    const register_index = op_code & 3;
    const condition = reg_cc[register_index];

    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("JP {s},Addr_{x:04}\n", .{ condition, address });
    std.debug.panic("Not implemented", .{});
}

fn jp_hl(cpu: *Cpu, _: u8) void {
    cpu.print("JP HL\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn rst(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const vec = y * 8;
    cpu.print("RST Addr_{x:04}\n", .{vec});
    std.debug.panic("Not implemented", .{});
}

// Arithmetic

fn inc_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("INC {s}\n", .{register});
    var value: u8 = reg_8_t[y].*;
    if (value == 0xFF) {
        value = 0;
    } else {
        value += 1;
    }
    reg_8_t[y].* = value;
    if (value == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
    flags.n = 0;
    if (value > 0xF) {
        flags.h = 1;
    } else {
        flags.h = 0;
    }
}

fn inc_rp(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const p = y >> 1;
    const register = reg_p[p];
    cpu.print("INC {s}\n", .{register});
    reg_p_t[y].* += 1;
}

fn dec_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("DEC {s}\n", .{register});
    reg_8_t[y].* -= 1;
    if (reg_8_t[y].* == 0) {
        flags.z = 1;
    }
    flags.n = 1;
    // flags.h = 0;
}

fn dec_rp(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const p = y >> 1;
    const register = reg_p[p];
    cpu.print("DEC {s}\n", .{register});
    reg_p_t[y].* -= 1;
}

fn add_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("ADD {s}\n", .{register});
    std.debug.panic("Not implemented", .{});
}

fn add_hl_rp(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const p = y >> 1;
    const register = reg_p[p];
    cpu.print("ADD HL,{s}\n", .{register});
    std.debug.panic("Not implemented", .{});
}

fn add_sp_e8(cpu: *Cpu, _: u8) void {
    const displacement = cpu.read();
    const address = @as(u16, @bitCast(@as(i16, @bitCast(cpu.pc)) + @as(i8, @bitCast(displacement))));
    cpu.print("ADD SP,ADDR_${X:02}\n", .{address});
    std.debug.panic("Not implemented", .{});
}

fn sub_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("SUB {s}\n", .{register});
    std.debug.panic("Not implemented", .{});
}

fn adc_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("ADC {s}\n", .{register});
    std.debug.panic("Not implemented", .{});
}

fn sbc_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("SBC {s}\n", .{register});
    std.debug.panic("Not implemented", .{});
}

fn cp_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("CP {s}\n", .{register});
    std.debug.panic("Not implemented", .{});
}

fn alu_n8(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_alu[y];
    const address = cpu.read();
    cpu.print("{s} A,${X:02}\n", .{ register, address });
    std.debug.panic("Not implemented", .{});
}

// Bitwise logic

fn and_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("AND {s}\n", .{register});
    std.debug.panic("Not implemented", .{});
}

fn or_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("OR {s}\n", .{register});
    std.debug.panic("Not implemented", .{});
}

fn xor_r(cpu: *Cpu, op_code: u8) void {
    const register_index = op_code & 7;
    const register = reg_8[register_index];
    cpu.print("XOR A,{s}\n", .{register});
    // std.debug.panic("Not implemented", .{});
    a_reg.* = reg_8_t[register_index].* ^ a_reg.*;
    if (a_reg.* == 0) {
        flags.z = 1;
    }
    flags.n = 0;
    flags.h = 0;
    flags.c = 0;
}

// Stack

fn push_rp2(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const p = y >> 1;
    const register = reg_p2[p];
    cpu.print("PUSH {s}\n", .{register});
    std.debug.panic("Not implemented", .{});
}

fn pop_rp2(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const p = y >> 1;
    const register = reg_p2[p];
    cpu.print("POP {s}\n", .{register});
    std.debug.panic("Not implemented", .{});
}

// Bit shift

fn rlca(cpu: *Cpu, _: u8) void {
    cpu.print("RLCA\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn rrca(cpu: *Cpu, _: u8) void {
    cpu.print("RRCA\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn rla(cpu: *Cpu, _: u8) void {
    cpu.print("RLA\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn rra(cpu: *Cpu, _: u8) void {
    cpu.print("RRA\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn daa(cpu: *Cpu, _: u8) void {
    // Complicated
    // Uses N and H flags
    cpu.print("DAA\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn cpl(cpu: *Cpu, _: u8) void {
    cpu.print("CPL\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn scf(cpu: *Cpu, _: u8) void {
    cpu.print("SCF\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn ccf(cpu: *Cpu, _: u8) void {
    cpu.print("CCF\n", .{});
    std.debug.panic("Not implemented", .{});
}

// Interrupt

fn halt(cpu: *Cpu, _: u8) void {
    cpu.print("HALT\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn di(cpu: *Cpu, _: u8) void {
    cpu.print("HALT\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn ei(cpu: *Cpu, _: u8) void {
    cpu.print("HALT\n", .{});
    std.debug.panic("Not implemented", .{});
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
        std.debug.panic("Not implemented", .{});
    } else if (x == 1) {
        const register = reg_8[z];
        cpu.print("BIT {d},{s}\n", .{ y, register });
        std.debug.panic("Not implemented", .{});
    } else {
        cpu.print("NOP CB\n", .{});
        std.debug.panic("Not implemented", .{});
    }
}

fn stop(cpu: *Cpu, _: u8) void {
    _ = cpu.read();
    cpu.print("STOP\n", .{});
}

const reg_8: [8][]const u8 = .{ "B", "C", "D", "E", "H", "L", "(HL)", "A" };
var reg_8_t: [8]*u8 = .{ &bc.sp.hi, &bc.sp.lo, &de.sp.hi, &de.sp.lo, &hl.sp.hi, &hl.sp.lo, a_reg, a_reg };

const reg_p: [4][]const u8 = .{ "BC", "DE", "HL", "SP" };
const reg_p_t: [4]*u16 = .{ &bc.full, &de.full, &hl.full, &sp };

const reg_p2: [4][]const u8 = .{ "BC", "DE", "HL", "AF" };
const reg_p2_t: [4]*u16 = .{ &bc.full, &de.full, &hl.full, &af.af };

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
