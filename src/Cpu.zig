const std = @import("std");
const Self = @This();

// const x = op_code >> 6 & 0b11;
// const y = op_code >> 3 & 0b111;
// const z = op_code & 0b111;
// const p = y >> 1;
// const q = y & 1;

memory: []u8,
pc: u16,
counter: u32,
debug: bool,
should_print: bool,
should_break: bool,
std_out: std.fs.File.Writer,

pub fn cycle(self: *Self) void {
    const op_code = self.read();

    if (self.should_break and self.counter == 500000) {
        // if (verbose and self.pc == 0xdefb) {
        // if (verbose and sp == 0xdf7e) {
        self.should_print = true;
        @breakpoint();
    }

    op_lookup[op_code](self, op_code);
    self.counter += 1;
}
pub fn readMemory(self: *Self, address: u16) u8 {
    // LCD Hardcode
    if (address == 0xFF44) {
        return 0x90;
    }
    // main_memory[0xFF44] = 0;
    // main_memory[0xFF40] = 0b10100010;

    return self.memory[address];
}
fn getMemoryPointer(self: *Self, address: u16) *u8 {
    return &self.memory[address];
}
fn read(self: *Self) u8 {
    const memory_value = self.readMemory(self.pc);
    self.pc += 1;
    return memory_value;
}
fn printIndex(self: *Self) void {
    self.print("Current Index: {0d} {0x}\n", .{self.pc});
}
fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
    if (self.debug) {
        std.debug.print(fmt, args);
    }
}
fn printFlags(self: *Self) void {
    self.print("{b}\n", .{af.sp.flag.full});
    self.print("c: {b}\n", .{flags.c});
    self.print("h: {b}\n", .{flags.h});
    self.print("n: {b}\n", .{flags.n});
    self.print("z: {b}\n", .{flags.z});
}
pub fn logState(self: *Self) !void {
    if (!self.should_print) {
        return;
    }
    try self.std_out.print("A:{X:02} F:{X:02} B:{X:02} C:{X:02} D:{X:02} E:{X:02} H:{X:02} L:{X:02} SP:{X:04} PC:{X:04} PCMEM:{X:02},{X:02},{X:02},{X:02}\n", .{ a_reg.*, af.sp.flag.full, bc.sp.hi, bc.sp.lo, de.sp.hi, de.sp.lo, hl.sp.hi, hl.sp.lo, sp, self.pc, self.memory[self.pc], self.memory[self.pc + 1], self.memory[self.pc + 2], self.memory[self.pc + 3] });
}
fn getRegDataPointer(self: *Self, index: u8) *u8 {
    var data_pointer = reg_8_t[index];
    if (index == 6) {
        data_pointer = self.getMemoryPointer(hl.full);
    }
    return data_pointer;
}
fn checkCondition(_: *Self, index: u8) bool {
    return (index == 0 and flags.z == 0) or (index == 1 and flags.z != 0) or (index == 2 and flags.c == 0) or (index == 3 and flags.c != 0);
}

const SplitRegister = packed struct { lo: u8, hi: u8 };
const Register = packed union { full: u16, sp: SplitRegister };

const FlagRegister = packed struct { x: u4, c: u1, h: u1, n: u1, z: u1 };
const FlagRegisterUnion = packed union { full: u8, sp: FlagRegister };
const AfRegister = packed struct { flag: FlagRegisterUnion, a: u8 };
const AfRegisterFull = packed union { af: u16, sp: AfRegister };

var af = AfRegisterFull{ .af = 0x01b0 };
var bc = Register{ .full = 0x0013 };
var de = Register{ .full = 0x00d8 };
var hl = Register{ .full = 0x014d };
var sp: u16 = 0xfffe;
const a_reg = &af.sp.a;
const flags = &af.sp.flag.sp;

