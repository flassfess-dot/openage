class_name RoRRenderingConfiguration
extends RefCounted

static func apply_window_presentation() -> void:
	# Keep enabled VSync during native window creation. The tested Windows
	# Release stalls when Mailbox is selected before swapchain initialization.
	# Applying it to the existing window preserves the fast presentation path.
	if DisplayServer.get_name() == "headless":
		return
	# Mailbox can render far beyond the display cadence. Once simulation runs
	# independently, keep that extra render/allocator work out of normal play.
	# An explicit engine cap remains authoritative; frame benchmarks can opt out.
	if Engine.max_fps == 0:
		Engine.max_fps = 60
	if RenderingServer.get_current_rendering_method() in ["mobile", "forward_plus"]:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX)
