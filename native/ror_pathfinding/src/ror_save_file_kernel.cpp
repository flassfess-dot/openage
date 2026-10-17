#include "ror_save_file_kernel.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/global_constants.hpp>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#else
#include <cstdio>
#endif

namespace godot {
void RoRSaveFileKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("replace_atomic", "source", "destination"), &RoRSaveFileKernel::replace_atomic);
}

int64_t RoRSaveFileKernel::replace_atomic(const String &source, const String &destination) const {
    if (source.is_empty() || destination.is_empty() || source == destination || source.get_base_dir() != destination.get_base_dir()) return ERR_INVALID_PARAMETER;
#ifdef _WIN32
    const Char16String from = source.replace("/", "\\").utf16();
    const Char16String to = destination.replace("/", "\\").utf16();
    // A single OS operation preserves the old slot on failure and commits the
    // complete replacement without a missing-file gap.
    if (MoveFileExW(reinterpret_cast<LPCWSTR>(from.get_data()), reinterpret_cast<LPCWSTR>(to.get_data()), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) return OK;
    return GetLastError() == ERROR_FILE_NOT_FOUND ? ERR_FILE_NOT_FOUND : ERR_CANT_CREATE;
#else
    return std::rename(source.utf8().get_data(), destination.utf8().get_data()) == 0 ? OK : ERR_CANT_CREATE;
#endif
}
}