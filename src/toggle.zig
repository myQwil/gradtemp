const std = @import("std");

const path = "/tmp/gradtemp_state";

fn getState() !bool {
	const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
	defer file.close();

	return (try file.reader().readByte() == '1');
}

pub fn main() !void {
	const on: bool = getState() catch true;
	const file = std.fs.cwd().openFile(path, .{ .mode = .write_only })
		catch try std.fs.cwd().createFile(path, .{});
	defer file.close();

	_ = try file.writer().writeByte(@as(u8, @intFromBool(!on)) + '0');
}
