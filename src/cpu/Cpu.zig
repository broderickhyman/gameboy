const std = @import("std");
const Endian = std.builtin.Endian;
const Self = @This();
const utils = @import("../utils.zig");
const Memory = @import("../memory/Memory.zig");
const Timer = @import("Timer.zig");
const RunContext = @import("../RunContext.zig");

run_context: *RunContext,
memory: *Memory,
timer: *Timer,
pc: u16,
counter: u32,
debug: bool,
verbose: bool,
should_print: bool,
output_memory: bool,
is_doctor_test: bool,
ime: u1,
paused: bool,
dot_counter: u8,

pub fn create(
    run_context: *RunContext,
    memory: *Memory,
    timer: *Timer,
    start_pc: u16,
) !*Self {
    const cpu = try run_context.allocator.create(Self);

    cpu.* = .{
        .run_context = run_context,
        .memory = memory,
        .timer = timer,
        .pc = start_pc,
        .counter = 1,
        .should_print = false,
        .output_memory = false,
        .debug = false,
        .verbose = false,
        .is_doctor_test = false,
        .ime = 0,
        .paused = false,
        .dot_counter = 0,
    };
    return cpu;
}

pub fn cycle(self: *Self) u8 {
    self.dot_counter = 0;
    if (self.timer.halted) {
        self.handleDots(4);
    } else {
        const op_code = self.read();
        self.counter = @addWithOverflow(self.counter, 1)[0];
        op_lookup[op_code](self, op_code);
    }

    self.handleInterrupts();
    return self.dot_counter;
}

fn handleDots(self: *Self, dots: u8) void {
    self.dot_counter += dots;
    self.timer.handleDots(self, dots);
    self.memory.handleDots(dots);
}

pub fn handleInterrupts(self: *Self) void {
    const enabled = self.memory.ie;
    const flag = self.memory.io.getMemoryPointer(0xFF0F);
    if (enabled == 0 or flag.* == 0) {
        return;
    }
    if (self.handleInterrupt(enabled, flag, 0, 0x40)) {
        // VBlank
        return;
    }
    if (self.handleInterrupt(enabled, flag, 1, 0x48)) {
        // LCD
        return;
    }
    if (self.handleInterrupt(enabled, flag, 2, 0x50)) {
        // Timer
        return;
    }
    if (self.handleInterrupt(enabled, flag, 3, 0x58)) {
        // Serial
        return;
    }
    if (self.handleInterrupt(enabled, flag, 4, 0x60)) {
        // Joypad
        return;
    }
}

fn handleInterrupt(self: *Self, enabled: u8, flag: *u8, shift: u3, address: u16) bool {
    const is_enabled = (enabled >> shift) & 0b1;
    const is_flagged = (flag.* >> shift) & 0b1;
    if (is_enabled == 1 and is_flagged == 1) {
        if (self.timer.halted) {
            self.handleDots(4);
            self.timer.halted = false;
        }
        if (self.ime == 0) {
            return false;
        }
        self.print("Interrupt: {d}\n", .{shift});
        self.ime = 0;
        utils.resetBit(flag, shift);
        self.handleDots(8);
        call_int(self, address);
        return true;
    }
    return false;
}

pub fn requestInterrupt(self: *Self, bit_num: u3) void {
    if (self.paused) {
        return;
    }
    self.memory.requestInterrupt(bit_num);
}

fn read(self: *Self) u8 {
    const memory_value = self.memory.read(self.pc);
    self.pc += 1;
    self.handleDots(4);
    return memory_value;
}

pub fn saveRam(self: *Self) !void {
    if (self.memory.external_ram_banks.len == 0) {
        return;
    }
    const file = try utils.openFileWrite(self.run_context, "ram.bin");
    defer file.close();
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    try self.memory.saveRam(&writer);
    try writer.end();
}

