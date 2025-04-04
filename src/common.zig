const std = @import("std");

pub fn process(mem: std.mem.Allocator, cmd: []const []const u8) !void {
	var proc = std.process.Child.init(cmd, mem);
	proc.stdout_behavior = .Ignore;
	proc.stderr_behavior = .Ignore;
	_ = try proc.spawn();
	_ = try proc.wait();
}
