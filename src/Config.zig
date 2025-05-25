const Config = @This();
const Slope = @import("Slope.zig");
const std = @import("std");

day: u15 = 6500,
night: u15 = 1900,
dawn: SlopeJson = .{ .start = 4, .end = 7, .scale = .grow },
dusk: SlopeJson = .{ .start = 18, .end = 21, .scale = .decay },

const SlopeJson = struct {
	start: f32,
	end: f32,
	scale: Slope.Scale,
};

inline fn tryInit(mem: std.mem.Allocator, home: std.fs.Dir) !Config {
	const data = try home.readFileAlloc(mem, ".config/gradtemp/config.json", 1024);
	defer mem.free(data);
	const parsed = std.json.parseFromSlice(Config, mem, data, .{}) catch |e| {
		std.debug.print("config.json: {s}\n", .{ @errorName(e) });
		return e;
	};
	defer parsed.deinit();
	return parsed.value;
}

pub fn init(mem: std.mem.Allocator, home: std.fs.Dir) Config {
	return tryInit(mem, home) catch .{};
}

pub fn getDawn(self: *const Config) Slope {
	return .init(
		.{ .lo = self.dawn.start, .hi = self.dawn.end },
		.{ .lo = self.night, .hi = self.day },
		self.dawn.scale,
	);
}

pub fn getDusk(self: *const Config) Slope {
	return .init(
		.{ .lo = self.dusk.start, .hi = self.dusk.end },
		.{ .lo = self.day, .hi = self.night },
		self.dusk.scale,
	);
}

/// one-off hour-to-kelvin converter. generates only one slope.
pub fn at(self: *const Config, hr: f32) u15 {
	const dawn = self.dawn.start;
	const dusk = self.dusk.start;
	if (dawn < dusk) {
		return if (dawn <= hr and hr < dusk)
			self.getDawn().at(hr)
		else
			self.getDusk().at(hr);
	} else {
		return if (dusk <= hr and hr < dawn)
			self.getDusk().at(hr)
		else
			self.getDawn().at(hr);
	}

}
