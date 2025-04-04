const std = @import("std");

const state_name = "state";

fn Range(T: type) type { return struct {
	lo: T,
	hi: T,
};}

const Config = struct {
	day: u15 = 6500,
	night: u15 = 1900,
	dawn: [2]f32 = .{ 4, 6 },
	dusk: [2]f32 = .{ 19, 21 },

	fn init(mem: std.mem.Allocator) !Config {
		const home = std.posix.getenv("HOME") orelse return error.NoHomeEnv;
		const path = try std.fs.path.join(mem, &.{ home, ".config/gradtemp/config.json" });
		defer mem.free(path);

		const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
		defer file.close();

		const contents = try file.readToEndAlloc(mem, 1024);
		defer mem.free(contents);

		const parsed = try std.json.parseFromSlice(Config, mem, contents, .{});
		defer parsed.deinit();

		return parsed.value;
	}
};

const Slope = struct {
	time: Range(f32),
	m: f32,
	b: u15,

	fn init(hour: Range(f32), kelvin: Range(u15)) Slope {
		const time: Range(f32) = .{
			.lo = hour.lo,
			.hi = if (hour.hi < hour.lo) hour.hi + 24 else hour.hi,
		};
		const run: f32 = time.hi - time.lo;
		if (run == 0) {
			return .{ .time = time, .m = 0, .b = kelvin.hi };
		} else {
			const irise: i16 = @as(i16, @intCast(kelvin.hi)) - @as(i16, @intCast(kelvin.lo));
			const rise: f32 = @floatFromInt(irise);
			return .{ .time = time, .m = rise / run, .b = kelvin.lo };
		}
	}

	fn at(self: *const Slope, hour: f32) u15 {
		const t = &self.time;
		const x: f32 = @min(if (hour < t.lo) hour + 24 else hour, t.hi) - t.lo;
		const kelvin: f32 = @round(self.m * x + @as(f32, @floatFromInt(self.b)));
		return @intFromFloat(kelvin);
	}
};

const Schedule = struct {
	dawn: Slope,
	dusk: Slope,

	fn init(cfg: *const Config) Schedule {
		const dawn_period: Range(f32) = .{ .lo = cfg.dawn[0], .hi = cfg.dawn[1] };
		const dusk_period: Range(f32) = .{ .lo = cfg.dusk[0], .hi = cfg.dusk[1] };
		return .{
			.dawn = .init(dawn_period, .{ .lo = cfg.night, .hi = cfg.day }),
			.dusk = .init(dusk_period, .{ .lo = cfg.day, .hi = cfg.night }),
		};
	}

	fn at(self: *const Schedule, hr: f32) u15 {
		const dn = &self.dawn.time;
		const dk = &self.dusk.time;
		if (dn.lo < dk.lo) {
			return if (dn.lo <= hr and hr < dk.lo) self.dawn.at(hr) else self.dusk.at(hr);
		} else {
			return if (dk.lo <= hr and hr < dn.lo) self.dusk.at(hr) else self.dawn.at(hr);
		}
	}
};

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

pub fn process(mem: std.mem.Allocator, cmd: []const []const u8) !void {
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

fn getState(mem: std.mem.Allocator) !bool {
	const home = std.posix.getenv("HOME") orelse return error.NoHomeEnv;
	const path = try std.fs.path.join(mem, &.{ home, ".cache/gradtemp/state" });
	defer mem.free(path);

	const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
	defer file.close();

	return (try file.reader().readByte() == '1');
}

fn getStateFromDir(dir: std.fs.Dir) !bool {
	const file = try dir.openFile(state_name, .{ .mode = .read_only });
	defer file.close();

	return (try file.reader().readByte() == '1');
}

pub fn main() !void {
	var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
	defer if (gpa.deinit() == .leak) std.debug.print("Memory leaks detected!\n", .{});

	const mem = gpa.allocator();
	var args = std.process.args();
	_ = args.skip();
	if (args.next()) |arg| {
		if (std.fmt.parseInt(u6, arg, 10)) |seg| {
			// Print temperatures over a span of 24 hours.
			// Arg specifies how many segments each hour is divided into.
			const n: u11 = @as(u11, @intCast(seg)) * 24;
			const div: f32 = @floatFromInt(seg);
			const schedule: Schedule = .init(&(Config.init(mem) catch .{}));
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
			const home = std.posix.getenv("HOME") orelse return error.NoHomeEnv;
			const path = try std.fs.path.join(mem, &.{ home, ".cache/gradtemp" });
			defer mem.free(path);

			var dir = blk: {
				const cwd = std.fs.cwd();
				cwd.access(path, .{}) catch try cwd.makePath(path);
				break :blk try cwd.openDir(path, .{});
			};
			defer dir.close();

			const on: bool = !(getStateFromDir(dir) catch true);
			const file = dir.openFile(state_name, .{ .mode = .write_only })
				catch try dir.createFile(state_name, .{});
			defer file.close();

			_ = try file.writer().writeByte(@as(u8, @intFromBool(on)) + '0');

			if (!on) {
				try process(mem, &.{ "hyprctl", "hyprsunset", "identity" });
			}
		}
		return;
	}

	if (!(getState(mem) catch true)) {
		return send(&.inactive);
	}
	const kelvin: u15 = Schedule.init(&(Config.init(mem) catch .{})).at(blk: {
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
	const tooltip = try std.fmt.bufPrint(&tip_buf, "Blue light filter: {}K ({s})", .{
		kelvin, class,
	});
	return send(&.{ .text = text, .class = class, .tooltip = tooltip });
}
