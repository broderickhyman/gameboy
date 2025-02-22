pub fn resetBit(pointer: *u8, shift: u3) void {
    const mask = ~(@as(u8, 1) << shift);
    pointer.* = pointer.* & mask;
}

pub fn resetBitValue(value: u8, shift: u3) u8 {
    const mask = ~(@as(u8, 1) << shift);
    return value & mask;
}

pub fn setBit(pointer: *u8, shift: u3) void {
    const mask = @as(u8, 1) << shift;
    pointer.* = pointer.* | mask;
}

pub fn setBitValue(value: u8, shift: u3) u8 {
    const mask = @as(u8, 1) << shift;
    return value | mask;
}

pub const Mapper = enum {
    None,
    MBC1,
    MBC2,
};

pub fn getMapperName(mapper: Mapper) []const u8 {
    return switch (mapper) {
        Mapper.MBC1 => "MBC1",
        Mapper.MBC2 => "MBC2",
        else => "None",
    };
}
