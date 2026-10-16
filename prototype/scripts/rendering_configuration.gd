class_name RoRRenderingConfiguration
extends RefCounted

static func apply_window_presentation() -> void:
	# Keep enabled VSync during native window creation. The tested Windows
	# Release stalls when Mailbox is selected before swapchain initialization.
	# Applying it to the existing window preserves the fast presentation path.
	if DisplayServer.get_name() == "headless":
		return
	if RenderingServer.get_current_rendering_method() in ["mobile", "forward_plus"]:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX)
