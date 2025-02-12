// /home/broderick/code/zig/gameboy/zig-out/bin/gameboy | /home/broderick/code/zig/gameboy/../gameboy-doctor/gameboy-doctor - cpu_instrs 7

pub fn main() !void {
    var buffer: [0xFFFF]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const fba_allocator = fba.allocator();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();

    const std_out = std.io.getStdOut().writer();

    // const file = try std.fs.cwd().openFile("roms/dmg_boot.bin", .{});
    // const file_name = "01-special.gb";
    // const file_name = "02-interrupts.gb";
    // const file_name = "03-op sp,hl.gb";
    // const file_name = "04-op r,imm.gb";
    // const file_name = "05-op rp.gb";
    // const file_name = "06-ld r,r.gb";
    const file_name = "07-jr,jp,call,ret,rst.gb";
    // const file_name = "08-misc instrs.gb";
    // const file_name = "09-op r,r.gb";
    // const file_name = "10-bit ops.gb";
    // const file_name = "11-op a,(hl).gb";
    const file = try std.fs.cwd().openFile("../gb-test-roms/cpu_instrs/individual/" ++ file_name, .{});
    defer file.close();

    const main_memory = try fba_allocator.alloc(u8, 0xFFFF);
    defer fba_allocator.free(main_memory);
    @memset(main_memory, 0);
    _ = try file.readAll(main_memory);

    // LCD Hardcode
    main_memory[0xFF44] = 0x90;

    const args = try std.process.argsAlloc(gpa_allocator);
    defer std.process.argsFree(gpa_allocator, args);
    // std.debug.print("${s}\n", .{args});
    var verbose = false;
    if (args.len > 1 and std.mem.eql(u8, args[1], "--verbose")) {
        verbose = true;
    }

    // zig fmt: off
    var cpu = Cpu{
        .memory = main_memory,
        .pc = 0x0100,
        .counter = 1,
        .should_print = false,
        .should_break = verbose,
        .std_out = std_out
        };
    // zig fmt: on

    const end = 500000;

    try cpu.logState();
    // cpu.print_flags();
    while (cpu.pc < cpu.memory.len) {
        if (verbose and cpu.counter > end) {
            break;
        }
        const op_code = cpu.read();
        // const x = op_code >> 6 & 0b11;
        // const y = op_code >> 3 & 0b111;
        // const z = op_code & 0b111;
        // const p = y >> 1;
        // const q = y & 1;

        if (verbose and cpu.counter == 254074) {
            // if (verbose and cpu.pc == 0xdefb) {
            // if (verbose and sp == 0xdf7e) {
            cpu.should_print = true;
            @breakpoint();
        }

        op_lookup[op_code](&cpu, op_code);
        cpu.counter += 1;
        if (!verbose or cpu.should_print) {
            try cpu.logState();
        }
        // cpu.print_flags();
        // cpu.print("\n", .{});
    }
}

const Cpu = struct {
    memory: []u8,
    pc: u16,
    counter: u32,
    should_print: bool,
    should_break: bool,
    std_out: std.fs.File.Writer,
    fn read(self: *Cpu) u8 {
        const memory_value = self.memory[self.pc];
        self.pc += 1;
        return memory_value;
    }
    fn printIndex(self: *Cpu) void {
        self.print("Current Index: {0d} {0x}\n", .{self.pc});
    }
    fn print(self: *Cpu, comptime fmt: []const u8, args: anytype) void {
        if (self.should_print) {
            std.debug.print(fmt, args);
        }
    }
    fn printFlags(self: *Cpu) void {
        self.print("{b}\n", .{af.sp.flag.full});
        self.print("c: {b}\n", .{flags.c});
        self.print("h: {b}\n", .{flags.h});
        self.print("n: {b}\n", .{flags.n});
        self.print("z: {b}\n", .{flags.z});
    }
    fn logState(self: *Cpu) !void {
        try self.std_out.print("A:{X:02} F:{X:02} B:{X:02} C:{X:02} D:{X:02} E:{X:02} H:{X:02} L:{X:02} SP:{X:04} PC:{X:04} PCMEM:{X:02},{X:02},{X:02},{X:02}", .{ a_reg.*, af.sp.flag.full, bc.sp.hi, bc.sp.lo, de.sp.hi, de.sp.lo, hl.sp.hi, hl.sp.lo, sp, self.pc, self.memory[self.pc], self.memory[self.pc + 1], self.memory[self.pc + 2], self.memory[self.pc + 3] });
        self.print(" - {d}", .{self.counter});
        try self.std_out.print("\n", .{});
    }
    fn getRegDataPointer(self: *Cpu, index: u8) *u8 {
        var data_pointer = reg_8_t[index];
        if (index == 6) {
            self.breakOnAddress(hl.full);
            data_pointer = &self.memory[hl.full];
        }
        return data_pointer;
    }
    fn breakOnAddress(self: *Cpu, address: u16) void {
        // if (self.should_break and address == 0xDF7E) {
        if (self.should_break and address == 0xDF7C) {
            @breakpoint();
        }
    }
    fn breakOnAddressAndValue(self: *Cpu, address: u16, value: u8) void {
        if (self.counter > 254000 and self.should_break and address == 0xDF7C and value == 0xFB) {
            @breakpoint();
            self.should_print = true;
        }
    }
    fn checkCondition(_: *Cpu, index: u8) bool {
        return (index == 0 and flags.z == 0) or (index == 1 and flags.z != 0) or (index == 2 and flags.c == 0) or (index == 3 and flags.c != 0);
    }
};

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