pub fn saveState(self: *Self) !void {
    // self.paused = true;
    const file = try utils.openFileWrite(self.run_context, "state.bin");
    defer file.close();
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    try utils.writeInt(&writer, u16, af.af, Endian.big);
    try utils.writeInt(&writer, u16, bc.full, Endian.big);
    try utils.writeInt(&writer, u16, de.full, Endian.big);
    try utils.writeInt(&writer, u16, hl.full, Endian.big);
    try utils.writeInt(&writer, u16, sp, Endian.big);
    try utils.writeInt(&writer, u16, self.pc, Endian.big);
    try utils.writeInt(&writer, u32, self.counter, Endian.big);
    try utils.writeInt(&writer, u8, self.ime, Endian.big);
    try utils.writeInt(&writer, u8, @intFromBool(self.paused), Endian.big);
    try self.memory.saveState(&writer);
    try self.timer.saveState(&writer);
    try writer.end();
}

pub fn loadState(self: *Self) !void {
    // self.paused = true;
    const file = try utils.openFileRead(self.run_context, "state.bin");
    defer file.close();
    var buffer: [4096]u8 = undefined;
    var reader = file.reader(&buffer);
    af.af = try utils.readInt(&reader, u16, Endian.big);
    bc.full = try utils.readInt(&reader, u16, Endian.big);
    de.full = try utils.readInt(&reader, u16, Endian.big);
    hl.full = try utils.readInt(&reader, u16, Endian.big);
    sp = try utils.readInt(&reader, u16, Endian.big);
    self.pc = try utils.readInt(&reader, u16, Endian.big);
    self.counter = try utils.readInt(&reader, u32, Endian.big);
    self.ime = @truncate(try utils.readInt(&reader, u8, Endian.big));
    self.paused = (try utils.readInt(&reader, u8, Endian.big)) == 1;
    try self.memory.loadState(&reader);
    try self.timer.loadState(&reader);
}

fn printIndex(self: *Self) void {
    self.print("Current Index: {0d} {0x}\n", .{self.pc});
}

fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
    if (self.should_print) {
        // std.debug.print(fmt, args);
        if (self.run_context.log_out) |*log_out| {
            var buffer: [256]u8 = undefined;
            const printed = std.fmt.bufPrint(&buffer, fmt, args) catch return;
            log_out.interface.writeAll(printed) catch std.debug.panic("Could not print.", .{});
            log_out.interface.flush() catch std.debug.panic("Could not flush.", .{});
        }
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
    if (self.is_doctor_test) {
        var buffer: [256]u8 = undefined;
        const printed = try std.fmt.bufPrint(&buffer, "A:{X:02} F:{X:02} B:{X:02} C:{X:02} D:{X:02} E:{X:02} H:{X:02} L:{X:02} SP:{X:04} PC:{X:04} PCMEM:{X:02},{X:02},{X:02},{X:02}\n", .{
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
            self.memory.read(self.pc),
            self.memory.read(self.pc + 1),
            self.memory.read(self.pc + 2),
            self.memory.read(self.pc + 3),
        });
        try self.run_context.std_out.interface.writeAll(printed);
        try self.run_context.std_out.interface.flush();
    }
    if (!(self.should_print and self.output_memory)) {
        return;
    }
    if (self.run_context.log_out) |*log_out| {
        var buffer2: [512]u8 = undefined;
        const printed2 = try std.fmt.bufPrint(&buffer2, "{X:08} {d:08}-{X:08} {d:08} {d:1}-{d:03} A:{X:02} F:{X:02} B:{X:02} C:{X:02} D:{X:02} E:{X:02} H:{X:02} L:{X:02} SP:{X:04} PC:{X:04} PCMEM:{X:02},{X:02},{X:02},{X:02}\n", .{
            self.counter,
            self.timer.internal_counter,
            self.timer.read(0xFF04),
            self.timer.timer,
            self.memory.dma_delay,
            self.memory.dma_timing,
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
            self.memory.read(self.pc),
            self.memory.read(self.pc + 1),
            self.memory.read(self.pc + 2),
            self.memory.read(self.pc + 3),
        });
        try log_out.interface.writeAll(printed2);
        try log_out.interface.flush();
    }
}

