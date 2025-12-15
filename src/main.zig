const std = @import("std");
const Slope = @import("Slope.zig");
const Config = @import("Config.zig");
const Waybar = @import("Waybar.zig");

var buf: [256]u8 = undefined;
const state = ".cache/gradtemp/state";

fn getState(home: std.fs.Dir) !bool {
	const file = try home.openFile(state, .{ .mode = .read_only });
	defer file.close();
	var reader = file.reader(&buf);
	return ((try reader.interface.take(1))[0] == '1');
}

fn process(mem: std.mem.Allocator, cmd: []const []const u8) !void {
	var proc = std.process.Child.init(cmd, mem);
	proc.stdout_behavior = .Ignore;
	proc.stderr_behavior = .Ignore;
	_ = try proc.spawn();
	_ = try proc.wait();
}

pub fn main() !void {
	var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
	defer if (gpa.deinit() == .leak) std.debug.print("Memory leaks detected!\n", .{});
	const mem = gpa.allocator();

	var home = if (std.posix.getenv("HOME")) |env| std.fs.cwd().openDir(env, .{})
		catch std.fs.cwd() else std.fs.cwd();
	defer home.close();

	const identity = 6500;
	const cmd_identity = [_][]const u8{ "hyprctl", "hyprsunset", "identity", "true" };

	var args = std.process.args();
	_ = args.skip();
	if (args.next()) |arg| {
		return if (std.fmt.parseInt(u6, arg, 10)) |seg| {
			// Print temperatures over a span of 24 hours.
			// Arg specifies how many segments each hour is divided into.
			const n: u11 = @as(u11, seg) * 24;
			const div: f32 = @floatFromInt(seg);

			const cfg: Config = .init(mem, home);
			const dawn: Slope = cfg.getDawn();
			const dusk: Slope = cfg.getDusk();
			const dn = &dawn.time;
			const dk = &dusk.time;

			std.debug.print("\n", .{});
			for (0..n) |i| {
				const h: f32 = @as(f32, @floatFromInt(i)) / div;
				const ih: f32 = @trunc(h);
				std.debug.print("{:0>2}:{:0>2} - {}\n", .{
					@as(u5, @intFromFloat(ih)),
					@as(u6, @intFromFloat(@round((h - ih) * 60))),
					if (dn.lo < dk.lo)
						if (dn.lo <= h and h < dk.lo) dawn.at(h) else dusk.at(h)
					else
						if (dk.lo <= h and h < dn.lo) dusk.at(h) else dawn.at(h),
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

			buf[0] = @as(u8, @intFromBool(on)) + '0';
			try file.writeAll(buf[0..1]);
			if (!on) {
				// running this now avoids performing it on every update
				try process(mem, &cmd_identity);
			}
		};
	}

	if (!(getState(home) catch true)) {
		return Waybar.inactive.send();
	}
	const kelvin: u15 = Config.init(mem, home).at(blk: {
		const c = @cImport({ @cInclude("time.h"); });
		var time: c.time_t = @intCast(std.time.timestamp());
		const local: *c.struct_tm = c.localtime(&time)
			orelse return error.TimeConversionFailed;

		const hour: f32 = @floatFromInt(local.tm_hour);
		const minute: f32 = @floatFromInt(local.tm_min);
		const second: f32 = @floatFromInt(local.tm_sec);
		break :blk hour + (minute / 60) + (second / (60 * 60));
	});

	var text_buf: [6]u8 = undefined;
	const text = try std.fmt.bufPrint(&text_buf, "{}", .{ kelvin });

	try process(mem, if (kelvin == identity)
		&cmd_identity
	else
		&.{ "hyprctl", "hyprsunset", "temperature", text });

	const class: []const u8 =
		if      (kelvin >= 5500) "cool"
		else if (kelvin >= 4000) "neutral"
		else if (kelvin >= 2500) "warm"
		else                     "candle";

	const fmt = "Blue light filter: {}K ({s})";
	const tooltip = try std.fmt.bufPrint(&buf, fmt, .{ kelvin, class });
	return (Waybar{
		.text = text,
		.class = class,
		.tooltip = tooltip,
		.percentage = 100,
	}).send();
}
