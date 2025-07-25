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

// const json_inactive = blk: {
// json.write(inactive) catch |e| {
// @compileError("Failed to stringify Waybar.inactive: " ++ @errorName(e));
// };
// var sized_buf: [stdout.pos]u8 = undefined;
// @memcpy(&sized_buf, buf[0..sized_buf.len]);
// break :blk sized_buf;
// };
const json_inactive = "{\"text\":\"6500\",\"class\":\"cool\","
	++ "\"tooltip\":\"Blue light filter: 6500K (off)\",\"percentage\":0}";

pub fn send(value: *const Waybar) !void {
	if (value == &inactive) {
		try stdout.interface.writeAll(json_inactive);
	} else {
		try json.write(value);
	}
	try json.writer.flush();
}