fn nop(_: *Cpu, _: u8) void {
    // std.debug.print("********** NOP ********** ${x:04}\n", .{cpu.index - 1});
    // std.debug.print("********** NOP **********\n", .{});
    // std.debug.print("{X:02}\n", .{op_code});
    // std.debug.panic("", .{});
}

fn nop_vd(_: *Cpu, _: u8) void {}

// Load

fn ld_rp_n16(cpu: *Cpu, op_code: u8) void {
    const p = op_code >> 4 & 0b11;
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
    cpu.getRegDataPointer(y).* = value;
}

fn ld_r_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const z = op_code & 0b111;
    const register1 = reg_8[y];
    const register2 = reg_8[z];
    cpu.print("LD {s},{s}\n", .{ register1, register2 });
    cpu.getRegDataPointer(y).* = cpu.getRegDataPointer(z).*;
}

fn ld_bc_a(cpu: *Cpu, _: u8) void {
    cpu.print("LD (BC),A\n", .{});
    cpu.breakOnAddress(bc.full);
    cpu.memory[bc.full] = a_reg.*;
}

fn ld_de_a(cpu: *Cpu, _: u8) void {
    cpu.print("LD (DE),A\n", .{});
    cpu.breakOnAddress(de.full);
    cpu.memory[de.full] = a_reg.*;
}

fn ld_a_bc(cpu: *Cpu, _: u8) void {
    cpu.print("LD A,(BC)\n", .{});
    a_reg.* = cpu.memory[bc.full];
}

fn ld_a_de(cpu: *Cpu, _: u8) void {
    cpu.print("LD A,(DE)\n", .{});
    a_reg.* = cpu.memory[de.full];
}

fn ld_hli_a(cpu: *Cpu, _: u8) void {
    cpu.print("LD (HL+),A\n", .{});
    cpu.breakOnAddress(hl.full);
    cpu.memory[hl.full] = a_reg.*;
    hl.full += 1;
}

fn ld_hld_a(cpu: *Cpu, _: u8) void {
    cpu.print("LD (HL-),A\n", .{});
    cpu.breakOnAddress(hl.full);
    cpu.memory[hl.full] = a_reg.*;
    hl.full -= 1;
}

fn ld_a_hli(cpu: *Cpu, _: u8) void {
    cpu.print("LD A,(HL+)\n", .{});
    a_reg.* = cpu.memory[hl.full];
    hl.full += 1;
}

fn ld_a_hld(cpu: *Cpu, _: u8) void {
    cpu.print("LD A,(HL-)\n", .{});
    a_reg.* = cpu.memory[hl.full];
    hl.full -= 1;
}

fn ld_a16_a(cpu: *Cpu, _: u8) void {
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("LD (${X:04}),A\n", .{address});
    cpu.breakOnAddressAndValue(address, a_reg.*);
    cpu.memory[address] = a_reg.*;
}

fn ld_a_a16(cpu: *Cpu, _: u8) void {
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("LD A,(${X:04})\n", .{address});
    a_reg.* = cpu.memory[address];
}

fn ld_a16_sp(cpu: *Cpu, _: u8) void {
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("LD ${X:04},SP\n", .{address});
    cpu.breakOnAddress(address);
    cpu.breakOnAddress(address + 1);
    cpu.memory[address] = @truncate(sp);
    cpu.memory[address + 1] = @truncate(sp >> 8);
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
    if (displacement == 0x44) {
        @breakpoint();
    }
    cpu.print("LD ($FF00+${X}),A\n", .{displacement});
    const address: u16 = @as(u16, 0xff00) + displacement;
    if (address > 0xFF00 and address < 0xFFFF) {
        cpu.breakOnAddress(address);
        cpu.memory[address] = a_reg.*;
    }
}

