const std = @import("std");
const Slope = @import("Slope.zig");
const Config = @import("Config.zig");
const Waybar = @import("Waybar.zig");
const Io = std.Io;

const state = ".cache/gradtemp/state";

fn getState(io: Io, home: Io.Dir) !bool {
	const file = try home.openFile(io, state, .{ .mode = .read_only });
	defer file.close(io);
	var buf: [16]u8 = undefined;
	var reader = file.reader(io, &buf);
	return ((try reader.interface.take(1))[0] == '1');
}

fn run(io: Io, cmd: []const []const u8) !void {
	var child = try std.process.spawn(io, .{
		.argv = cmd,
		.stdin = .ignore,
		.stdout = .ignore,
		.stderr = .ignore,
	});
	_ = try child.wait(io);
}

pub fn main(init: std.process.Init) !void {
	const io = init.io;
	const gpa = init.gpa;
	const environ_map = init.environ_map;

	var home = if (environ_map.get("HOME")) |env|
		Io.Dir.cwd().openDir(io, env, .{}) catch Io.Dir.cwd()
	else Io.Dir.cwd();
	defer home.close(io);

	const identity = 6500;
	const cmd_identity = [_][]const u8{ "hyprctl", "hyprsunset", "identity", "true" };

	var args = init.minimal.args.iterate();
	_ = args.skip();
	if (args.next()) |arg| {
		return if (std.fmt.parseInt(u6, arg, 10)) |seg| {
			// Print temperatures over a span of 24 hours.
			// Arg specifies how many segments each hour is divided into.
			const n: u11 = @as(u11, seg) * 24;
			const div: f32 = @floatFromInt(seg);

			const cfg: Config = .init(io, gpa, home);
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
			home.access(io, path, .{}) catch try home.createDirPath(io, path);
			const on: bool = !(getState(io, home) catch true);

			const file = home.openFile(io, state, .{ .mode = .write_only })
				catch try home.createFile(io, state, .{});
			defer file.close(io);

			var buf: [16]u8 = undefined;
			var w = file.writer(io, &buf);
			try w.interface.writeByte(@as(u8, @intFromBool(on)) + '0');
			try w.flush();
			if (!on) {
				// running this now avoids performing it on every update
				try run(io, &cmd_identity);
			}
		};
	}

	if (!(getState(io, home) catch true)) {
		return Waybar.inactive.send(io);
	}
	const kelvin: u15 = Config.init(io, gpa, home).at(blk: {
		const now: Io.Timestamp = .now(io, .real);
		const sec: i96 = @divTrunc(now.nanoseconds, std.time.ns_per_s);

		// Some idea of how it'd be done if zig had timezone support
		// const ep = std.time.epoch;
		// const esec: ep.EpochSeconds = .{ .secs = @intCast(sec) };
		// const dsec: ep.DaySeconds = esec.getDaySeconds();
		// const hour: f32 = @floatFromInt(dsec.getHoursIntoDay());
		// const minute: f32 = @floatFromInt(dsec.getMinutesIntoHour());
		// const second: f32 = @floatFromInt(dsec.getSecondsIntoMinute());

		const c = @cImport({ @cInclude("time.h"); });
		var time: c.time_t = @intCast(sec);
		const local: *c.struct_tm = c.localtime(&time)
			orelse return error.TimeConversionFailed;

		const hour: f32 = @floatFromInt(local.tm_hour);
		const minute: f32 = @floatFromInt(local.tm_min);
		const second: f32 = @floatFromInt(local.tm_sec);
		break :blk hour + (minute / 60) + (second / (60 * 60));
	});

	var text_buf: [6]u8 = undefined;
	const text = try std.fmt.bufPrint(&text_buf, "{}", .{ kelvin });

	try run(io, if (kelvin == identity)
		&cmd_identity
	else &.{ "hyprctl", "hyprsunset", "temperature", text });

	const class: []const u8 =
		if      (kelvin >= 5500) "cool"
		else if (kelvin >= 4000) "neutral"
		else if (kelvin >= 2500) "warm"
		else                     "candle";

	const fmt = "Blue light filter: {}K ({s})";
	var buf: [256]u8 = undefined;
	const tooltip = try std.fmt.bufPrint(&buf, fmt, .{ kelvin, class });
	return (Waybar{
		.text = text,
		.class = class,
		.tooltip = tooltip,
		.percentage = 100,
	}).send(io);
}
