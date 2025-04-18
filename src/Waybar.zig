const Waybar = @This();
const std = @import("std");

text: []const u8,
class: []const u8,
tooltip: []const u8,
percentage: u7,

pub const inactive: Waybar = .{
	.text = "6500",
	.class = "cool",
	.tooltip = "Blue light filter: 6500K (off)",
	.percentage = 0,
};

const json_inactive = blk: {
	var buf: [128]u8 = undefined;
	var stream = std.io.fixedBufferStream(&buf);
	std.json.stringify(&inactive, .{}, stream.writer()) catch |e| {
		@compileError("Failed to stringify Waybar.inactive: " ++ @errorName(e));
	};
	var sized_buf: [stream.getWritten().len]u8 = undefined;
	@memcpy(&sized_buf, buf[0..sized_buf.len]);
	break :blk sized_buf;
};

pub fn send(value: *const Waybar) !void {
	const stdout_file = std.io.getStdOut().writer();
	var bw = std.io.bufferedWriter(stdout_file);
	const stdout = bw.writer();
	if (value == &inactive) {
		try stdout.writeAll(&json_inactive);
	} else {
		try std.json.stringify(value, .{}, stdout);
	}
	try bw.flush();
}
