const Slope = @This();

time: Range(f32),
kelv: Range(f32),
scale: *const fn(*const Slope, f32) f32,
m: f32,

fn Range(T: type) type { return struct {
	lo: T,
	hi: T,
};}

pub const Scale = enum {
	linear,
	grow,
	decay,
};

pub fn init(hour: Range(f32), kelvin: Range(u15), scale: Scale) Slope {
	const time: Range(f32) = .{
		.lo = hour.lo,
		.hi = if (hour.hi < hour.lo) hour.hi + 24 else hour.hi,
	};
	const run: f32 = time.hi - time.lo;
	if (run == 0) {
		const k: f32 = @floatFromInt(kelvin.hi);
		return .{ .time = time, .kelv = .{ .lo = k, .hi = k }, .scale = &lin, .m = 0 };
	} else {
		const k: Range(f32) = .{
			.lo = @floatFromInt(kelvin.lo),
			.hi = @floatFromInt(kelvin.hi),
		};
		return switch (scale) {
			.linear => .{
				.time = time, .kelv = k, .scale = &lin, .m = (k.hi - k.lo) / run,
			},
			.grow => .{
				.time = time, .kelv = k, .scale = &grow, .m = @log2(k.hi / k.lo) / run,
			},
			.decay => .{
				.time = time, .kelv = k, .scale = &decay, .m = @log2(k.hi / k.lo) / run,
			}
		};
	}
}

pub fn at(self: *const Slope, hour: f32) u15 {
	const t = &self.time;
	const x: f32 = @min(if (hour < t.lo) hour + 24 else hour, t.hi) - t.lo;
	return @intFromFloat(@round(self.scale(self, x)));
}

fn lin(self: *const Slope, x: f32) f32 {
	return self.m * x + self.kelv.lo;
}

fn grow(self: *const Slope, x: f32) f32 {
	return @exp2(self.m * x) * self.kelv.lo;
}

fn decay(self: *const Slope, x: f32) f32 {
	const k = &self.kelv;
	return -@exp2(-self.m * x) * k.hi + k.lo + k.hi;
}
