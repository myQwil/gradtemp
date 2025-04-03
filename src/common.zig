const std = @import("std");

pub fn run(mem: std.mem.Allocator, cmd: []const []const u8) !void {
	var process = std.process.Child.init(cmd, mem);
	process.stdout_behavior = .Ignore;
	process.stderr_behavior = .Ignore;
	_ = try process.spawn();
	_ = try process.wait();
}
