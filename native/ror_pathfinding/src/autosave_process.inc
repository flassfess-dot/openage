namespace godot {
namespace {
String background_quote_argument(const String &value) {
    String result = "\"";
    int64_t slashes = 0;
    for (int64_t i = 0; i < value.length(); ++i) {
        const char32_t current = value[i];
        if (current == '\\') { ++slashes; continue; }
        if (current == '"') {
            result += String("\\").repeat(slashes * 2 + 1) + "\"";
        } else {
            result += String("\\").repeat(slashes) + String::chr(current);
        }
        slashes = 0;
    }
    return result + String("\\").repeat(slashes * 2) + "\"";
}
}

RoRSaveFileKernel::~RoRSaveFileKernel() { stop_background_process(); }

bool RoRSaveFileKernel::background_process_supported() const {
#ifdef _WIN32
    return true;
#else
    return false;
#endif
}

bool RoRSaveFileKernel::background_process_running() const {
#ifdef _WIN32
    return background_process && WaitForSingleObject(static_cast<HANDLE>(background_process), 0) == WAIT_TIMEOUT;
#else
    return false;
#endif
}

void RoRSaveFileKernel::stop_background_process() {
#ifdef _WIN32
    // This handle was created and retained by this object. No PID lookup can
    // accidentally target an unrelated process after Windows reuses an ID.
    if (background_job) {
        TerminateJobObject(static_cast<HANDLE>(background_job), 0);
        CloseHandle(static_cast<HANDLE>(background_job));
        background_job = nullptr;
    }
    if (background_process) {
        WaitForSingleObject(static_cast<HANDLE>(background_process), 5000);
        CloseHandle(static_cast<HANDLE>(background_process));
        background_process = nullptr;
    }
#endif
}

Dictionary RoRSaveFileKernel::start_background_process(const String &application, const Array &arguments) {
    Dictionary result;
    result["error"] = int64_t(ERR_UNAVAILABLE);
#ifdef _WIN32
    if (background_process_running()) { result["error"] = int64_t(ERR_BUSY); return result; }
    stop_background_process();
    // The game only launches its own executable, in headless worker mode.
    if (application.replace("\\", "/").to_lower() != OS::get_singleton()->get_executable_path().replace("\\", "/").to_lower() || arguments.size() > 32) {
        result["error"] = int64_t(ERR_INVALID_PARAMETER); return result;
    }
    String command = background_quote_argument(application);
    for (int64_t i = 0; i < arguments.size(); ++i) {
        if (arguments[i].get_type() != Variant::STRING) { result["error"] = int64_t(ERR_INVALID_PARAMETER); return result; }
        command += " " + background_quote_argument(arguments[i]);
    }
    const Char16String app = application.utf16(), cmd = command.utf16(), cwd = application.get_base_dir().utf16();
    if (cmd.length() >= 32767) { result["error"] = int64_t(ERR_INVALID_PARAMETER); return result; }
    std::vector<wchar_t> writable(cmd.length() + 1);
    std::memcpy(writable.data(), cmd.get_data(), (cmd.length() + 1) * sizeof(wchar_t));
    HANDLE job = CreateJobObjectW(nullptr, nullptr);
    if (!job) { result["os_error"] = int64_t(GetLastError()); return result; }
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) {
        result["os_error"] = int64_t(GetLastError()); CloseHandle(job); return result;
    }
    STARTUPINFOW startup = {};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION process = {};
    const DWORD flags = CREATE_NO_WINDOW | CREATE_SUSPENDED | BELOW_NORMAL_PRIORITY_CLASS;
    if (!CreateProcessW(reinterpret_cast<LPCWSTR>(app.get_data()), writable.data(), nullptr, nullptr, FALSE, flags, nullptr, reinterpret_cast<LPCWSTR>(cwd.get_data()), &startup, &process)) {
        result["os_error"] = int64_t(GetLastError()); CloseHandle(job); return result;
    }
    // A private job also kills the helper if the game crashes or exits before
    // its normal shutdown. Suspend until ownership is established.
    if (!AssignProcessToJobObject(job, process.hProcess)) {
        result["os_error"] = int64_t(GetLastError());
        TerminateProcess(process.hProcess, 1);
        CloseHandle(process.hThread); CloseHandle(process.hProcess); CloseHandle(job);
        return result;
    }
    background_process = process.hProcess;
    background_job = job;
    if (ResumeThread(process.hThread) == DWORD(-1)) {
        result["os_error"] = int64_t(GetLastError()); CloseHandle(process.hThread); stop_background_process(); return result;
    }
    CloseHandle(process.hThread);
    result["error"] = int64_t(OK);
    result["pid"] = int64_t(process.dwProcessId);
#endif
    return result;
}
}