fn nop(_: *Self, _: u8) void {
    // std.debug.print("********** NOP ********** ${x:04}\n", .{self.index - 1});
    // std.debug.print("********** NOP **********\n", .{});
    // std.debug.print("{X:02}\n", .{op_code});
    // std.debug.panic("", .{});
}

fn nop_vd(_: *Self, _: u8) void {}

// Load

fn ld_rp_n16(self: *Self, op_code: u8) void {
    const p = op_code >> 4 & 0b11;
    const register = reg_p[p];
    const right = self.read();
    const value: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("LD {s},${x:04}\n", .{ register, value });
    reg_p_t[p].* = value;
}

fn ld_r_n8(self: *Self, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    const value = self.read();
    self.print("LD {s},${x:04}\n", .{ register, value });
    self.getRegDataPointer(y).* = value;
}

fn ld_r_r(self: *Self, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const z = op_code & 0b111;
    const register1 = reg_8[y];
    const register2 = reg_8[z];
    self.print("LD {s},{s}\n", .{ register1, register2 });
    self.getRegDataPointer(y).* = self.getRegDataPointer(z).*;
}

fn ld_bc_a(self: *Self, _: u8) void {
    self.print("LD (BC),A\n", .{});
    self.getMemoryPointer(bc.full).* = a_reg.*;
}

fn ld_de_a(self: *Self, _: u8) void {
    self.print("LD (DE),A\n", .{});
    self.getMemoryPointer(de.full).* = a_reg.*;
}

fn ld_a_bc(self: *Self, _: u8) void {
    self.print("LD A,(BC)\n", .{});
    a_reg.* = self.readMemory(bc.full);
}

fn ld_a_de(self: *Self, _: u8) void {
    self.print("LD A,(DE)\n", .{});
    a_reg.* = self.readMemory(de.full);
}

fn ld_hli_a(self: *Self, _: u8) void {
    self.print("LD (HL+),A\n", .{});
    self.getMemoryPointer(hl.full).* = a_reg.*;
    hl.full += 1;
}

fn ld_hld_a(self: *Self, _: u8) void {
    self.print("LD (HL-),A\n", .{});
    self.getMemoryPointer(hl.full).* = a_reg.*;
    hl.full -= 1;
}

fn ld_a_hli(self: *Self, _: u8) void {
    self.print("LD A,(HL+)\n", .{});
    a_reg.* = self.readMemory(hl.full);
    hl.full += 1;
}

fn ld_a_hld(self: *Self, _: u8) void {
    self.print("LD A,(HL-)\n", .{});
    a_reg.* = self.readMemory(hl.full);
    hl.full -= 1;
}

fn ld_a16_a(self: *Self, _: u8) void {
    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("LD (${X:04}),A\n", .{address});
    self.getMemoryPointer(address).* = a_reg.*;
}

fn ld_a_a16(self: *Self, _: u8) void {
    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("LD A,(${X:04})\n", .{address});
    a_reg.* = self.readMemory(address);
}

fn ld_a16_sp(self: *Self, _: u8) void {
    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("LD ${X:04},SP\n", .{address});
    self.getMemoryPointer(address).* = @truncate(sp);
    self.getMemoryPointer(address + 1).* = @truncate(sp >> 8);
}

