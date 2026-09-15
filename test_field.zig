const std = @import("std");

const MyStruct = struct {
    name: []const u8,
    step: i32,
};

pub fn main() void {
    const s = MyStruct{ .name = "test", .step = 42 };
    const ptr: *MyStruct = @fieldParentPtr("step", &s.step);
    std.debug.print("Name: {s}\n", .{ptr.name});
}
