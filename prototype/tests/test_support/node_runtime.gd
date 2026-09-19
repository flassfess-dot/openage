class_name RoRTestNodeRuntime
extends RefCounted


# Resolves the Node.js binary for the importer self-tests: PATH entries first,
# then the standard install location, then the repository-local portable
# toolchain under .tools/nodejs (gitignored; unpack a node-v*-win-x64.zip
# there). PATH is inspected without spawning a process so a missing runtime
# produces an actionable failure instead of a CreateProcess engine error.
# Returns an empty string when no runtime exists.
static func resolve() -> String:
	var executable := "node.exe" if OS.get_name() == "Windows" else "node"
	var path_separator := ";" if OS.get_name() == "Windows" else ":"
	for directory in OS.get_environment("PATH").split(path_separator, false):
		var candidate := String(directory).strip_edges().path_join(executable)
		if FileAccess.file_exists(candidate):
			return candidate
	var candidates := [
		ProjectSettings.globalize_path("res://../.tools/nodejs/node.exe"),
		"C:/Program Files/nodejs/node.exe",
	]
	for candidate in candidates:
		if FileAccess.file_exists(String(candidate)):
			return String(candidate)
	return ""


static func unavailable_message() -> String:
	return "Node.js not found: install Node.js, or unpack the portable win-x64 zip into .tools/nodejs so tools/ror_import self-tests can run"
