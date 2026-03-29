const Waybar = @This();
const std = @import("std");
const Io = std.Io;

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
	const io = Io.Threaded.global_single_threaded.io();
	var b: [256]u8 = undefined;
	var s = Io.File.stdout().writer(io, &b);
	var j = std.json.Stringify{ .writer = &s.interface };
	j.write(inactive) catch @compileError("Couldn't stringify json_inactive");
	var sized_buf: [s.interface.end]u8 = undefined;
	@memcpy(&sized_buf, s.interface.buffered());
	break :blk sized_buf;
};

pub fn send(value: *const Waybar, io: Io) !void {
	var buf: [256]u8 = undefined;
	var stdout = Io.File.stdout().writer(io, &buf);
	var json = std.json.Stringify{ .writer = &stdout.interface };

	if (value == &inactive) {
		try stdout.interface.writeAll(&json_inactive);
	} else {
		try json.write(value);
	}
	try stdout.interface.flush();
}
