const std = @import("std");

pub const TestType = enum {
    boot_rom,
    doctor_test,
    display_test,
};

pub const PassStatus = enum {
    passed,
    failed,
    crashed,
    unknown,
};

pub const TestEntry = struct {
    test_id: u8,
    path: []const u8,
    name: []const u8,
    type: TestType,
    pass_status: PassStatus,
    notes: []const u8,

    pub fn getStartPc(self: *const TestEntry) u16 {
        return if (self.type == TestType.boot_rom) 0 else 0x0100;
    }

    pub fn isDoctorTest(self: *const TestEntry, display: bool) bool {
        return self.type == TestType.doctor_test and !display;
    }

    pub fn shouldDisplay(self: *const TestEntry) bool {
        return self.type == TestType.display_test or
               self.type == TestType.boot_rom;
    }
};

pub const TestSuite = struct {
    entries: []TestEntry,
    allocator: std.mem.Allocator,

    pub fn findById(self: *const TestSuite, test_id: u8) ?*const TestEntry {
        for (self.entries) |*entry| {
            if (entry.test_id == test_id) {
                return entry;
            }
        }
        return null;
    }

    pub fn deinit(self: *TestSuite) void {
        for (self.entries) |entry| {
            self.allocator.free(entry.path);
            self.allocator.free(entry.name);
            self.allocator.free(entry.notes);
        }
        self.allocator.free(self.entries);
    }
};

pub fn parseTestSuite(allocator: std.mem.Allocator, json_path: []const u8) !TestSuite {
    const file = try std.fs.cwd().openFile(json_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const json_data = try allocator.alloc(u8, file_size);
    defer allocator.free(json_data);
    _ = try file.readAll(json_data);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_data, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const tests_array = root.get("tests") orelse return error.MissingTestsArray;

    if (tests_array != .array) {
        return error.TestsNotArray;
    }

    // First pass: count entries
    var count: usize = 0;
    for (tests_array.array.items) |_| {
        count += 1;
    }

    // Allocate entries array
    var entries = try allocator.alloc(TestEntry, count);
    var idx: usize = 0;

    var seen_ids = std.AutoHashMap(u8, void).init(allocator);
    defer seen_ids.deinit();

    for (tests_array.array.items) |entry_value| {
        if (entry_value != .object) {
            return error.TestNotObject;
        }

        const entry_obj = entry_value.object;
        const test_id_val = entry_obj.get("test_id") orelse return error.MissingTestId;
        const test_id = @as(u8, @intCast(test_id_val.integer));

        if (seen_ids.contains(test_id)) {
            return error.DuplicateTestId;
        }
        try seen_ids.put(test_id, {});

        const path = entry_obj.get("path") orelse return error.MissingPath;
        const name = entry_obj.get("name") orelse return error.MissingName;
        const type_str = entry_obj.get("type") orelse return error.MissingType;
        const pass_status_str = entry_obj.get("pass_status") orelse return error.MissingPassStatus;
        const notes = entry_obj.get("notes") orelse return error.MissingNotes;

        if (path != .string or name != .string or type_str != .string or pass_status_str != .string or notes != .string) {
            return error.InvalidFieldType;
        }

        const entry_type = std.meta.stringToEnum(TestType, type_str.string) orelse return error.InvalidTestType;
        const status = std.meta.stringToEnum(PassStatus, pass_status_str.string) orelse return error.InvalidPassStatus;

        entries[idx] = TestEntry{
            .test_id = test_id,
            .path = try allocator.dupe(u8, path.string),
            .name = try allocator.dupe(u8, name.string),
            .type = entry_type,
            .pass_status = status,
            .notes = try allocator.dupe(u8, notes.string),
        };
        idx += 1;
    }

    return TestSuite{
        .entries = entries,
        .allocator = allocator,
    };
}
