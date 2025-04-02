const std = @import("std");

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	const exe_mod = b.createModule(.{
		.root_source_file = b.path("src/main.zig"),
		.target = target,
		.optimize = optimize,
		.link_libc = true,
	});
	const exe = b.addExecutable(.{
		.name = "gradtemp",
		.root_module = exe_mod,
	});
	b.installArtifact(exe);

	const run_cmd = b.addRunArtifact(exe);
	run_cmd.step.dependOn(b.getInstallStep());
	if (b.args) |args| {
		run_cmd.addArgs(args);
	}
	const run_step = b.step("run", "Run the main app");
	run_step.dependOn(&run_cmd.step);

	const tgl_mod = b.createModule(.{
		.root_source_file = b.path("src/toggle.zig"),
		.target = target,
		.optimize = optimize,
	});
	const tgl = b.addExecutable(.{
		.name = "toggle",
		.root_module = tgl_mod,
	});
	b.installArtifact(tgl);

	const run_tgl_cmd = b.addRunArtifact(tgl);
	run_tgl_cmd.step.dependOn(b.getInstallStep());
	const run_tgl_step = b.step("run_toggle", "Run the toggle app");
	run_tgl_step.dependOn(&run_tgl_cmd.step);
}