fn ldh_a_a8(cpu: *Cpu, _: u8) void {
    const displacement = cpu.read();
    // if (displacement == 0x44) {
    //     @breakpoint();
    // }
    cpu.print("LD A,($FF00+${X})\n", .{displacement});
    const address: u16 = @as(u16, 0xff00) + displacement;
    a_reg.* = cpu.memory[address];
}

fn ld_sp_hl(cpu: *Cpu, _: u8) void {
    cpu.print("LD SP,HL\n", .{});
    sp = hl.full;
}

fn ld_hl_sp_e8(cpu: *Cpu, _: u8) void {
    const displacement = cpu.read();
    const address = @as(u16, @bitCast(@as(i16, @bitCast(cpu.pc)) + @as(i8, @bitCast(displacement))));
    cpu.print("LD HL,SP+${X:02}\n", .{address});
    std.debug.panic("Not implemented", .{});
}

// Jumps

fn call(cpu: *Cpu, address: u16) void {
    push(cpu, cpu.pc);
    cpu.pc = address;
}

fn call_a16(cpu: *Cpu, _: u8) void {
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("CALL ${X:04}\n", .{address});
    call(cpu, address);
}

fn call_cc_a16(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const condition = reg_cc[y];
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("CALL {s},${X:04}\n", .{ condition, address });
    if (cpu.checkCondition(y)) {
        call(cpu, address);
    }
}

fn jr_cc_e8(cpu: *Cpu, op_code: u8) void {
    const y_offset = op_code >> 3 & 0b111 - 4;
    const condition = reg_cc[y_offset];
    const displacement = cpu.read();
    const address = @as(u16, @bitCast(@as(i16, @bitCast(cpu.pc)) + @as(i8, @bitCast(displacement))));
    cpu.print("JR {s},Addr_{x:04}\n", .{ condition, address });
    if (cpu.checkCondition(y_offset)) {
        cpu.pc = address;
    }
}

fn jr_e8(cpu: *Cpu, _: u8) void {
    const displacement = cpu.read();
    const address = @as(u16, @bitCast(@as(i16, @bitCast(cpu.pc)) + @as(i8, @bitCast(displacement))));
    cpu.print("JR Addr_{x:04}\n", .{address});
    cpu.pc = address;
}

fn ret(cpu: *Cpu, _: u8) void {
    cpu.print("RET\n", .{});
    cpu.pc = pop(cpu);
}

fn reti(cpu: *Cpu, op_code: u8) void {
    cpu.print("RETI\n", .{});
    ei(cpu, op_code);
    ret(cpu, op_code);
}

fn ret_cc(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const condition = reg_cc[y];
    cpu.print("RET {s}\n", .{condition});
    if (cpu.checkCondition(y)) {
        ret(cpu, 0);
    }
}

fn jp_a16(cpu: *Cpu, _: u8) void {
    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("JP Addr_{x:04}\n", .{address});
    cpu.pc = address;
}

fn jp_cc_a16(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const condition = reg_cc[y];

    const right = cpu.read();
    const address: u16 = (@as(u16, cpu.read()) << 8) | right;
    cpu.print("JP {s},Addr_{x:04}\n", .{ condition, address });
    if (cpu.checkCondition(y)) {
        cpu.pc = address;
    }
}

fn jp_hl(cpu: *Cpu, _: u8) void {
    cpu.print("JP HL\n", .{});
    cpu.pc = hl.full;
}

fn rst(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const vec = y * 8;
    cpu.print("RST Addr_{x:04}\n", .{vec});
    call(cpu, vec);
}

fn push(cpu: *Cpu, value: u16) void {
    sp -= 1;
    cpu.breakOnAddressAndValue(sp, @truncate(value >> 8));
    cpu.memory[sp] = @truncate(value >> 8);
    sp -= 1;
    cpu.breakOnAddressAndValue(sp, @truncate(value));
    cpu.memory[sp] = @truncate(value);
}

fn pop(cpu: *Cpu) u16 {
    var new_value: u16 = @as(u16, cpu.memory[sp]);
    sp += 1;
    new_value = new_value | (@as(u16, cpu.memory[sp]) << 8);
    sp += 1;
    return new_value;
}

// Arithmetic

fn inc_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("INC {s}\n", .{register});
    const data_pointer = cpu.getRegDataPointer(y);
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

fn inc_rp(cpu: *Cpu, op_code: u8) void {
    const p = op_code >> 4 & 0b11;
    const register = reg_p[p];
    cpu.print("INC {s}\n", .{register});
    reg_p_t[p].* += 1;
}

