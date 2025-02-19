const std = @import("std");
const Self = @This();
const utils = @import("utils.zig");

memory: []u8,
pc: u16,
counter: u32,
debug: bool,
verbose: bool,
should_print: bool,
std_out: std.fs.File.Writer,
is_doctor_test: bool,
ime: u1,
extra_dots: u8,
extra_timer_cycles: u10,
div_counter: u10,
halted: bool,

pub fn create(allocator: *const std.mem.Allocator, main_memory: []u8, start_pc: u16, std_out: std.fs.File.Writer) !*Self {
    const cpu = try allocator.create(Self);

    cpu.* = .{
        .memory = main_memory,
        .pc = start_pc,
        .counter = 1,
        .should_print = false,
        .debug = false,
        .verbose = false,
        .std_out = std_out,
        .is_doctor_test = false,
        .ime = 0,
        .extra_dots = 0,
        .extra_timer_cycles = 0,
        .div_counter = 0,
        .halted = false,
    };
    return cpu;
}

pub fn cycle(self: *Self) u8 {
    if (self.halted) {
        return 4;
    }
    const op_code = self.read();
    self.counter = @addWithOverflow(self.counter, 1)[0];
    return op_lookup[op_code](self, op_code);
}

pub fn handleInterrupts(self: *Self) u8 {
    if (self.ime == 0) {
        return 0;
    }
    const enabled = self.getMemoryPointer(0xFFFF);
    const flag = self.getMemoryPointer(0xFF0F);
    if (enabled.* == 0 or flag.* == 0) {
        return 0;
    }
    if (self.handleInterrupt(enabled, flag, 0, 0x40)) {
        // VBlank
        return 20;
    }
    if (self.handleInterrupt(enabled, flag, 1, 0x48)) {
        // LCD
        return 20;
    }
    if (self.handleInterrupt(enabled, flag, 2, 0x50)) {
        // Timer
        return 20;
    }
    if (self.handleInterrupt(enabled, flag, 3, 0x58)) {
        // Serial
        return 20;
    }
    if (self.handleInterrupt(enabled, flag, 4, 0x60)) {
        // Joypad
        return 20;
    }
    return 0;
}

fn handleInterrupt(self: *Self, enabled: *u8, flag: *u8, shift: u3, address: u16) bool {
    const is_enabled = (enabled.* >> shift) & 0b1;
    const is_flagged = (flag.* >> shift) & 0b1;
    if (is_enabled == 1 and is_flagged == 1) {
        self.halted = false;
        self.ime = 0;
        utils.resetBit(flag, shift);
        call_int(self, address);
        return true;
    }
    return false;
}

pub fn requestInterrupt(self: *Self, bit_num: u3) void {
    utils.setBit(self.getMemoryPointer(0xFF0F), bit_num);
}

pub fn handleTimer(self: *Self, dots: u8) void {
    self.extra_dots += dots;
    const cycles: u8 = self.extra_dots / 4;
    self.extra_dots = self.extra_dots % 4;
    self.div_counter += cycles;
    if (self.div_counter > 64) {
        self.div_counter -= 64;
        const div_pointer = self.getMemoryPointer(0xFF04);
        const div_result = @addWithOverflow(div_pointer.*, 1);
        div_pointer.* = div_result[0];
    }
    const tac = self.readMemory(0xFF07);
    const enabled = (tac >> 2) & 0b1;
    if (enabled == 1) {
        const timer_pointer = self.getMemoryPointer(0xFF05);
        const clock_select: u10 = switch (tac & 0x11) {
            1 => 4,
            2 => 16,
            3 => 64,
            else => 256,
        };
        self.extra_timer_cycles += cycles;
        const ticks: u8 = @truncate(self.extra_timer_cycles / clock_select);
        self.extra_timer_cycles -= ticks * clock_select;
        const timer_result = @addWithOverflow(timer_pointer.*, ticks);
        if (timer_result[1] == 1) {
            // Set timer interrupt
            self.requestInterrupt(2);
            // Timer modulo
            timer_pointer.* = self.readMemory(0xFF06);
            self.halted = false;
        } else {
            timer_pointer.* = timer_result[0];
        }
    }
}

