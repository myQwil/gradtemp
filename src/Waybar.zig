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

var buf: [256]u8 = undefined;
var stdout = std.fs.File.stdout().writer(&buf);
var json = std.json.Stringify{ .writer = &stdout.interface };

const json_inactive = blk: {
	var b: [256]u8 = undefined;
	var s = std.fs.File.stdout().writer(&b);
	var j = std.json.Stringify{ .writer = &s.interface };
	j.write(inactive) catch @compileError("Couldn't stringify json_inactive");
	var sized_buf: [s.interface.end]u8 = undefined;
	@memcpy(&sized_buf, b[0..sized_buf.len]);
	break :blk sized_buf;
};

pub fn send(value: *const Waybar) !void {
	if (value == &inactive) {
		try stdout.interface.writeAll(&json_inactive);
	} else {
		try json.write(value);
	}
	try stdout.interface.flush();
}
