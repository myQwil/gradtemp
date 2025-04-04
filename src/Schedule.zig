const std = @import("std");
const Schedule = @This();

dawn: Slope,
dusk: Slope,

const Config = struct {
	day: u15 = 6500,
	night: u15 = 1900,
	dawn: [2]f32 = .{ 4, 6 },
	dusk: [2]f32 = .{ 19, 21 },

	inline fn init(mem: std.mem.Allocator, home: std.fs.Dir) !Config {
		const file = try home.openFile(
			".config/gradtemp/config.json", .{ .mode = .read_only });
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

	fn Range(T: type) type { return struct {
		lo: T,
		hi: T,
	};}

	fn init(hour: Range(f32), kelvin: Range(u15)) Slope {
		const time: Range(f32) = .{
			.lo = hour.lo,
			.hi = if (hour.hi < hour.lo) hour.hi + 24 else hour.hi,
		};
		const run: f32 = time.hi - time.lo;
		if (run == 0) {
			return .{ .time = time, .m = 0, .b = kelvin.hi };
		} else {
			const irise: i16 = @as(i16, kelvin.hi) - @as(i16, kelvin.lo);
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

pub fn init(mem: std.mem.Allocator, home: std.fs.Dir) Schedule {
	const cfg: Config = Config.init(mem, home) catch .{};
	return .{
		.dawn = .init(
			.{ .lo = cfg.dawn[0], .hi = cfg.dawn[1] },
			.{ .lo = cfg.night, .hi = cfg.day }
		),
		.dusk = .init(
			.{ .lo = cfg.dusk[0], .hi = cfg.dusk[1] },
			.{ .lo = cfg.day, .hi = cfg.night }
		),
	};
}

pub fn at(self: *const Schedule, hr: f32) u15 {
	const dn = &self.dawn.time;
	const dk = &self.dusk.time;
	if (dn.lo < dk.lo) {
		return if (dn.lo <= hr and hr < dk.lo) self.dawn.at(hr) else self.dusk.at(hr);
	} else {
		return if (dk.lo <= hr and hr < dn.lo) self.dusk.at(hr) else self.dawn.at(hr);
	}
}
