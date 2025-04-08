const Schedule = @This();
const std = @import("std");

dawn: Slope,
dusk: Slope,

const Scale = enum {
	linear,
	grow,
	decay,
};

const Config = struct {
	day: u15 = 6500,
	night: u15 = 1900,
	dawn: SlopeConfig = .{ .start = 4, .end = 6, .scale = .grow },
	dusk: SlopeConfig = .{ .start = 19, .end = 21, .scale = .decay },

	const SlopeConfig = struct {
		start: f32,
		end: f32,
		scale: Scale,
	};

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
	k: Range(f32),
	scale: *const fn(*const Slope, f32) f32,
	m: f32,

	fn Range(T: type) type { return struct {
		lo: T,
		hi: T,
	};}

	fn init(hour: Range(f32), kelvin: Range(u15), scale: Scale) Slope {
		const time: Range(f32) = .{
			.lo = hour.lo,
			.hi = if (hour.hi < hour.lo) hour.hi + 24 else hour.hi,
		};
		const k: Range(f32) = .{
			.lo = @floatFromInt(kelvin.lo),
			.hi = @floatFromInt(kelvin.hi),
		};
		const run: f32 = time.hi - time.lo;
		if (run == 0) {
			return .{ .time = time, .k = k, .scale = &lin, .m = 0 };
		} else {
			return switch (scale) {
				.linear => .{
					.time = time, .k = k, .scale = &lin, .m = (k.hi - k.lo) / run,
				},
				.grow => .{
					.time = time, .k = k, .scale = &grow, .m = @log2(k.hi / k.lo) / run,
				},
				.decay => .{
					.time = time, .k = k, .scale = &decay, .m = @log2(k.hi / k.lo) / run,
				}
			};
		}
	}

	fn at(self: *const Slope, hour: f32) u15 {
		const t = &self.time;
		const x: f32 = @min(if (hour < t.lo) hour + 24 else hour, t.hi) - t.lo;
		return @intFromFloat(@round(self.scale(self, x)));
	}

	fn lin(self: *const Slope, x: f32) f32 {
		return self.m * x + self.k.lo;
	}

	fn grow(self: *const Slope, x: f32) f32 {
		return @exp2(self.m * x) * self.k.lo;
	}

	fn decay(self: *const Slope, x: f32) f32 {
		return -@exp2(-self.m * x) * self.k.hi + self.k.lo + self.k.hi;
	}
};

pub fn init(mem: std.mem.Allocator, home: std.fs.Dir) Schedule {
	const cfg: Config = Config.init(mem, home) catch |e| blk: {
		std.debug.print("config.json: {s}\n", .{ @errorName(e) });
		break :blk .{};
	};
	return .{
		.dawn = .init(
			.{ .lo = cfg.dawn.start, .hi = cfg.dawn.end },
			.{ .lo = cfg.night, .hi = cfg.day },
			cfg.dawn.scale,
		),
		.dusk = .init(
			.{ .lo = cfg.dusk.start, .hi = cfg.dusk.end },
			.{ .lo = cfg.day, .hi = cfg.night },
			cfg.dusk.scale,
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
