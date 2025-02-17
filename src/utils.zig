pub fn resetBit(pointer: *u8, shift: u3) void {
    const mask = ~(@as(u8, 1) << shift);
    pointer.* = pointer.* & mask;
}

pub fn setBit(pointer: *u8, shift: u3) void {
    const mask = @as(u8, 1) << shift;
    pointer.* = pointer.* | mask;
}