fn ldh_c_a(self: *Self, _: u8) void {
    self.print("LD ($FF00+C),A\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn ldh_a_c(self: *Self, _: u8) void {
    self.print("LD A,($FF00+C)\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn ldh_a8_a(self: *Self, _: u8) void {
    const displacement = self.read();
    self.print("LD ($FF00+${X}),A\n", .{displacement});
    const address: u16 = @as(u16, 0xff00) + displacement;
    if (address > 0xFF00 and address < 0xFFFF) {
        self.getMemoryPointer(address).* = a_reg.*;
    }
}

fn ldh_a_a8(self: *Self, _: u8) void {
    const displacement = self.read();
    self.print("LD A,($FF00+${X})\n", .{displacement});
    const address: u16 = @as(u16, 0xff00) + displacement;
    a_reg.* = self.readMemory(address);
}

fn ld_sp_hl(self: *Self, _: u8) void {
    self.print("LD SP,HL\n", .{});
    sp = hl.full;
}

fn ld_hl_sp_e8(self: *Self, _: u8) void {
    const displacement = self.read();
    const address = @as(u16, @bitCast(@as(i16, @bitCast(self.pc)) + @as(i8, @bitCast(displacement))));
    self.print("LD HL,SP+${X:02}\n", .{address});
    std.debug.panic("Not implemented", .{});
}

// Jumps

fn call(self: *Self, address: u16) void {
    push(self, self.pc);
    self.pc = address;
}

fn call_a16(self: *Self, _: u8) void {
    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("CALL ${X:04}\n", .{address});
    call(self, address);
}

fn call_cc_a16(self: *Self, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const condition = reg_cc[y];
    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("CALL {s},${X:04}\n", .{ condition, address });
    if (self.checkCondition(y)) {
        call(self, address);
    }
}

fn jr_cc_e8(self: *Self, op_code: u8) void {
    const y_offset = op_code >> 3 & 0b111 - 4;
    const condition = reg_cc[y_offset];
    const displacement = self.read();
    const address = @as(u16, @bitCast(@as(i16, @bitCast(self.pc)) + @as(i8, @bitCast(displacement))));
    self.print("JR {s},Addr_{x:04}\n", .{ condition, address });
    if (self.checkCondition(y_offset)) {
        self.pc = address;
    }
}

fn jr_e8(self: *Self, _: u8) void {
    const displacement = self.read();
    const jump = @as(i8, @bitCast(displacement));
    const address = @as(u16, @bitCast(@as(i16, @bitCast(self.pc)) + jump));
    self.print("JR Addr_{x:04} {x:02}\n", .{ address, jump });
    self.pc = address;
}

fn ret(self: *Self, _: u8) void {
    self.print("RET\n", .{});
    self.pc = pop(self);
}

fn reti(self: *Self, op_code: u8) void {
    self.print("RETI\n", .{});
    ei(self, op_code);
    ret(self, op_code);
}

fn ret_cc(self: *Self, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const condition = reg_cc[y];
    self.print("RET {s}\n", .{condition});
    if (self.checkCondition(y)) {
        ret(self, 0);
    }
}

fn jp_a16(self: *Self, _: u8) void {
    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("JP Addr_{x:04}\n", .{address});
    self.pc = address;
}

fn jp_cc_a16(self: *Self, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const condition = reg_cc[y];

    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("JP {s},Addr_{x:04}\n", .{ condition, address });
    if (self.checkCondition(y)) {
        self.pc = address;
    }
}

fn jp_hl(self: *Self, _: u8) void {
    self.print("JP HL\n", .{});
    self.pc = hl.full;
}

fn rst(self: *Self, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const vec = y * 8;
    self.print("RST Addr_{x:04}\n", .{vec});
    call(self, vec);
}

fn push(self: *Self, value: u16) void {
    sp -= 1;
    self.getMemoryPointer(sp).* = @truncate(value >> 8);
    sp -= 1;
    self.getMemoryPointer(sp).* = @truncate(value);
}

fn pop(self: *Self) u16 {
    var new_value: u16 = @as(u16, self.readMemory(sp));
    sp += 1;
    new_value = new_value | (@as(u16, self.readMemory(sp)) << 8);
    sp += 1;
    return new_value;
}

// Arithmetic

fn inc_r(self: *Self, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    self.print("INC {s}\n", .{register});
    const data_pointer = self.getRegDataPointer(y);
    var value: u8 = data_pointer.*;
    const overflow = value >> 4 & 1;
    if (value == 0xFF) {
        value = 0;
    } else {
        value += 1;
    }
    data_pointer.* = value;
    if (value == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
    flags.n = 0;
    const new_overflow = value >> 4 & 1;
    if (new_overflow != overflow) {
        flags.h = 1;
    } else {
        flags.h = 0;
    }
}

fn inc_rp(self: *Self, op_code: u8) void {
    const p = op_code >> 4 & 0b11;
    const register = reg_p[p];
    self.print("INC {s}\n", .{register});
    const data_pointer = reg_p_t[p];
    const result = @addWithOverflow(data_pointer.*, 1);
    data_pointer.* = result[0];
}

fn dec_r(self: *Self, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    self.print("DEC {s}\n", .{register});
    const data_pointer = self.getRegDataPointer(y);
    const current_value = data_pointer.*;
    const result = @subWithOverflow(current_value, 1);
    data_pointer.* = result[0];
    flags.n = 1;
    const half_result = @subWithOverflow(@as(u4, @truncate(current_value)), @as(u4, @truncate(1)));
    flags.h = half_result[1];
    if (data_pointer.* == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
}

fn dec_rp(self: *Self, op_code: u8) void {
    const p = op_code >> 4 & 0b11;
    const register = reg_p[p];
    self.print("DEC {s}\n", .{register});
    reg_p_t[p].* -= 1;
}

fn add_r(self: *Self, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    self.print("ADD {s}\n", .{register});
    std.debug.panic("Not implemented", .{});
}

fn add_hl_rp(self: *Self, op_code: u8) void {
    const p = op_code >> 4 & 0b11;
    const register = reg_p[p];
    self.print("ADD HL,{s}\n", .{register});
    const current_value = reg_p_t[p].*;
    const result = @addWithOverflow(hl.full, current_value);
    const half_result = @addWithOverflow(@as(u12, @truncate(hl.full)), @as(u12, @truncate(current_value)));
    hl.full = result[0];
    flags.n = 0;
    flags.h = half_result[1];
    flags.c = result[1];
}

fn add_sp_e8(self: *Self, _: u8) void {
    const displacement = self.read();
    const address = @as(u16, @bitCast(@as(i16, @bitCast(self.pc)) + @as(i8, @bitCast(displacement))));
    self.print("ADD SP,ADDR_${X:02}\n", .{address});
    std.debug.panic("Not implemented", .{});
}

fn sub_r(self: *Self, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    self.print("SUB {s}\n", .{register});
    std.debug.panic("Not implemented", .{});
}

fn adc_r(self: *Self, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    self.print("ADC {s}\n", .{register});
    std.debug.panic("Not implemented", .{});
}

fn sbc_r(self: *Self, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    self.print("SBC {s}\n", .{register});
    std.debug.panic("Not implemented", .{});
}

fn cp_r(self: *Self, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    self.print("CP {s}\n", .{register});
    std.debug.panic("Not implemented", .{});
}

fn alu_n8(self: *Self, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_alu[y];
    var change = self.read();
    const current_value = a_reg.*;
    self.print("{s} A,${X:02}\n", .{ register, change });
    var new_value = current_value;
    if (y == 0) {
        // ADD
        const result = @addWithOverflow(current_value, change);
        new_value = result[0];
        a_reg.* = new_value;
        flags.c = result[1];
        flags.n = 0;
        const half_result = @addWithOverflow(@as(u4, @truncate(current_value)), @as(u4, @truncate(change)));
        flags.h = half_result[1];
    } else if (y == 1) {
        // ADC
        change += flags.c;
        const result = @addWithOverflow(current_value, change);
        new_value = result[0];
        a_reg.* = new_value;
        flags.c = result[1];
        flags.n = 0;
        const half_result = @addWithOverflow(@as(u4, @truncate(current_value)), @as(u4, @truncate(change)));
        flags.h = half_result[1];
    } else if (y == 2) {
        // SUB
        const result = @subWithOverflow(current_value, change);
        flags.c = result[1];
        new_value = result[0];
        a_reg.* = new_value;
        flags.n = 1;
        const half_result = @subWithOverflow(@as(u4, @truncate(current_value)), @as(u4, @truncate(change)));
        flags.h = half_result[1];
    } else if (y == 4) {
        // AND
        new_value = current_value & change;
        a_reg.* = new_value;
        flags.n = 0;
        flags.h = 1;
        flags.c = 0;
    } else if (y == 5) {
        // XOR
        new_value = current_value ^ change;
        a_reg.* = new_value;
        flags.n = 0;
        flags.h = 0;
        flags.c = 0;
    } else if (y == 7) {
        // CP
        const result = @subWithOverflow(current_value, change);
        new_value = result[0];
        flags.c = result[1];
        flags.n = 1;
        const half_result = @subWithOverflow(@as(u4, @truncate(current_value)), @as(u4, @truncate(change)));
        flags.h = half_result[1];
    } else {
        std.debug.panic("Not implemented: {s}", .{register});
    }
    if (new_value & 0xFF == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
}

// Bitwise logic

fn and_r(self: *Self, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    self.print("AND A,{s}\n", .{register});
    std.debug.panic("Not implemented", .{});
}

fn or_r(self: *Self, op_code: u8) void {
    const z = op_code & 0b111;
    const register = reg_8[z];
    self.print("OR A,{s}\n", .{register});
    a_reg.* = a_reg.* | self.getRegDataPointer(z).*;
    if (a_reg.* == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
    flags.n = 0;
    flags.h = 0;
    flags.c = 0;
}

fn xor_r(self: *Self, op_code: u8) void {
    const z = op_code & 0b111;
    const register = reg_8[z];
    self.print("XOR A,{s}\n", .{register});
    a_reg.* = self.getRegDataPointer(z).* ^ a_reg.*;
    if (a_reg.* == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
    flags.n = 0;
    flags.h = 0;
    flags.c = 0;
}

// Stack

fn push_rp2(self: *Self, op_code: u8) void {
    const p = op_code >> 4 & 0b11;
    const register = reg_p2[p];
    self.print("PUSH {s}\n", .{register});
    push(self, reg_p2_t[p].*);
}

fn pop_rp2(self: *Self, op_code: u8) void {
    const p = op_code >> 4 & 0b11;
    const register = reg_p2[p];
    self.print("POP {s}\n", .{register});
    reg_p2_t[p].* = pop(self);
}

// Bit shift

fn rlca(self: *Self, _: u8) void {
    self.print("RLCA\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn rrca(self: *Self, _: u8) void {
    self.print("RRCA\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn rla(self: *Self, _: u8) void {
    self.print("RLA\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn rra(self: *Self, _: u8) void {
    self.print("RRA\n", .{});
    const old_c: u8 = flags.c;
    flags.c = @truncate(a_reg.* & 0x1);
    a_reg.* = (a_reg.* >> 1) | (old_c << 7);
    flags.n = 0;
    flags.h = 0;
    flags.z = 0;
}

fn daa(self: *Self, _: u8) void {
    // Complicated
    // Uses N and H flags
    self.print("DAA\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn cpl(self: *Self, _: u8) void {
    self.print("CPL\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn scf(self: *Self, _: u8) void {
    self.print("SCF\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn ccf(self: *Self, _: u8) void {
    self.print("CCF\n", .{});
    std.debug.panic("Not implemented", .{});
}

// Interrupt

fn halt(self: *Self, _: u8) void {
    self.print("HALT\n", .{});
    std.debug.panic("Not implemented", .{});
}

fn di(self: *Self, _: u8) void {
    self.print("DI\n", .{});
}

fn ei(self: *Self, _: u8) void {
    self.print("EI\n", .{});
}

// CB

fn cb_prefix(self: *Self, _: u8) void {
    const op_code = self.read();
    const x = op_code >> 6 & 0b11;
    const y = op_code >> 3 & 0b111;
    const z = op_code & 0b111;
    if (x == 0) {
        const operation = reg_rot[y];
        const register = reg_8[z];
        self.print("{s} {s}\n", .{ operation, register });
        const data_pointer = self.getRegDataPointer(z);
        if (y == 3) {
            // RR
            const old_c: u8 = flags.c;
            flags.c = @truncate(data_pointer.* & 0x1);
            data_pointer.* = (data_pointer.* >> 1) | (old_c << 7);
            flags.n = 0;
            flags.h = 0;
            if (data_pointer.* == 0) {
                flags.z = 1;
            } else {
                flags.z = 0;
            }
        } else if (y == 4) {
            // SLA
            const result = @shlWithOverflow(data_pointer.*, 0x1);
            flags.c = result[1];
            data_pointer.* = result[0];
            flags.n = 0;
            flags.h = 0;
            if (data_pointer.* == 0) {
                flags.z = 1;
            } else {
                flags.z = 0;
            }
        } else if (y == 7) {
            // SRL
            flags.c = @truncate(data_pointer.* & 0x1);
            data_pointer.* = data_pointer.* >> 1;
            flags.n = 0;
            flags.h = 0;
            if (data_pointer.* == 0) {
                flags.z = 1;
            } else {
                flags.z = 0;
            }
        } else {
            std.debug.panic("Not implemented x:{d}, y:{d}, z:{d}", .{ x, y, z });
        }
    } else if (x == 1) {
        const register = reg_8[z];
        self.print("BIT {d},{s}\n", .{ y, register });
        std.debug.panic("BIT Not implemented x:{d}, y:{d}, z:{d}", .{ x, y, z });
    } else {
        self.print("NOP CB\n", .{});
        std.debug.panic("Not implemented x:{d}, y:{d}, z:{d}", .{ x, y, z });
    }
}

fn stop(self: *Self, _: u8) void {
    _ = self.read();
    self.print("STOP\n", .{});
}

const reg_8: [8][]const u8 = .{ "B", "C", "D", "E", "H", "L", "(HL)", "A" };
var reg_8_t: [8]*u8 = .{ &bc.sp.hi, &bc.sp.lo, &de.sp.hi, &de.sp.lo, &hl.sp.hi, &hl.sp.lo, a_reg, a_reg };

const reg_p: [4][]const u8 = .{ "BC", "DE", "HL", "SP" };
const reg_p_t: [4]*u16 = .{ &bc.full, &de.full, &hl.full, &sp };

const reg_p2: [4][]const u8 = .{ "BC", "DE", "HL", "AF" };
const reg_p2_t: [4]*u16 = .{ &bc.full, &de.full, &hl.full, &af.af };

const reg_cc: [4][]const u8 = .{ "NZ", "Z", "NC", "C" };

const reg_alu: [8][]const u8 = .{ "ADD", "ADC", "SUB", "SBC", "AND", "XOR", "OR", "CP" };

const reg_rot: [8][]const u8 = .{ "RLC", "RRC", "RL", "RR", "SLA", "SRA", "SWAP", "SRL" };

// zig fmt: off
const op_lookup = [256] *const fn (*Self, u8) void { 
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
    ret_cc,      pop_rp2,   jp_cc_a16, nop_vd,    call_cc_a16, push_rp2, alu_n8,  rst,    // D
    ret_cc,      reti,      jp_cc_a16, nop_vd,    call_cc_a16, nop_vd,   alu_n8,  rst,   
    ldh_a8_a,    pop_rp2,   ldh_c_a,   nop_vd,    nop_vd,      push_rp2, alu_n8,  rst,    // E
    add_sp_e8,   jp_hl,     ld_a16_a,  nop_vd,    nop_vd,      nop_vd,   alu_n8,  rst,   
    ldh_a_a8,    pop_rp2,   ldh_a_c,   di,        nop_vd,      push_rp2, alu_n8,  rst,    // F
    ld_hl_sp_e8, ld_sp_hl,  ld_a_a16,  ei,        nop_vd,      nop_vd,   alu_n8,  rst
    };
// zig fmt: on
