const Schedule = @This();
const std = @import("std");

dawn: Slope,
dusk: Slope,

const Scale = enum {
	linear,
	logarithmic,
};

const Config = struct {
	day: u15 = 6500,
	night: u15 = 1900,
	dawn: [2]f32 = .{ 4, 6 },
	dusk: [2]f32 = .{ 19, 21 },
	scale: Scale = .linear,

	inline fn init(mem: std.mem.Allocator, home: std.fs.Dir) !Config {
		const data = try home.readFileAlloc(mem, ".config/gradtemp/config.json", 1024);
		defer mem.free(data);
		const parsed = try std.json.parseFromSlice(Config, mem, data, .{});
		defer parsed.deinit();
		return parsed.value;
	}
};

const Slope = struct {
	time: Range(f32),
	scale: *const fn(*const Slope, f32) f32,
	m: f32,
	b: f32,

	fn Range(T: type) type { return struct {
		lo: T,
		hi: T,
	};}

	fn init(hour: Range(f32), kelvin: Range(u15), scale: Scale) Slope {
		const time: Range(f32) = .{
			.lo = hour.lo,
			.hi = if (hour.hi < hour.lo) hour.hi + 24 else hour.hi,
		};
		const run: f32 = time.hi - time.lo;
		if (run == 0) {
			return .{ .time = time, .scale = &lin, .m = 0, .b = @floatFromInt(kelvin.hi) };
		} else {
			const hi: f32 = @floatFromInt(kelvin.hi);
			const lo: f32 = @floatFromInt(kelvin.lo);
			return switch (scale) {
				.linear => .{
					.time = time, .scale = &lin, .b = lo, .m = (hi - lo) / run,
				},
				.logarithmic => .{
					.time = time, .scale = &log, .b = lo, .m = @log2(hi / lo) / run,
				},
			};
		}
	}

	fn at(self: *const Slope, hour: f32) u15 {
		const t = &self.time;
		const x: f32 = @min(if (hour < t.lo) hour + 24 else hour, t.hi) - t.lo;
		return @intFromFloat(@round(self.scale(self, x)));
	}

	fn lin(self: *const Slope, x: f32) f32 {
		return self.m * x + self.b;
	}

	fn log(self: *const Slope, x: f32) f32 {
		return @exp2(self.m * x) * self.b;
	}
};

pub fn init(mem: std.mem.Allocator, home: std.fs.Dir) Schedule {
	const cfg: Config = Config.init(mem, home) catch .{};
	return .{
		.dawn = .init(
			.{ .lo = cfg.dawn[0], .hi = cfg.dawn[1] },
			.{ .lo = cfg.night, .hi = cfg.day },
			cfg.scale,
		),
		.dusk = .init(
			.{ .lo = cfg.dusk[0], .hi = cfg.dusk[1] },
			.{ .lo = cfg.day, .hi = cfg.night },
			cfg.scale,
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
