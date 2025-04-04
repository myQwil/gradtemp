const std = @import("std");
const cmn = @import("common.zig");

const filename = "state";

fn getState(dir: std.fs.Dir) !bool {
	const file = try dir.openFile(filename, .{ .mode = .read_only });
	defer file.close();

	return (try file.reader().readByte() == '1');
}

pub fn main() !void {
	var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
	defer if (gpa.deinit() == .leak) std.debug.print("Memory leaks detected!\n", .{});

	const mem = gpa.allocator();
	const home = std.posix.getenv("HOME") orelse return error.NoHomeEnv;
	const path = try std.fs.path.join(mem, &.{ home, ".cache/gradtemp" });
	defer mem.free(path);

	var dir = blk: {
		const cwd = std.fs.cwd();
		cwd.access(path, .{}) catch try cwd.makePath(path);
		break :blk try cwd.openDir(path, .{});
	};
	defer dir.close();

	const on: bool = !(getState(dir) catch true);
	const file = dir.openFile(filename, .{ .mode = .write_only })
		catch try dir.createFile(filename, .{});
	defer file.close();

	_ = try file.writer().writeByte(@as(u8, @intFromBool(on)) + '0');

	if (!on) {
		try cmn.run(mem, &.{ "hyprctl", "hyprsunset", "identity" });
	}
}
