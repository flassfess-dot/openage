#include "ror_save_file_kernel.hpp"
#include "ror_journal_version_reader.hpp"
#include <godot_cpp/variant/variant_internal.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/global_constants.hpp>
#include <godot_cpp/classes/os.hpp>
#include <vector>
#include <cstring>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#else
#include <cstdio>
#include <unistd.h>
#endif

namespace godot {
void RoRSaveFileKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("capture_resource_changes", "rows", "versions", "base_revision"), &RoRSaveFileKernel::capture_resource_changes);
    ClassDB::bind_method(D_METHOD("background_process_supported"), &RoRSaveFileKernel::background_process_supported);
    ClassDB::bind_method(D_METHOD("start_background_process", "application", "arguments"), &RoRSaveFileKernel::start_background_process);
    ClassDB::bind_method(D_METHOD("background_process_running"), &RoRSaveFileKernel::background_process_running);
    ClassDB::bind_method(D_METHOD("stop_background_process"), &RoRSaveFileKernel::stop_background_process);
    ClassDB::bind_method(D_METHOD("replace_atomic", "source", "destination"), &RoRSaveFileKernel::replace_atomic);
    ClassDB::bind_method(D_METHOD("link_for_backup", "source", "destination"), &RoRSaveFileKernel::link_for_backup);
}

Dictionary RoRSaveFileKernel::capture_resource_changes(const Array &rows, const Variant &versions, int64_t base_revision) const {
    static const Variant id_key("id");
    RoRJournalVersionReader journal(versions);
    PackedInt64Array order;
    order.resize(rows.size());
    int64_t *ids = order.ptrw();
    Dictionary changed;
    // The simulation owner holds the array for this whole synchronous call.
    // Borrow each row only until it has been read or detached.
    const auto *entities = rows.is_empty() ? nullptr : reinterpret_cast<const Variant *>(
        gdextension_interface::array_operator_index_const(rows._native_ptr(), 0));
    for (int64_t index = 0; index < rows.size(); ++index) {
        if (entities[index].get_type() != Variant::DICTIONARY) return Dictionary();
        const Dictionary &row = *VariantInternal::get_dictionary(&entities[index]);
        if (!row.has(id_key)) return Dictionary();
        const auto *value = reinterpret_cast<const Variant *>(
            gdextension_interface::dictionary_operator_index_const(row._native_ptr(), id_key._native_ptr()));
        if (!value || value->get_type() != Variant::INT) return Dictionary();
        const int64_t id = *VariantInternal::get_int(value);
        if (id < 0) return Dictionary();
        ids[index] = id;
        int64_t revision = -1;
        if (base_revision < 0 || !journal.maximum(id, revision) || revision < 0 || revision > base_revision)
            changed[id] = row.duplicate(true);
    }
    Dictionary result;
    result["ids"] = order;
    result["changed"] = changed;
    return result;
}

bool RoRSaveFileKernel::link_for_backup(const String &source, const String &destination) const {
    if (source.get_base_dir() != destination.get_base_dir()) return false;
#ifdef _WIN32
    const Char16String from = source.replace("/", "\\").utf16();
    const Char16String to = destination.replace("/", "\\").utf16();
    return CreateHardLinkW(reinterpret_cast<LPCWSTR>(to.get_data()), reinterpret_cast<LPCWSTR>(from.get_data()), nullptr) != 0;
#else
    return link(source.utf8().get_data(), destination.utf8().get_data()) == 0;
#endif
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
#include "autosave_process.inc"