pub fn readMemory(self: *Self, address: u16) u8 {
    // LCD Hardcode
    if (address == 0xFF44) {
        if (self.is_doctor_test) {
            return 0x90; // 144 = VBlank
        }
    }
    // if (address == 0xFF42) {
    //     return 0;
    // }
    // main_memory[0xFF44] = 0;
    // main_memory[0xFF40] = 0b10100010;

    return self.getMemoryPointer(address).*;
}

pub fn writeMemory(self: *Self, address: u16, value: u8) void {
    self.memory[address] = value;
    if (address == 0xFF46) {
        // OAM DMA
        self.dma(value);
        @breakpoint();
    }
}

pub fn getMemoryPointer(self: *Self, address: u16) *u8 {
    if (address == 0xFF46) {
        // OAM DMA
        @breakpoint();
    }
    // if (address == 0xFF45) {
    //     @breakpoint();
    //     std.debug.print("{X:02} - Pointer\n", .{self.memory[address]});
    // }
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
    if (self.should_print and self.debug) {
        std.debug.print(fmt, args);
    }
}

pub fn printFlags(self: *Self) void {
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
    try self.std_out.print("A:{X:02} F:{X:02} B:{X:02} C:{X:02} D:{X:02} E:{X:02} H:{X:02} L:{X:02} SP:{X:04} PC:{X:04} PCMEM:{X:02},{X:02},{X:02},{X:02}\n", .{
        a_reg.*,
        af.sp.flag.full,
        bc.sp.hi,
        bc.sp.lo,
        de.sp.hi,
        de.sp.lo,
        hl.sp.hi,
        hl.sp.lo,
        sp,
        self.pc,
        self.readMemory(self.pc),
        self.readMemory(self.pc + 1),
        self.readMemory(self.pc + 2),
        self.readMemory(self.pc + 3),
    });
}

fn getRegDataPointer(self: *Self, index: u8) *u8 {
    if (index == 6) {
        return self.getMemoryPointer(hl.full);
    } else {
        return reg_8_t[index];
    }
}