fn readRegDataValue(self: *Self, index: u8) u8 {
    if (index == 6) {
        if (hl.full == 0xFF05) {
            self.print("\nRead Timer: {d}\n\n", .{self.memory.read(hl.full)});
        }
        self.print("Read HL: ${X:04}\n", .{hl.full});
        const value = self.memory.read(hl.full);
        self.handleDots(4);
        return value;
    } else {
        return reg_8_t[index].*;
    }
}

fn writeRegDataValue(self: *Self, index: u8, value: u8) void {
    if (index == 6) {
        if (hl.full == 0xFF05) {
            self.print("\nWrite Timer: {d}\n\n", .{value});
        }
        self.print("Write HL: ${X:04}\n", .{hl.full});
        self.handleDots(4);
        self.memory.write(hl.full, value);
    } else {
        reg_8_t[index].* = value;
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

fn nop(_: *Self, _: u8) void {
    // return 4;
}

fn nop_vd(_: *Self, _: u8) void {
    // return 4;
    // std.debug.panic("Unknown behavior", .{});
}

// Load

fn ld_rp_n16(self: *Self, op_code: u8) void {
    const p: u2 = @truncate(op_code >> 4);
    const register = reg_p[p];
    const right = self.read();
    const value: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("LD {s},${X:04}\n", .{ register, value });
    reg_p_t[p].* = value;
    // return 12;
}

fn ld_r_n8(self: *Self, op_code: u8) void {
    const y: u3 = @truncate(op_code >> 3);
    const register = reg_8[y];
    const value = self.read();
    self.print("LD {s},${X:04}\n", .{ register, value });
    self.writeRegDataValue(y, value);
    // if (y == 6) {
    //     return 12;
    // }
    // return 8;
}

fn ld_r_r(self: *Self, op_code: u8) void {
    const y: u3 = @truncate(op_code >> 3);
    const z: u3 = @truncate(op_code);
    const register1 = reg_8[y];
    const register2 = reg_8[z];
    self.print("LD {s},{s}\n", .{ register1, register2 });
    if (y == z) {
        // Software breakpoint
        // @breakpoint();
    }
    self.writeRegDataValue(y, self.readRegDataValue(z));
    // if (y == 6 or z == 6) {
    //     return 8;
    // }
    // return 4;
}

fn ld_bc_a(self: *Self, _: u8) void {
    self.print("LD (BC),A\n", .{});
    self.handleDots(4);
    self.memory.write(bc.full, a_reg.*);
    // return 8;
}

fn ld_de_a(self: *Self, _: u8) void {
    self.print("LD (DE),A\n", .{});
    self.handleDots(4);
    self.memory.write(de.full, a_reg.*);
    // return 8;
}

fn ld_a_bc(self: *Self, _: u8) void {
    self.print("LD A,(BC)\n", .{});
    self.handleDots(4);
    a_reg.* = self.memory.read(bc.full);
    // return 8;
}

fn ld_a_de(self: *Self, _: u8) void {
    self.print("LD A,(DE)\n", .{});
    self.handleDots(4);
    a_reg.* = self.memory.read(de.full);
    // return 8;
}

fn ld_hli_a(self: *Self, _: u8) void {
    self.print("LD (HL+),A ${X:04}\n", .{hl.full});
    self.handleDots(4);
    self.memory.write(hl.full, a_reg.*);
    // hl.full = @addWithOverflow(hl.full, 1)[0];
    hl.full += 1;
    // return 8;
}

fn ld_hld_a(self: *Self, _: u8) void {
    self.print("LD (HL-),A ${X:04}\n", .{hl.full});
    self.handleDots(4);
    self.memory.write(hl.full, a_reg.*);
    hl.full -= 1;
    // return 8;
}

fn ld_a_hli(self: *Self, _: u8) void {
    self.print("LD A,(HL+) ${X:04}\n", .{hl.full});
    self.handleDots(4);
    a_reg.* = self.memory.read(hl.full);
    hl.full += 1;
    // return 8;
}

fn ld_a_hld(self: *Self, _: u8) void {
    self.print("LD A,(HL-) ${X:04}\n", .{hl.full});
    self.handleDots(4);
    a_reg.* = self.memory.read(hl.full);
    hl.full -= 1;
    // return 8;
}

fn ld_a16_a(self: *Self, _: u8) void {
    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("LD (${X:04}),A\n", .{address});
    self.handleDots(4);
    self.memory.write(address, a_reg.*);
    // return 16;
}

fn ld_a_a16(self: *Self, _: u8) void {
    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("LD A,(${X:04})\n", .{address});
    self.handleDots(4);
    a_reg.* = self.memory.read(address);
    // return 16;
}

fn ldh_c_a(self: *Self, _: u8) void {
    const address: u16 = @as(u16, 0xFF00) + bc.sp.lo;
    self.print("LDH (${X:04}),A\n", .{address});
    self.handleDots(4);
    self.memory.write(address, a_reg.*);
    // return 8;
}

fn ldh_a_c(self: *Self, _: u8) void {
    const address: u16 = @as(u16, 0xFF00) + bc.sp.lo;
    self.print("LDH A,(${X:04})\n", .{address});
    self.handleDots(4);
    a_reg.* = self.memory.read(address);
    // return 8;
}

fn ldh_a8_a(self: *Self, _: u8) void {
    const displacement = self.read();
    const address: u16 = @as(u16, 0xFF00) + displacement;
    self.print("LDH (${X:04}),A\n", .{address});
    if (address >= 0xFF00 and address <= 0xFFFF) {
        self.handleDots(4);
        self.memory.write(address, a_reg.*);
    } else {
        std.debug.panic("Bad Address", .{});
    }
    // return 12;
}

fn ldh_a_a8(self: *Self, _: u8) void {
    const displacement = self.read();
    const address: u16 = @as(u16, 0xFF00) + displacement;
    self.print("LDH A,(${X:04})\n", .{address});
    if (address >= 0xFF00 and address <= 0xFFFF) {
        self.handleDots(4);
        a_reg.* = self.memory.read(address);
    } else {
        std.debug.panic("Bad Address", .{});
    }
    // return 12;
}

// Jumps

fn call_int(self: *Self, address: u16) void {
    push_int(self, self.pc);
    self.handleDots(4);
    self.pc = address;
}

fn call_a16(self: *Self, _: u8) void {
    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("CALL ${X:04}\n", .{address});
    call_int(self, address);
    // return 24;
}

fn call_cc_a16(self: *Self, op_code: u8) void {
    const y: u3 = @truncate(op_code >> 3);
    const condition = reg_cc[y];
    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("CALL {s},${X:04}\n", .{ condition, address });
    if (self.checkCondition(y)) {
        call_int(self, address);
        // return 24;
    }
    // return 12;
}

fn jr_cc_e8(self: *Self, op_code: u8) void {
    const y_offset: u3 = @truncate((op_code >> 3) - 4);
    const condition = reg_cc[y_offset];
    const displacement = self.read();
    const address: u16 = @truncate(@as(u17, @bitCast(@as(i17, self.pc) + @as(i8, @bitCast(displacement)))));
    self.print("JR {s},Addr_{X:04}\n", .{ condition, address });
    if (self.checkCondition(y_offset)) {
        self.handleDots(4);
        self.pc = address;
        // return 12;
    }
    // return 8;
}

fn jr_e8(self: *Self, _: u8) void {
    const displacement: i8 = @bitCast(self.read());
    const address: u16 = @truncate(@as(u17, @bitCast(@as(i17, self.pc) + displacement)));
    self.print("JR Addr_{X:04}\n", .{address});
    self.handleDots(4);
    self.pc = address;
    // return 12;
}

fn ret(self: *Self, _: u8) void {
    self.print("RET\n", .{});
    self.handleDots(4);
    self.pc = pop_int(self);
    // return 16;
}

fn ret_cc(self: *Self, op_code: u8) void {
    const y: u3 = @truncate(op_code >> 3);
    const condition = reg_cc[y];
    self.print("RET {s}\n", .{condition});
    self.handleDots(4);
    if (self.checkCondition(y)) {
        ret(self, 0);
        // return 20;
    }
    // return 8;
}

fn reti(self: *Self, op_code: u8) void {
    self.print("RETI\n", .{});
    ret(self, op_code);
    ei_int(self);
    // return 16;
}

fn jp_a16(self: *Self, _: u8) void {
    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("JP Addr_{X:04}\n", .{address});
    self.handleDots(4);
    self.pc = address;
    // return 16;
}

fn jp_cc_a16(self: *Self, op_code: u8) void {
    const y: u3 = @truncate(op_code >> 3);
    const condition = reg_cc[y];

    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("JP {s},Addr_{X:04}\n", .{ condition, address });
    if (self.checkCondition(y)) {
        self.handleDots(4);
        self.pc = address;
        // return 16;
    }
    // return 12;
}

fn jp_hl(self: *Self, _: u8) void {
    self.print("JP HL ${X:04}\n", .{hl.full});
    self.pc = hl.full;
    // return 4;
}

fn rst(self: *Self, op_code: u8) void {
    const y: u3 = @truncate(op_code >> 3);
    const vec: u16 = @as(u16, y) * 8;
    self.print("RST Addr_{X:04}\n", .{vec});
    call_int(self, vec);
    // return 16;
}

fn push_int(self: *Self, value: u16) void {
    sp -= 1;
    self.handleDots(4);
    self.memory.write(sp, @truncate(value >> 8));
    sp -= 1;
    self.handleDots(4);
    self.memory.write(sp, @truncate(value));
}

fn pop_int(self: *Self) u16 {
    var new_value: u16 = @as(u16, self.memory.read(sp));
    self.handleDots(4);
    sp += 1;
    new_value = new_value | (@as(u16, self.memory.read(sp)) << 8);
    self.handleDots(4);
    sp += 1;
    return new_value;
}

// Arithmetic

fn adc_r(self: *Self, op_code: u8) void {
    const z: u3 = @truncate(op_code);
    const register = reg_8[z];
    self.print("ADC {s}\n", .{register});
    adc_int(self.readRegDataValue(z));
    // if (z == 6) {
    //     return 8;
    // }
    // return 4;
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

fn add_r(self: *Self, op_code: u8) void {
    const z: u3 = @truncate(op_code);
    const register = reg_8[z];
    self.print("ADD {s}\n", .{register});
    add_int(self.readRegDataValue(z));
    // if (z == 6) {
    //     return 8;
    // }
    // return 4;
}

fn add_hl_rp(self: *Self, op_code: u8) void {
    const p: u2 = @truncate(op_code >> 4);
    const register = reg_p[p];
    self.print("ADD HL,{s} ${X:04}\n", .{ register, hl.full });
    const current_value = reg_p_t[p].*;
    self.handleDots(4);
    const result = @addWithOverflow(hl.full, current_value);
    const half_result = @addWithOverflow(@as(u12, @truncate(hl.full)), @as(u12, @truncate(current_value)));
    hl.full = result[0];
    flags.n = 0;
    flags.h = half_result[1];
    flags.c = result[1];
    // return 8;
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

fn cp_r(self: *Self, op_code: u8) void {
    const z: u3 = @truncate(op_code);
    const register = reg_8[z];
    self.print("CP {s}\n", .{register});
    cp_int(self.readRegDataValue(z));
    // if (z == 6) {
    //     return 8;
    // }
    // return 4;
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

fn dec_r(self: *Self, op_code: u8) void {
    const y: u3 = @truncate(op_code >> 3);
    const register = reg_8[y];
    self.print("DEC {s}\n", .{register});
    const original = self.readRegDataValue(y);
    const half_result = @subWithOverflow(@as(u4, @truncate(original)), 1);
    flags.h = half_result[1];
    flags.n = 1;
    const result = @subWithOverflow(original, 1);
    self.writeRegDataValue(y, result[0]);
    if (result[0] == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
    // if (y == 6) {
    //     return 12;
    // }
    // return 4;
}

fn dec_rp(self: *Self, op_code: u8) void {
    const p: u2 = @truncate(op_code >> 4);
    const register = reg_p[p];
    self.print("DEC {s}\n", .{register});
    const pointer = reg_p_t[p];
    self.handleDots(4);
    const result = @subWithOverflow(pointer.*, 1);
    pointer.* = result[0];
    // return 8;
}

fn inc_r(self: *Self, op_code: u8) void {
    const y: u3 = @truncate(op_code >> 3);
    const register = reg_8[y];
    self.print("INC {s}\n", .{register});
    const original = self.readRegDataValue(y);

    const half_result = @addWithOverflow(@as(u4, @truncate(original)), 1);
    flags.h = half_result[1];
    flags.n = 0;
    const result = @addWithOverflow(original, 1);
    self.writeRegDataValue(y, result[0]);
    if (result[0] == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
    // if (y == 6) {
    //     return 12;
    // }
    // return 4;
}

fn inc_rp(self: *Self, op_code: u8) void {
    const p: u2 = @truncate(op_code >> 4);
    const register = reg_p[p];
    self.print("INC {s}\n", .{register});
    const pointer = reg_p_t[p];
    self.handleDots(4);
    const result = @addWithOverflow(pointer.*, 1);
    pointer.* = result[0];
    // return 8;
}

fn sbc_r(self: *Self, op_code: u8) void {
    const z: u3 = @truncate(op_code);
    const register = reg_8[z];
    self.print("SBC {s}\n", .{register});
    sbc_int(self.readRegDataValue(z));
    // if (z == 6) {
    //     return 8;
    // }
    // return 4;
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

fn sub_r(self: *Self, op_code: u8) void {
    const z: u3 = @truncate(op_code);
    const register = reg_8[z];
    self.print("SUB {s}\n", .{register});
    sub_int(self.readRegDataValue(z));
    // if (z == 6) {
    //     return 8;
    // }
    // return 4;
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

fn alu_n8(self: *Self, op_code: u8) void {
    const y: u3 = @truncate(op_code >> 3);
    const register = reg_alu[y];
    const change = self.read();
    self.print("{s} A,${X:02}\n", .{ register, change });
    if (y == 0) {
        // ADD
        add_int(change);
        // return 8;
    } else if (y == 1) {
        // ADC
        adc_int(change);
        // return 8;
    } else if (y == 2) {
        // SUB
        sub_int(change);
        // return 8;
    } else if (y == 3) {
        // SBC
        sbc_int(change);
        // return 8;
    } else if (y == 4) {
        // AND
        and_int(change);
        // return 8;
    } else if (y == 5) {
        // XOR
        xor_int(change);
        // return 8;
    } else if (y == 6) {
        // OR
        or_int(change);
        // return 8;
    } else if (y == 7) {
        // CP
        cp_int(change);
        // return 8;
    }
}

// Bitwise logic

fn and_r(self: *Self, op_code: u8) void {
    const z: u3 = @truncate(op_code);
    const register = reg_8[z];
    self.print("AND A,{s}\n", .{register});
    and_int(self.readRegDataValue(z));
    // if (z == 6) {
    //     return 8;
    // }
    // return 4;
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

fn cpl(self: *Self, _: u8) void {
    self.print("CPL\n", .{});
    a_reg.* = ~a_reg.*;
    flags.n = 1;
    flags.h = 1;
    // return 4;
}

fn or_r(self: *Self, op_code: u8) void {
    const z: u3 = @truncate(op_code);
    const register = reg_8[z];
    self.print("OR A,{s}\n", .{register});
    or_int(self.readRegDataValue(z));
    // if (z == 6) {
    //     return 8;
    // }
    // return 4;
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

fn xor_r(self: *Self, op_code: u8) void {
    const z: u3 = @truncate(op_code);
    const register = reg_8[z];
    self.print("XOR A,{s}\n", .{register});
    xor_int(self.readRegDataValue(z));
    // if (z == 6) {
    //     return 8;
    // }
    // return 4;
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

fn add_sp_e8(self: *Self, _: u8) void {
    const displacement: i8 = @bitCast(self.read());
    self.print("ADD SP,{X:02}\n", .{displacement});
    self.handleDots(4);
    sp = add_sp_e8_int(self, displacement);
    // return 16;
}

fn add_sp_e8_int(self: *Self, displacement: i8) u16 {
    const signed_sp = @as(i16, @bitCast(sp));
    const result = @addWithOverflow(signed_sp, displacement);
    const half_result = @addWithOverflow(@as(u8, @truncate(sp)), @as(u8, @truncate(@as(u8, @bitCast(displacement)))));
    const quarter_result = @addWithOverflow(@as(u4, @truncate(sp)), @as(u4, @truncate(@as(u8, @bitCast(displacement)))));
    flags.z = 0;
    flags.n = 0;
    flags.h = quarter_result[1];
    flags.c = half_result[1];
    self.handleDots(4);
    return @truncate(@as(u16, @bitCast(result[0])));
}

fn ld_sp_hl(self: *Self, _: u8) void {
    self.print("LD SP,HL ${X:04}\n", .{hl.full});
    self.handleDots(4);
    sp = hl.full;
    // return 8;
}

fn ld_hl_sp_e8(self: *Self, _: u8) void {
    const displacement: i8 = @bitCast(self.read());
    self.print("LD HL,SP+{X:02} ${X:04}\n", .{ displacement, hl.full });
    hl.full = add_sp_e8_int(self, displacement);
    // return 12;
}

fn ld_a16_sp(self: *Self, _: u8) void {
    const right = self.read();
    const address: u16 = (@as(u16, self.read()) << 8) | right;
    self.print("LD ${X:04},SP\n", .{address});
    self.handleDots(4);
    self.memory.write(address, @truncate(sp));
    self.handleDots(4);
    self.memory.write(address + 1, @truncate(sp >> 8));
    // return 20;
}

fn push_rp2(self: *Self, op_code: u8) void {
    const p: u2 = @truncate(op_code >> 4);
    const register = reg_p2[p];
    self.print("PUSH {s}\n", .{register});
    self.handleDots(4);
    if (p == 3) {
        push_int(self, af.af & 0xFFF0);
    } else {
        push_int(self, reg_p2_t[p].*);
    }
    // return 16;
}

fn pop_rp2(self: *Self, op_code: u8) void {
    const p: u2 = @truncate(op_code >> 4);
    const register = reg_p2[p];
    self.print("POP {s}\n", .{register});
    if (p == 3) {
        reg_p2_t[p].* = pop_int(self) & 0xFFF0;
    } else {
        reg_p2_t[p].* = pop_int(self);
    }
    // return 12;
}

// Bit shift

fn rlca(self: *Self, _: u8) void {
    self.print("RLCA\n", .{});
    a_reg.* = rlc_int(a_reg.*);
    flags.z = 0;
    // return 4;
}

fn rlc_int(value: u8) u8 {
    const result = @shlWithOverflow(value, 1);
    flags.c = result[1];
    flags.n = 0;
    flags.h = 0;
    return result[0] | result[1];
}

fn rrca(self: *Self, _: u8) void {
    self.print("RRCA\n", .{});
    a_reg.* = rrc_int(a_reg.*);
    flags.z = 0;
    // return 4;
}

fn rrc_int(value: u8) u8 {
    const low_bit: u1 = @truncate(value);
    const result = value >> 1;
    flags.c = low_bit;
    flags.n = 0;
    flags.h = 0;
    return result | (@as(u8, low_bit) << 7);
}

fn rla(self: *Self, _: u8) void {
    self.print("RLA\n", .{});
    a_reg.* = rl_int(a_reg.*);
    flags.z = 0;
    // return 4;
}

fn rl_int(value: u8) u8 {
    const result = @shlWithOverflow(value, 1);
    const old_c = flags.c;
    flags.c = result[1];
    flags.n = 0;
    flags.h = 0;
    return result[0] | old_c;
}

fn rra(self: *Self, _: u8) void {
    self.print("RRA\n", .{});
    a_reg.* = rr_int(a_reg.*);
    flags.z = 0;
    // return 4;
}

fn rr_int(value: u8) u8 {
    const old_c: u8 = flags.c;
    flags.c = @truncate(value);
    flags.n = 0;
    flags.h = 0;
    return (value >> 1) | (old_c << 7);
}

fn daa(self: *Self, _: u8) void {
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
    // return 4;
}

// Carry flag

fn scf(self: *Self, _: u8) void {
    self.print("SCF\n", .{});
    flags.n = 0;
    flags.h = 0;
    flags.c = 1;
    // return 4;
}

fn ccf(self: *Self, _: u8) void {
    self.print("CCF\n", .{});
    flags.n = 0;
    flags.h = 0;
    flags.c = ~flags.c;
    // return 4;
}

// Interrupt

fn halt(self: *Self, _: u8) void {
    // Low Power Mode
    self.print("HALT\n", .{});
    self.timer.halted = true;
    // return 0;
}

fn di(self: *Self, _: u8) void {
    self.print("DI\n", .{});
    // Disable Interrupts by clearing the IME flag.
    self.ime = 0;
    // return 4;
}

fn ei(self: *Self, _: u8) void {
    self.print("EI\n", .{});
    self.ei_int();
    // return 4;
}

fn ei_int(self: *Self) void {
    // Enable Interrupts by setting the IME flag.
    // TODO: The flag is only set after the instruction following EI.
    self.ime = 1;
}

// CB

fn cb_prefix(self: *Self, _: u8) void {
    const op_code = self.read();
    const x: u2 = @truncate(op_code >> 6);
    const y: u3 = @truncate(op_code >> 3);
    const z: u3 = @truncate(op_code);
    const register = reg_8[z];
    var value = self.readRegDataValue(z);
    if (x == 0) {
        const operation = reg_rot[y];
        self.print("{s} {s}\n", .{ operation, register });
        if (y == 0) {
            // RLC
            value = rlc_int(value);
        } else if (y == 1) {
            // RRC
            value = rrc_int(value);
        } else if (y == 2) {
            // RL
            value = rl_int(value);
        } else if (y == 3) {
            // RR
            value = rr_int(value);
        } else if (y == 4) {
            // SLA
            const result = @shlWithOverflow(value, 0x1);
            flags.c = result[1];
            value = result[0];
            flags.n = 0;
            flags.h = 0;
        } else if (y == 5) {
            // SRA
            flags.c = @truncate(value);
            const bit_7 = value & 0b10000000;
            value = bit_7 | (value >> 1);
            flags.n = 0;
            flags.h = 0;
        } else if (y == 6) {
            // SWAP
            const lower: u4 = @truncate(value);
            value = (value >> 4) | (@as(u8, lower) << 4);
            flags.n = 0;
            flags.h = 0;
            flags.c = 0;
        } else if (y == 7) {
            // SRL
            flags.c = @truncate(value);
            value = value >> 1;
            flags.n = 0;
            flags.h = 0;
        } else {
            std.debug.panic("Unknown x:{d}, y:{d}, z:{d}", .{ x, y, z });
        }
        self.writeRegDataValue(z, value);
        if (value == 0) {
            flags.z = 1;
        } else {
            flags.z = 0;
        }
        // if (z == 6) {
        //     return 16;
        // }
        // return 8;
    } else if (x == 1) {
        self.print("BIT {d},{s}\n", .{ y, register });
        flags.z = ~@as(u1, @truncate(value >> y));
        flags.n = 0;
        flags.h = 1;
        // if (z == 6) {
        //     return 12;
        // }
        // return 8;
    } else if (x == 2) {
        self.print("RES {d},{s}\n", .{ y, register });
        value = utils.resetBitValue(value, y);
        self.writeRegDataValue(z, value);
        // if (z == 6) {
        //     return 16;
        // }
        // return 8;
    } else if (x == 3) {
        self.print("SET {d},{s}\n", .{ y, register });
        value = utils.setBitValue(value, y);
        self.writeRegDataValue(z, value);
        // if (z == 6) {
        //     return 16;
        // }
        // return 8;
    } else {
        std.debug.panic("Unknown x:{d}, y:{d}, z:{d}", .{ x, y, z });
    }
}

fn stop(self: *Self, _: u8) void {
    _ = self.read();
    // const extra = self.read();
    // self.std_out.print("{X:02}\n", .{extra}) catch unreachable;
    self.print("STOP\n", .{});
    // @breakpoint();
    halt(self, 0);
    // return 0;
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
