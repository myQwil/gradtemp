const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Waybar = struct {
	text: []const u8,
	class: []const u8,
	tooltip: []const u8,

	pub const inactive: Waybar = .{
		.text = "󰌶 6500",
		.class = "cool",
		.tooltip = "Blue light filter: 6500K (off)",
	};
};

pub fn run(cmd: []const []const u8, mem: Allocator) !void {
	var process = std.process.Child.init(cmd, mem);
	process.stdout_behavior = .Ignore;
	process.stderr_behavior = .Ignore;
	_ = try process.spawn();
	_ = try process.wait();
}

pub fn send(value: Waybar) !void {
	const stdout_file = std.io.getStdOut().writer();
	var bw = std.io.bufferedWriter(stdout_file);
	const stdout = bw.writer();
	_ = try std.json.stringify(value, .{ .escape_unicode = true }, stdout);
	try bw.flush();
}
