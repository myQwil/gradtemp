const std = @import("std");
const Schedule = @import("Schedule.zig");

const Waybar = struct {
	text: []const u8,
	class: []const u8,
	tooltip: []const u8,

	const inactive: Waybar = .{
		.text = "󰌶 6500",
		.class = "cool",
		.tooltip = "Blue light filter: 6500K (off)",
	};
};

const state = ".cache/gradtemp/state";
const json_inactive = blk: {
	var buf: [128]u8 = undefined;
	var stream = std.io.fixedBufferStream(&buf);
	const writer = stream.writer();
	std.json.stringify(Waybar.inactive, .{ .escape_unicode = true }, writer) catch |e| {
		@compileError("Failed to stringify Waybar.inactive: " ++ @errorName(e));
	};
	var new_buf: [stream.getWritten().len]u8 = undefined;
	@memcpy(&new_buf, buf[0..new_buf.len]);
	break :blk new_buf;
};

fn process(mem: std.mem.Allocator, cmd: []const []const u8) !void {
	var proc = std.process.Child.init(cmd, mem);
	proc.stdout_behavior = .Ignore;
	proc.stderr_behavior = .Ignore;
	_ = try proc.spawn();
	_ = try proc.wait();
}

fn send(value: *const Waybar) !void {
	const stdout_file = std.io.getStdOut().writer();
	var bw = std.io.bufferedWriter(stdout_file);
	const stdout = bw.writer();
	if (value == &Waybar.inactive) {
		try stdout.writeAll(&json_inactive);
	} else {
		try std.json.stringify(value, .{ .escape_unicode = true }, stdout);
	}
	try bw.flush();
}

fn getState(home: std.fs.Dir) !bool {
	const file = try home.openFile(state, .{ .mode = .read_only });
	defer file.close();
	return (try file.reader().readByte() == '1');
}

pub fn main() !void {
	var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
	defer if (gpa.deinit() == .leak) std.debug.print("Memory leaks detected!\n", .{});
	const mem = gpa.allocator();

	var home = try std.fs.cwd().openDir(
		std.posix.getenv("HOME") orelse return error.NoHomeEnv, .{});
	defer home.close();

	var args = std.process.args();
	_ = args.skip();
	if (args.next()) |arg| {
		if (std.fmt.parseInt(u6, arg, 10)) |seg| {
			// Print temperatures over a span of 24 hours.
			// Arg specifies how many segments each hour is divided into.
			const n: u11 = @as(u11, seg) * 24;
			const div: f32 = @floatFromInt(seg);
			const schedule: Schedule = .init(mem, home);
			std.debug.print("\n", .{});
			for (0..n) |i| {
				const h: f32 = @as(f32, @floatFromInt(i)) / div;
				const ih: f32 = @trunc(h);
				std.debug.print("{:0>2}:{:0>2} - {}\n", .{
					@as(u5, @intFromFloat(ih)),
					@as(u6, @intFromFloat((h - ih) * 60)),
					schedule.at(h),
				});
			}
		} else |_| {
			// Toggle the on/off state
			const path = state[0..state.len - 6];
			home.access(path, .{}) catch try home.makePath(path);
			const on: bool = !(getState(home) catch true);

			const file = home.openFile(state, .{ .mode = .write_only })
				catch try home.createFile(state, .{});
			defer file.close();

			try file.writer().writeByte(@as(u8, @intFromBool(on)) + '0');
			if (!on) {
				try process(mem, &.{ "hyprctl", "hyprsunset", "identity" });
			}
		}
		return;
	}

	if (!(getState(home) catch true)) {
		return send(&.inactive);
	}
	const kelvin: u15 = Schedule.init(mem, home).at(blk: {
		const c = @cImport({ @cInclude("time.h"); });
		var time: c.time_t = @intCast(std.time.timestamp());
		const local: *c.struct_tm = c.localtime(&time)
			orelse return error.TimeConversionFailed;

		const hour: f32 = @floatFromInt(local.tm_hour);
		const minute: f32 = @floatFromInt(local.tm_min);
		const second: f32 = @floatFromInt(local.tm_sec);
		break :blk hour + (minute / 60) + (second / (60 * 60));
	});

	var text_buf: [11]u8 = undefined;
	const text = try std.fmt.bufPrint(&text_buf, "󰌵 {}", .{ kelvin });
	if (kelvin == 6500) {
		try process(mem, &.{ "hyprctl", "hyprsunset", "identity" });
	} else {
		try process(mem, &.{ "hyprctl", "hyprsunset", "temperature", text[5..] });
	}

	const class: []const u8 = if (kelvin < 2300)
		"candle"
	else if (kelvin < 3900)
		"warm"
	else if (kelvin < 5500)
		"neutral"
	else
		"cool";

	var tip_buf: [40]u8 = undefined;
	const tooltip = try std.fmt.bufPrint(
		&tip_buf, "Blue light filter: {}K ({s})", .{ kelvin, class });
	return send(&.{ .text = text, .class = class, .tooltip = tooltip });
}