fn getRegDataValue(self: *Self, index: u8) u8 {
    if (index == 6) {
        return self.readMemory(hl.full);
    } else {
        return reg_8_t[index].*;
    }
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
var sp: u16 = 0xFFFE;
const a_reg = &af.sp.a;
const flags = &af.sp.flag.sp;

fn nop(_: *Self, _: u8) u8 {
    return 4;
}

fn nop_vd(_: *Self, _: u8) u8 {
    return 4;
    // std.debug.panic("Unknown behavior", .{});
}

fn dma(self: *Self, address_index: u8) void {
    // std.debug.print("Index: {x}\n", .{address_index});
    const source_start: u16 = @as(u16, address_index) << 8;
    // var i: usize = 0;
    // while (i < 100) : (i += 1) {
    //     std.debug.print("Before: {x} {x}\n", .{ self.memory[source_start + i], self.memory[0xFE00 + i] });
    // }
    const source_end: u16 = source_start | 0x9F;
    const source = self.memory[source_start..source_end];
    // for (source) |temp| {
    //     if (temp != 0) {
    //         std.debug.print("Before: {x}\n", .{temp});
    //     }
    // }
    const destination = self.memory[0xFE00..0xFE9F];
    @memcpy(destination, source);
    // i = 0;
    // while (i < 100) : (i += 1) {
    //     std.debug.print("After: {x} {x}\n", .{ self.memory[source_start + i], self.memory[0xFE00 + i] });
    // }
}

// Load

fn ld_rp_n16(self: *Self, op_code: u8) u8 {
    const p: u2 = @truncate(op_code >> 4);
    const register = reg_p[p];
    const right = self.read();
    const value: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("LD {s},${x:04}\n", .{ register, value });
    reg_p_t[p].* = value;
    return 12;
}

fn ld_r_n8(self: *Self, op_code: u8) u8 {
    const y: u3 = @truncate(op_code >> 3);
    const register = reg_8[y];
    const value = self.read();
    self.print("LD {s},${x:04}\n", .{ register, value });
    self.getRegDataPointer(y).* = value;
    if (y == 6) {
        return 12;
    }
    return 8;
}

fn ld_r_r(self: *Self, op_code: u8) u8 {
    const y: u3 = @truncate(op_code >> 3);
    const z: u3 = @truncate(op_code);
    const register1 = reg_8[y];
    const register2 = reg_8[z];
    self.print("LD {s},{s}\n", .{ register1, register2 });
    if (y == z) {
        // Software breakpoint
        // @breakpoint();
    }
    self.getRegDataPointer(y).* = self.getRegDataValue(z);
    if (y == 6 or z == 6) {
        return 8;
    }
    return 4;
}

fn ld_bc_a(self: *Self, _: u8) u8 {
    self.print("LD (BC),A\n", .{});
    self.getMemoryPointer(bc.full).* = a_reg.*;
    return 8;
}

fn ld_de_a(self: *Self, _: u8) u8 {
    self.print("LD (DE),A\n", .{});
    self.getMemoryPointer(de.full).* = a_reg.*;
    return 8;
}

fn ld_a_bc(self: *Self, _: u8) u8 {
    self.print("LD A,(BC)\n", .{});
    a_reg.* = self.readMemory(bc.full);
    return 8;
}

fn ld_a_de(self: *Self, _: u8) u8 {
    self.print("LD A,(DE)\n", .{});
    a_reg.* = self.readMemory(de.full);
    return 8;
}

fn ld_hli_a(self: *Self, _: u8) u8 {
    self.print("LD (HL+),A\n", .{});
    self.getMemoryPointer(hl.full).* = a_reg.*;
    hl.full += 1;
    return 8;
}

fn ld_hld_a(self: *Self, _: u8) u8 {
    self.print("LD (HL-),A\n", .{});
    self.getMemoryPointer(hl.full).* = a_reg.*;
    hl.full -= 1;
    return 8;
}

fn ld_a_hli(self: *Self, _: u8) u8 {
    self.print("LD A,(HL+)\n", .{});
    a_reg.* = self.readMemory(hl.full);
    hl.full += 1;
    return 8;
}

fn ld_a_hld(self: *Self, _: u8) u8 {
    self.print("LD A,(HL-)\n", .{});
    a_reg.* = self.readMemory(hl.full);
    hl.full -= 1;
    return 8;
}

fn ld_a16_a(self: *Self, _: u8) u8 {
    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("LD (${X:04}),A\n", .{address});
    self.getMemoryPointer(address).* = a_reg.*;
    return 16;
}

fn ld_a_a16(self: *Self, _: u8) u8 {
    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("LD A,(${X:04})\n", .{address});
    a_reg.* = self.readMemory(address);
    return 16;
}

fn ldh_c_a(self: *Self, _: u8) u8 {
    self.print("LD ($FF00+C),A\n", .{});
    const address: u16 = @as(u16, 0xFF00) + bc.sp.lo;
    self.getMemoryPointer(address).* = a_reg.*;
    return 8;
}

fn ldh_a_c(self: *Self, _: u8) u8 {
    self.print("LD A,($FF00+C)\n", .{});
    const address: u16 = @as(u16, 0xFF00) + bc.sp.lo;
    a_reg.* = self.readMemory(address);
    return 8;
}

fn ldh_a8_a(self: *Self, _: u8) u8 {
    const displacement = self.read();
    self.print("LD ($FF00+${X}),A\n", .{displacement});
    const address: u16 = @as(u16, 0xFF00) + displacement;
    if (address >= 0xFF00 and address <= 0xFFFF) {
        self.writeMemory(address, a_reg.*);
    } else {
        std.debug.panic("Bad Address", .{});
    }
    return 12;
}

fn ldh_a_a8(self: *Self, _: u8) u8 {
    const displacement = self.read();
    self.print("LD A,($FF00+${X})\n", .{displacement});
    const address: u16 = @as(u16, 0xFF00) + displacement;
    if (address >= 0xFF00 and address <= 0xFFFF) {
        a_reg.* = self.readMemory(address);
    } else {
        std.debug.panic("Bad Address", .{});
    }
    return 12;
}

// Jumps

fn call_int(self: *Self, address: u16) void {
    push_int(self, self.pc);
    self.pc = address;
}

fn call_a16(self: *Self, _: u8) u8 {
    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("CALL ${X:04}\n", .{address});
    call_int(self, address);
    return 24;
}

fn call_cc_a16(self: *Self, op_code: u8) u8 {
    const y: u3 = @truncate(op_code >> 3);
    const condition = reg_cc[y];
    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("CALL {s},${X:04}\n", .{ condition, address });
    if (self.checkCondition(y)) {
        call_int(self, address);
        return 24;
    }
    return 12;
}

fn jr_cc_e8(self: *Self, op_code: u8) u8 {
    const y_offset: u3 = @truncate((op_code >> 3) - 4);
    const condition = reg_cc[y_offset];
    const displacement = self.read();
    const address: u16 = @truncate(@as(u17, @bitCast(@as(i17, self.pc) + @as(i8, @bitCast(displacement)))));
    self.print("JR {s},Addr_{x:04}\n", .{ condition, address });
    if (self.checkCondition(y_offset)) {
        self.pc = address;
        return 12;
    }
    return 8;
}

fn jr_e8(self: *Self, _: u8) u8 {
    const displacement: i8 = @bitCast(self.read());
    const address: u16 = @truncate(@as(u17, @bitCast(@as(i17, self.pc) + displacement)));
    self.print("JR Addr_{x:04}\n", .{address});
    self.pc = address;
    return 12;
}

fn ret(self: *Self, _: u8) u8 {
    self.print("RET\n", .{});
    self.pc = pop_int(self);
    return 16;
}

fn ret_cc(self: *Self, op_code: u8) u8 {
    const y: u3 = @truncate(op_code >> 3);
    const condition = reg_cc[y];
    self.print("RET {s}\n", .{condition});
    if (self.checkCondition(y)) {
        _ = ret(self, 0);
        return 20;
    }
    return 8;
}

fn reti(self: *Self, op_code: u8) u8 {
    self.print("RETI\n", .{});
    _ = ei(self, op_code);
    _ = ret(self, op_code);
    return 16;
}

fn jp_a16(self: *Self, _: u8) u8 {
    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("JP Addr_{x:04}\n", .{address});
    self.pc = address;
    return 16;
}

fn jp_cc_a16(self: *Self, op_code: u8) u8 {
    const y: u3 = @truncate(op_code >> 3);
    const condition = reg_cc[y];

    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("JP {s},Addr_{x:04}\n", .{ condition, address });
    if (self.checkCondition(y)) {
        self.pc = address;
        return 16;
    }
    return 12;
}

fn jp_hl(self: *Self, _: u8) u8 {
    self.print("JP HL\n", .{});
    self.pc = hl.full;
    return 4;
}

fn rst(self: *Self, op_code: u8) u8 {
    const y: u3 = @truncate(op_code >> 3);
    const vec: u16 = @as(u16, y) * 8;
    self.print("RST Addr_{x:04}\n", .{vec});
    call_int(self, vec);
    return 16;
}

fn push_int(self: *Self, value: u16) void {
    sp -= 1;
    self.getMemoryPointer(sp).* = @truncate(value >> 8);
    sp -= 1;
    self.getMemoryPointer(sp).* = @truncate(value);
}

fn pop_int(self: *Self) u16 {
    var new_value: u16 = @as(u16, self.readMemory(sp));
    sp += 1;
    new_value = new_value | (@as(u16, self.readMemory(sp)) << 8);
    sp += 1;
    return new_value;
}

// Arithmetic

fn adc_r(self: *Self, op_code: u8) u8 {
    const z: u3 = @truncate(op_code);
    const register = reg_8[z];
    self.print("ADC {s}\n", .{register});
    adc_int(self.getRegDataValue(z));
    if (z == 6) {
        return 8;
    }
    return 4;
}

fn adc_int(change: u8) void {
    const change_result = @addWithOverflow(change, flags.c);
    const result = @addWithOverflow(a_reg.*, change_result[0]);
    const change_half_result = @addWithOverflow(@as(u4, @truncate(change)), flags.c);
    const half_result = @addWithOverflow(@as(u4, @truncate(a_reg.*)), change_half_result[0]);
    flags.c = result[1] | change_result[1];
    flags.h = half_result[1] | change_half_result[1];
    a_reg.* = result[0];
    flags.n = 0;
    if (result[0] & 0xFF == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
}

fn add_r(self: *Self, op_code: u8) u8 {
    const z: u3 = @truncate(op_code);
    const register = reg_8[z];
    self.print("ADD {s}\n", .{register});
    add_int(self.getRegDataValue(z));
    if (z == 6) {
        return 8;
    }
    return 4;
}

fn add_hl_rp(self: *Self, op_code: u8) u8 {
    const p: u2 = @truncate(op_code >> 4);
    const register = reg_p[p];
    self.print("ADD HL,{s}\n", .{register});
    const current_value = reg_p_t[p].*;
    const result = @addWithOverflow(hl.full, current_value);
    const half_result = @addWithOverflow(@as(u12, @truncate(hl.full)), @as(u12, @truncate(current_value)));
    hl.full = result[0];
    flags.n = 0;
    flags.h = half_result[1];
    flags.c = result[1];
    return 8;
}

fn add_int(change: u8) void {
    const result = @addWithOverflow(a_reg.*, change);
    const half_result = @addWithOverflow(@as(u4, @truncate(a_reg.*)), @as(u4, @truncate(change)));
    a_reg.* = result[0];
    flags.c = result[1];
    flags.n = 0;
    flags.h = half_result[1];
    if (result[0] & 0xFF == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
}

fn cp_r(self: *Self, op_code: u8) u8 {
    const z: u3 = @truncate(op_code);
    const register = reg_8[z];
    self.print("CP {s}\n", .{register});
    cp_int(self.getRegDataValue(z));
    if (z == 6) {
        return 8;
    }
    return 4;
}

fn cp_int(value: u8) void {
    const result = @subWithOverflow(a_reg.*, value);
    flags.c = result[1];
    flags.n = 1;
    const half_result = @subWithOverflow(@as(u4, @truncate(a_reg.*)), @as(u4, @truncate(value)));
    flags.h = half_result[1];
    if (result[0] & 0xFF == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
}

fn dec_r(self: *Self, op_code: u8) u8 {
    const y: u3 = @truncate(op_code >> 3);
    const register = reg_8[y];
    self.print("DEC {s}\n", .{register});
    const pointer = self.getRegDataPointer(y);
    const half_result = @subWithOverflow(@as(u4, @truncate(pointer.*)), 1);
    flags.h = half_result[1];
    flags.n = 1;
    const result = @subWithOverflow(pointer.*, 1);
    pointer.* = result[0];
    if (pointer.* == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
    if (y == 6) {
        return 12;
    }
    return 4;
}

fn dec_rp(self: *Self, op_code: u8) u8 {
    const p: u2 = @truncate(op_code >> 4);
    const register = reg_p[p];
    self.print("DEC {s}\n", .{register});
    const pointer = reg_p_t[p];
    const result = @subWithOverflow(pointer.*, 1);
    pointer.* = result[0];
    return 8;
}

fn inc_r(self: *Self, op_code: u8) u8 {
    const y: u3 = @truncate(op_code >> 3);
    const register = reg_8[y];
    self.print("INC {s}\n", .{register});
    const pointer = self.getRegDataPointer(y);

    const half_result = @addWithOverflow(@as(u4, @truncate(pointer.*)), 1);
    flags.h = half_result[1];
    flags.n = 0;
    const result = @addWithOverflow(pointer.*, 1);
    pointer.* = result[0];
    if (pointer.* == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
    if (y == 6) {
        return 12;
    }
    return 4;
}

fn inc_rp(self: *Self, op_code: u8) u8 {
    const p: u2 = @truncate(op_code >> 4);
    const register = reg_p[p];
    self.print("INC {s}\n", .{register});
    const pointer = reg_p_t[p];
    const result = @addWithOverflow(pointer.*, 1);
    pointer.* = result[0];
    return 8;
}

fn sbc_r(self: *Self, op_code: u8) u8 {
    const z: u3 = @truncate(op_code);
    const register = reg_8[z];
    self.print("SBC {s}\n", .{register});
    sbc_int(self.getRegDataValue(z));
    if (z == 6) {
        return 8;
    }
    return 4;
}

fn sbc_int(change: u8) void {
    const result = @subWithOverflow(a_reg.*, change);
    const change_result = @subWithOverflow(result[0], flags.c);

    const half_result = @subWithOverflow(@as(u4, @truncate(a_reg.*)), @as(u4, @truncate(change)));
    const change_half_result = @subWithOverflow(@as(u4, @truncate(half_result[0])), flags.c);

    flags.c = result[1] | change_result[1];
    flags.h = half_result[1] | change_half_result[1];
    a_reg.* = change_result[0];
    flags.n = 1;
    if (change_result[0] & 0xFF == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
}

fn sub_r(self: *Self, op_code: u8) u8 {
    const z: u3 = @truncate(op_code);
    const register = reg_8[z];
    self.print("SUB {s}\n", .{register});
    sub_int(self.getRegDataValue(z));
    if (z == 6) {
        return 8;
    }
    return 4;
}

fn sub_int(value: u8) void {
    const result = @subWithOverflow(a_reg.*, value);
    flags.c = result[1];
    flags.n = 1;
    const half_result = @subWithOverflow(@as(u4, @truncate(a_reg.*)), @as(u4, @truncate(value)));
    flags.h = half_result[1];
    a_reg.* = result[0];
    if (result[0] & 0xFF == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
}

fn alu_n8(self: *Self, op_code: u8) u8 {
    const y: u3 = @truncate(op_code >> 3);
    const register = reg_alu[y];
    const change = self.read();
    self.print("{s} A,${X:02}\n", .{ register, change });
    if (y == 0) {
        // ADD
        add_int(change);
        return 8;
    } else if (y == 1) {
        // ADC
        adc_int(change);
        return 8;
    } else if (y == 2) {
        // SUB
        sub_int(change);
        return 8;
    } else if (y == 3) {
        // SBC
        sbc_int(change);
        return 8;
    } else if (y == 4) {
        // AND
        and_int(change);
        return 8;
    } else if (y == 5) {
        // XOR
        xor_int(change);
        return 8;
    } else if (y == 6) {
        // OR
        or_int(change);
        return 8;
    } else if (y == 7) {
        // CP
        cp_int(change);
        return 8;
    }
    std.debug.panic("Unknown: {s}", .{register});
}

// Bitwise logic

fn and_r(self: *Self, op_code: u8) u8 {
    const z: u3 = @truncate(op_code);
    const register = reg_8[z];
    self.print("AND A,{s}\n", .{register});
    and_int(self.getRegDataValue(z));
    if (z == 6) {
        return 8;
    }
    return 4;
}

fn and_int(change: u8) void {
    a_reg.* = a_reg.* & change;
    flags.n = 0;
    flags.h = 1;
    flags.c = 0;
    if (a_reg.* & 0xFF == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
}

fn cpl(self: *Self, _: u8) u8 {
    self.print("CPL\n", .{});
    a_reg.* = ~a_reg.*;
    flags.n = 1;
    flags.h = 1;
    return 4;
}

fn or_r(self: *Self, op_code: u8) u8 {
    const z: u3 = @truncate(op_code);
    const register = reg_8[z];
    self.print("OR A,{s}\n", .{register});
    or_int(self.getRegDataValue(z));
    if (z == 6) {
        return 8;
    }
    return 4;
}

fn or_int(change: u8) void {
    a_reg.* = a_reg.* | change;
    if (a_reg.* == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
    flags.n = 0;
    flags.h = 0;
    flags.c = 0;
}

fn xor_r(self: *Self, op_code: u8) u8 {
    const z: u3 = @truncate(op_code);
    const register = reg_8[z];
    self.print("XOR A,{s}\n", .{register});
    xor_int(self.getRegDataValue(z));
    if (z == 6) {
        return 8;
    }
    return 4;
}

fn xor_int(change: u8) void {
    a_reg.* = change ^ a_reg.*;
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

fn add_sp_e8(self: *Self, _: u8) u8 {
    const displacement: i8 = @bitCast(self.read());
    self.print("ADD SP,{X:02}\n", .{displacement});
    sp = add_sp_e8_int(displacement);
    return 16;
}

fn add_sp_e8_int(displacement: i8) u16 {
    const signed_sp = @as(i16, @bitCast(sp));
    const result = @addWithOverflow(signed_sp, displacement);
    const half_result = @addWithOverflow(@as(u8, @truncate(sp)), @as(u8, @truncate(@as(u8, @bitCast(displacement)))));
    const quarter_result = @addWithOverflow(@as(u4, @truncate(sp)), @as(u4, @truncate(@as(u8, @bitCast(displacement)))));
    flags.z = 0;
    flags.n = 0;
    flags.h = quarter_result[1];
    flags.c = half_result[1];
    return @truncate(@as(u16, @bitCast(result[0])));
}

fn ld_sp_hl(self: *Self, _: u8) u8 {
    self.print("LD SP,HL\n", .{});
    sp = hl.full;
    return 8;
}

fn ld_hl_sp_e8(self: *Self, _: u8) u8 {
    const displacement: i8 = @bitCast(self.read());
    self.print("LD HL,SP+{X:02}\n", .{displacement});
    hl.full = add_sp_e8_int(displacement);
    return 12;
}

fn ld_a16_sp(self: *Self, _: u8) u8 {
    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("LD ${X:04},SP\n", .{address});
    self.getMemoryPointer(address).* = @truncate(sp);
    self.getMemoryPointer(address + 1).* = @truncate(sp >> 8);
    return 20;
}

fn push_rp2(self: *Self, op_code: u8) u8 {
    const p: u2 = @truncate(op_code >> 4);
    const register = reg_p2[p];
    self.print("PUSH {s}\n", .{register});
    if (p == 3) {
        push_int(self, af.af & 0xFFF0);
    } else {
        push_int(self, reg_p2_t[p].*);
    }
    return 16;
}

fn pop_rp2(self: *Self, op_code: u8) u8 {
    const p: u2 = @truncate(op_code >> 4);
    const register = reg_p2[p];
    self.print("POP {s}\n", .{register});
    if (p == 3) {
        reg_p2_t[p].* = pop_int(self) & 0xFFF0;
    } else {
        reg_p2_t[p].* = pop_int(self);
    }
    return 12;
}

// Bit shift

fn rlca(self: *Self, _: u8) u8 {
    self.print("RLCA\n", .{});
    rlc_int(a_reg);
    flags.z = 0;
    return 4;
}

fn rlc_int(pointer: *u8) void {
    const result = @shlWithOverflow(pointer.*, 1);
    pointer.* = result[0] | result[1];
    flags.c = result[1];
    flags.n = 0;
    flags.h = 0;
}

fn rrca(self: *Self, _: u8) u8 {
    self.print("RRCA\n", .{});
    rrc_int(a_reg);
    flags.z = 0;
    return 4;
}

fn rrc_int(pointer: *u8) void {
    const low_bit: u1 = @truncate(pointer.*);
    const result = pointer.* >> 1;
    pointer.* = result | (@as(u8, low_bit) << 7);
    flags.c = low_bit;
    flags.n = 0;
    flags.h = 0;
}

fn rla(self: *Self, _: u8) u8 {
    self.print("RLA\n", .{});
    rl_int(a_reg);
    flags.z = 0;
    return 4;
}

fn rl_int(pointer: *u8) void {
    const result = @shlWithOverflow(pointer.*, 1);
    pointer.* = result[0] | flags.c;
    flags.c = result[1];
    flags.n = 0;
    flags.h = 0;
}

fn rra(self: *Self, _: u8) u8 {
    self.print("RRA\n", .{});
    rr_int(a_reg);
    flags.z = 0;
    return 4;
}

fn rr_int(pointer: *u8) void {
    const old_c: u8 = flags.c;
    flags.c = @truncate(pointer.*);
    pointer.* = (pointer.* >> 1) | (old_c << 7);
    flags.n = 0;
    flags.h = 0;
}

fn daa(self: *Self, _: u8) u8 {
    self.print("DAA\n", .{});
    var adjustment: u8 = 0;
    if (flags.n == 1) {
        if (flags.h == 1) {
            adjustment += 0x6;
        }
        if (flags.c == 1) {
            adjustment += 0x60;
        }
        const result = @subWithOverflow(a_reg.*, adjustment);
        a_reg.* = result[0];
    } else {
        if (flags.h == 1 or (a_reg.* & 0xF) > 0x9) {
            adjustment += 0x6;
        }
        if (flags.c == 1 or a_reg.* > 0x99) {
            adjustment += 0x60;
            flags.c = 1;
        }
        const result = @addWithOverflow(a_reg.*, adjustment);
        a_reg.* = result[0];
    }
    flags.h = 0;
    if (a_reg.* == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
    return 4;
}

// Carry flag

fn scf(self: *Self, _: u8) u8 {
    self.print("SCF\n", .{});
    flags.n = 0;
    flags.h = 0;
    flags.c = 1;
    return 4;
}

fn ccf(self: *Self, _: u8) u8 {
    self.print("CCF\n", .{});
    flags.n = 0;
    flags.h = 0;
    flags.c = ~flags.c;
    return 4;
}

// Interrupt

fn halt(self: *Self, _: u8) u8 {
    // Low Power Mode
    self.print("HALT\n", .{});
    self.halted = true;
    return 0;
}

fn di(self: *Self, _: u8) u8 {
    self.print("DI\n", .{});
    // Disable Interrupts by clearing the IME flag.
    self.ime = 0;
    return 4;
}

fn ei(self: *Self, _: u8) u8 {
    self.print("EI\n", .{});
    // Enable Interrupts by setting the IME flag.
    self.ime = 1;
    // TODO: The flag is only set after the instruction following EI.
    return 4;
}

// CB

fn cb_prefix(self: *Self, _: u8) u8 {
    const op_code = self.read();
    const x: u2 = @truncate(op_code >> 6);
    const y: u3 = @truncate(op_code >> 3);
    const z: u3 = @truncate(op_code);
    const register = reg_8[z];
    const pointer = self.getRegDataPointer(z);
    if (x == 0) {
        const operation = reg_rot[y];
        self.print("{s} {s}\n", .{ operation, register });
        if (y == 0) {
            // RLC
            rlc_int(pointer);
        } else if (y == 1) {
            // RRC
            rrc_int(pointer);
        } else if (y == 2) {
            // RL
            rl_int(pointer);
        } else if (y == 3) {
            // RR
            rr_int(pointer);
        } else if (y == 4) {
            // SLA
            const result = @shlWithOverflow(pointer.*, 0x1);
            flags.c = result[1];
            pointer.* = result[0];
            flags.n = 0;
            flags.h = 0;
        } else if (y == 5) {
            // SRA
            flags.c = @truncate(pointer.*);
            const bit_7 = pointer.* & 0b10000000;
            pointer.* = bit_7 | (pointer.* >> 1);
            flags.n = 0;
            flags.h = 0;
        } else if (y == 6) {
            // SWAP
            const lower: u4 = @truncate(pointer.*);
            pointer.* = (pointer.* >> 4) | (@as(u8, lower) << 4);
            flags.n = 0;
            flags.h = 0;
            flags.c = 0;
        } else if (y == 7) {
            // SRL
            flags.c = @truncate(pointer.*);
            pointer.* = pointer.* >> 1;
            flags.n = 0;
            flags.h = 0;
        } else {
            std.debug.panic("Unknown x:{d}, y:{d}, z:{d}", .{ x, y, z });
        }
        if (pointer.* == 0) {
            flags.z = 1;
        } else {
            flags.z = 0;
        }
        if (z == 6) {
            return 16;
        }
        return 8;
    } else if (x == 1) {
        self.print("BIT {d},{s}\n", .{ y, register });
        flags.z = ~@as(u1, @truncate(pointer.* >> y));
        flags.n = 0;
        flags.h = 1;
        if (z == 6) {
            return 12;
        }
        return 8;
    } else if (x == 2) {
        self.print("RES {d},{s}\n", .{ y, register });
        utils.resetBit(pointer, y);
        if (z == 6) {
            return 16;
        }
        return 8;
    } else if (x == 3) {
        self.print("SET {d},{s}\n", .{ y, register });
        utils.setBit(pointer, y);
        const mask = @as(u8, 1) << y;
        pointer.* = pointer.* | mask;
        if (z == 6) {
            return 16;
        }
        return 8;
    } else {
        std.debug.panic("Unknown x:{d}, y:{d}, z:{d}", .{ x, y, z });
    }
}

fn stop(self: *Self, _: u8) u8 {
    _ = self.read();
    self.print("STOP\n", .{});
    return 0;
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
const op_lookup = [256] *const fn (*Self, u8) u8 { 
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