fn dec_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("DEC {s}\n", .{register});
    const data_pointer = cpu.getRegDataPointer(y);
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

fn dec_rp(cpu: *Cpu, op_code: u8) void {
    const p = op_code >> 4 & 0b11;
    const register = reg_p[p];
    cpu.print("DEC {s}\n", .{register});
    reg_p_t[p].* -= 1;
}

fn add_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("ADD {s}\n", .{register});
    std.debug.panic("Not implemented", .{});
}

fn add_hl_rp(cpu: *Cpu, op_code: u8) void {
    const p = op_code >> 4 & 0b11;
    const register = reg_p[p];
    cpu.print("ADD HL,{s}\n", .{register});
    const current_value = reg_p_t[p].*;
    const result = @addWithOverflow(hl.full, current_value);
    const half_result = @addWithOverflow(@as(u12, @truncate(hl.full)), @as(u12, @truncate(current_value)));
    hl.full = result[0];
    flags.n = 0;
    flags.h = half_result[1];
    flags.c = result[1];
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
    var change = cpu.read();
    const current_value = a_reg.*;
    cpu.print("{s} A,${X:02}\n", .{ register, change });
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

fn and_r(cpu: *Cpu, op_code: u8) void {
    const y = op_code >> 3 & 0b111;
    const register = reg_8[y];
    cpu.print("AND A,{s}\n", .{register});
    std.debug.panic("Not implemented", .{});
}

fn or_r(cpu: *Cpu, op_code: u8) void {
    const z = op_code & 0b111;
    const register = reg_8[z];
    cpu.print("OR A,{s}\n", .{register});
    a_reg.* = a_reg.* | cpu.getRegDataPointer(z).*;
    if (a_reg.* == 0) {
        flags.z = 1;
    } else {
        flags.z = 0;
    }
    flags.n = 0;
    flags.h = 0;
    flags.c = 0;
}

fn xor_r(cpu: *Cpu, op_code: u8) void {
    const z = op_code & 0b111;
    const register = reg_8[z];
    cpu.print("XOR A,{s}\n", .{register});
    a_reg.* = cpu.getRegDataPointer(z).* ^ a_reg.*;
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

fn push_rp2(cpu: *Cpu, op_code: u8) void {
    const p = op_code >> 4 & 0b11;
    const register = reg_p2[p];
    cpu.print("PUSH {s}\n", .{register});
    push(cpu, reg_p2_t[p].*);
}

fn pop_rp2(cpu: *Cpu, op_code: u8) void {
    const p = op_code >> 4 & 0b11;
    const register = reg_p2[p];
    cpu.print("POP {s}\n", .{register});
    reg_p2_t[p].* = pop(cpu);
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
    const old_c: u8 = flags.c;
    flags.c = @truncate(a_reg.* & 0x1);
    a_reg.* = (a_reg.* >> 1) | (old_c << 7);
    flags.n = 0;
    flags.h = 0;
    flags.z = 0;
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
    cpu.print("DI\n", .{});
}

fn ei(cpu: *Cpu, _: u8) void {
    cpu.print("EI\n", .{});
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
        const data_pointer = cpu.getRegDataPointer(z);
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
        cpu.print("BIT {d},{s}\n", .{ y, register });
        std.debug.panic("BIT Not implemented x:{d}, y:{d}, z:{d}", .{ x, y, z });
    } else {
        cpu.print("NOP CB\n", .{});
        std.debug.panic("Not implemented x:{d}, y:{d}, z:{d}", .{ x, y, z });
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

const reg_alu: [8][]const u8 = .{ "ADD", "ADC", "SUB", "SBC", "AND", "XOR", "OR", "CP" };

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
    ret_cc,      pop_rp2,   jp_cc_a16, nop_vd,    call_cc_a16, push_rp2, alu_n8,  rst,    // D
    ret_cc,      reti,      jp_cc_a16, nop_vd,    call_cc_a16, nop_vd,   alu_n8,  rst,   
    ldh_a8_a,    pop_rp2,   ldh_c_a,   nop_vd,    nop_vd,      push_rp2, alu_n8,  rst,    // E
    add_sp_e8,   jp_hl,     ld_a16_a,  nop_vd,    nop_vd,      nop_vd,   alu_n8,  rst,   
    ldh_a_a8,    pop_rp2,   ldh_a_c,   di,        nop_vd,      push_rp2, alu_n8,  rst,    // F
    ld_hl_sp_e8, ld_sp_hl,  ld_a_a16,  ei,        nop_vd,      nop_vd,   alu_n8,  rst
    };
// zig fmt: on

const std = @import("std");
