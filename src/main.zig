const std = @import("std");
const c = @cImport({
	@cInclude("time.h");
});

const Allocator = std.mem.Allocator;

fn Range(T: type) type { return struct {
	lo: T,
	hi: T,
};}

const Slope = struct {
	time: Range(f32),
	m: f32,
	b: u15,

	fn init(hour: Range(f32), temp: Range(u15)) Slope {
		const time: Range(f32) = .{
			.lo = hour.lo,
			.hi = if (hour.hi < hour.lo) hour.hi + 24 else hour.hi,
		};
		const run: f32 = time.hi - time.lo;
		if (run == 0) {
			return .{ .time = time, .m = 0, .b = temp.hi };
		} else {
			const irise: i16 = @as(i16, @intCast(temp.hi)) - @as(i16, @intCast(temp.lo));
			const rise: f32 = @floatFromInt(irise);
			return .{ .time = time, .m = rise / run, .b = temp.lo };
		}
	}

	fn at(self: *const Slope, hour: f32) u15 {
		const t = &self.time;
		const x: f32 = @min(if (hour < t.lo) hour + 24 else hour, t.hi) - t.lo;
		const temp: f32 = @round(self.m * x + @as(f32, @floatFromInt(self.b)));
		return @intFromFloat(temp);
	}
};

const Config = struct {
	day: u15 = 6500,
	night: u15 = 1900,
	dawn: [2]f32 = .{ 4, 6 },
	dusk: [2]f32 = .{ 19, 21 },

	fn init(mem: Allocator) !Config {
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

const ColorSched = struct {
	dawn: Slope,
	dusk: Slope,

	fn init(cfg: *const Config) ColorSched {
		const dawn_period: Range(f32) = .{ .lo = cfg.dawn[0], .hi = cfg.dawn[1] };
		const dusk_period: Range(f32) = .{ .lo = cfg.dusk[0], .hi = cfg.dusk[1] };
		return .{
			.dawn = .init(dawn_period, .{ .lo = cfg.night, .hi = cfg.day }),
			.dusk = .init(dusk_period, .{ .lo = cfg.day, .hi = cfg.night }),
		};
	}

	fn at(self: *const ColorSched, hr: f32) u15 {
		const dn = &self.dawn.time;
		const dk = &self.dusk.time;
		if (dn.lo < dk.lo) {
			return if (dn.lo <= hr and hr < dk.lo) self.dawn.at(hr) else self.dusk.at(hr);
		} else {
			return if (dk.lo <= hr and hr < dn.lo) self.dusk.at(hr) else self.dawn.at(hr);
		}
	}
};

fn getState(mem: Allocator) !bool {
	const home = std.posix.getenv("HOME") orelse return error.NoHomeEnv;
	const path = try std.fs.path.join(mem, &.{ home, ".cache/gradtemp/state" });
	defer mem.free(path);

	const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
	defer file.close();

	return (try file.reader().readByte() == '1');
}

fn getHour() !f32 {
	var time: c.time_t = @intCast(std.time.timestamp());
	const local: *c.struct_tm = c.localtime(&time)
		orelse return error.TimeConversionFailed;

	const hour: f32 = @floatFromInt(local.tm_hour);
	const minute: f32 = @floatFromInt(local.tm_min);
	const second: f32 = @floatFromInt(local.tm_sec);
	return hour + (minute / 60) + (second / (60 * 60));
}

const Waybar = struct {
	text: []const u8,
	class: []const u8,
	tooltip: []const u8,
};

pub fn main() !void {
	var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
	defer switch (gpa.deinit()) {
		.leak => {}, // std.debug.print("Memory leaks detected!\n", .{}),
		.ok => {}, // std.debug.print("No memory leaks detected.\n", .{}),
	};
	const mem = gpa.allocator();

	const sched: ColorSched = blk: {
		const cfg: Config = Config.init(mem) catch .{};
		break :blk .init(&cfg);
	};

	var args = std.process.args();
	_ = args.skip();
	if (args.next()) |arg| {
		// Print temperatures over a span of 24 hours.
		// Arg specifies how many segments each hour is divided into.
		const div: f32 = try std.fmt.parseFloat(f32, arg);
		const n: u15 = @intFromFloat(24 * div);
		std.debug.print("\n", .{});
		for (0..n) |i| {
			const h: f32 = @as(f32, @floatFromInt(i)) / div;
			const ih: f32 = @trunc(h);
			std.debug.print("{:0>2}:{:0>2} - {}\n", .{
				@as(u5, @intFromFloat(ih)),
				@as(u6, @intFromFloat((h - ih) * 60)),
				sched.at(h),
			});
		}
		return;
	}

	const identity: u15 = 6500;
	const on: bool = getState(mem) catch true;
	const temp: u15 = if (on) sched.at(try getHour()) else identity;
	const bulb: []const u8 = if (on) "󰌵" else "󰌶";

	var buf: [11]u8 = undefined;
	const s_temp = try std.fmt.bufPrint(&buf, "{s} {}", .{ bulb, temp });

	var cmd: std.ArrayList([]const u8) = .init(mem);
	defer cmd.deinit();

	try cmd.appendSlice(&.{ "hyprctl", "hyprsunset" });
	if (temp == identity) {
		try cmd.append("identity");
	} else {
		try cmd.appendSlice(&.{ "temperature", s_temp[bulb.len + 1..] });
	}

	var process = std.process.Child.init(cmd.items, mem);
	process.stdout_behavior = .Ignore;
	process.stderr_behavior = .Ignore;
	_ = try process.spawn();
	_ = try process.wait();

	const class: []const u8 = if (temp < 2300)
		"candle"
	else if (temp < 3900)
		"warm"
	else if (temp < 5500)
		"neutral"
	else
		"cool";

	var ttip: [40]u8 = undefined;
	const tooltip = try std.fmt.bufPrint(&ttip, "Blue light filter: {}K ({s})", .{
		temp,
		if (on) class else "off",
	});

	const stdout_file = std.io.getStdOut().writer();
	var bw = std.io.bufferedWriter(stdout_file);
	const stdout = bw.writer();

	_ = try std.json.stringify(Waybar{
		.text = s_temp,
		.class = class,
		.tooltip = tooltip,
	}, .{ .escape_unicode = true }, stdout);

	try bw.flush();
}
