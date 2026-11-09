// Owner-process diagnostic only. Documentation:
// https://learn.microsoft.com/windows/win32/api/dbghelp/nf-dbghelp-stackwalk64
// https://learn.microsoft.com/windows/win32/api/processthreadsapi/nf-processthreadsapi-getthreadcontext
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0600
#include <windows.h>
#include <tlhelp32.h>
#include <dbghelp.h>
#include <algorithm>
#include <atomic>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

namespace {
std::atomic<bool> cancelled{false};
BOOL WINAPI cancel_handler(DWORD) { cancelled = true; return TRUE; }
std::string utf8(const wchar_t *text) {
    if (!text) return {};
    const int size = WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
    std::string result(size > 0 ? size : 0, '\0');
    if (size) { WideCharToMultiByte(CP_UTF8, 0, text, -1, &result[0], size, nullptr, nullptr); result.pop_back(); }
    return result;
}
std::string quoted(const std::string &text) {
    std::string result = "\"";
    for (unsigned char c : text) {
        if (c == '\\' || c == '"') { result += '\\'; result += char(c); }
        else if (c < 32) result += ' ';
        else result += char(c);
    }
    return result + "\"";
}
std::string hex(uint64_t value) { std::ostringstream out; out << "0x" << std::hex << value; return out.str(); }
uint64_t filetime(FILETIME time) { return (uint64_t(time.dwHighDateTime) << 32) | time.dwLowDateTime; }
uint64_t cpu_time(DWORD id) {
    HANDLE thread = OpenThread(THREAD_QUERY_INFORMATION, FALSE, id);
    FILETIME created{}, exited{}, kernel{}, user{};
    const bool valid = thread && GetThreadTimes(thread, &created, &exited, &kernel, &user);
    if (thread) CloseHandle(thread);
    return valid ? filetime(kernel) + filetime(user) : 0;
}
std::vector<DWORD> thread_ids(DWORD pid) {
    std::vector<DWORD> result;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return result;
    THREADENTRY32 entry{}; entry.dwSize = sizeof(entry);
    if (Thread32First(snapshot, &entry)) do {
        if (entry.th32OwnerProcessID == pid) result.push_back(entry.th32ThreadID);
    } while (Thread32Next(snapshot, &entry));
    CloseHandle(snapshot); return result;
}
struct Thread {
    DWORD id = 0;
    HANDLE handle = nullptr;
    uint64_t cpu_delta = 0, samples = 0, suspend_errors = 0, context_errors = 0, walk_errors = 0;
    int priority = 0;
    std::string name;
    std::map<std::vector<uint64_t>, uint64_t> stacks;
};
struct Resume {
    HANDLE thread;
    bool suspended;
    explicit Resume(HANDLE value) : thread(value), suspended(SuspendThread(value) != DWORD(-1)) {}
    ~Resume() { if (suspended) ResumeThread(thread); }
};
void sample(HANDLE process, Thread &thread) {
    // All DbgHelp operations run on this one sampler thread. The RAII guard
    // balances our suspension on every return; target registers are read only.
    Resume guard(thread.handle);
    if (!guard.suspended) { ++thread.suspend_errors; return; }
    CONTEXT context{}; context.ContextFlags = CONTEXT_FULL;
    if (!GetThreadContext(thread.handle, &context)) { ++thread.context_errors; return; }
    STACKFRAME64 frame{};
    frame.AddrPC.Offset = context.Rip; frame.AddrPC.Mode = AddrModeFlat;
    frame.AddrStack.Offset = context.Rsp; frame.AddrStack.Mode = AddrModeFlat;
    frame.AddrFrame.Offset = context.Rbp; frame.AddrFrame.Mode = AddrModeFlat;
    std::vector<uint64_t> frames; frames.reserve(48); frames.push_back(context.Rip);
    uint64_t previous_pc = 0, previous_sp = 0;
    for (int depth = 0; depth < 47; ++depth) {
        if (!StackWalk64(IMAGE_FILE_MACHINE_AMD64, process, thread.handle, &frame, &context,
                nullptr, SymFunctionTableAccess64, SymGetModuleBase64, nullptr)) break;
        if (!frame.AddrPC.Offset || (frame.AddrPC.Offset == previous_pc && frame.AddrStack.Offset == previous_sp)) break;
        if (frame.AddrPC.Offset != frames.back() || depth > 0) frames.push_back(frame.AddrPC.Offset);
        previous_pc = frame.AddrPC.Offset; previous_sp = frame.AddrStack.Offset;
    }
    if (frames.size() < 2) ++thread.walk_errors;
    ++thread.stacks[frames]; ++thread.samples;
}
}

int main(int argc, char **argv) {
    if (argc < 5) { std::cerr << "pid duration_ms interval_ms output.json [top_threads]\n"; return 2; }
    const DWORD pid = DWORD(std::stoul(argv[1]));
    const int duration = std::stoi(argv[2]), interval = std::stoi(argv[3]);
    const int count = argc > 5 ? std::stoi(argv[5]) : 2;
    if (!pid || pid == GetCurrentProcessId() || duration < 1000 || duration > 60000 || interval < 5 || count < 1 || count > 4) return 2;
    HANDLE process = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ | SYNCHRONIZE, FALSE, pid);
    if (!process) { std::cerr << "OpenProcess " << GetLastError() << '\n'; return 3; }
    SetConsoleCtrlHandler(cancel_handler, TRUE);
    SymSetOptions(SYMOPT_DEFERRED_LOADS | SYMOPT_UNDNAME | SYMOPT_FAIL_CRITICAL_ERRORS | SYMOPT_NO_PROMPTS);
    if (!SymInitialize(process, "", TRUE)) { std::cerr << "SymInitialize " << GetLastError() << '\n'; CloseHandle(process); return 4; }
    std::map<DWORD, uint64_t> before;
    for (DWORD id : thread_ids(pid)) before[id] = cpu_time(id);
    Sleep(1500);
    std::vector<Thread> threads;
    using Description = HRESULT(WINAPI *)(HANDLE, PWSTR *);
    const auto description = reinterpret_cast<Description>(GetProcAddress(GetModuleHandleA("kernel32.dll"), "GetThreadDescription"));
    for (DWORD id : thread_ids(pid)) {
        const uint64_t current = cpu_time(id), previous = before[id];
        if (current <= previous) continue;
        Thread thread; thread.id = id; thread.cpu_delta = current - previous;
        thread.handle = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, id);
        if (!thread.handle) continue;
        thread.priority = GetThreadPriority(thread.handle);
        PWSTR text = nullptr;
        if (description && SUCCEEDED(description(thread.handle, &text))) { thread.name = utf8(text); LocalFree(text); }
        threads.push_back(std::move(thread));
    }
    std::sort(threads.begin(), threads.end(), [](const Thread &a, const Thread &b) { return a.cpu_delta > b.cpu_delta; });
    while (int(threads.size()) > count) { CloseHandle(threads.back().handle); threads.pop_back(); }
    if (threads.empty()) { SymCleanup(process); CloseHandle(process); return 5; }
    for (const auto &thread : threads) std::cout << "thread=" << thread.id << " cpu_ms=" << double(thread.cpu_delta) / 10000.0 << " name=" << thread.name << '\n';
    const ULONGLONG start = GetTickCount64();
    ULONGLONG next = start;
    while (!cancelled && GetTickCount64() - start < ULONGLONG(duration) && WaitForSingleObject(process, 0) == WAIT_TIMEOUT) {
        for (auto &thread : threads) sample(process, thread);
        next += interval;
        const ULONGLONG now = GetTickCount64();
        if (next > now) Sleep(DWORD(next - now)); else next = now;
    }
    std::ofstream out(argv[4], std::ios::binary);
    out << "{\"pid\":" << pid << ",\"elapsed_ms\":" << (GetTickCount64() - start) << ",\"interval_ms\":" << interval << ",\"modules\":[";
    HANDLE modules = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
    bool first = true;
    if (modules != INVALID_HANDLE_VALUE) {
        MODULEENTRY32W module{}; module.dwSize = sizeof(module);
        if (Module32FirstW(modules, &module)) do {
            if (!first) out << ','; first = false;
            out << "{\"name\":" << quoted(utf8(module.szModule)) << ",\"path\":" << quoted(utf8(module.szExePath))
                << ",\"base\":" << quoted(hex(uint64_t(module.modBaseAddr))) << ",\"size\":" << module.modBaseSize << '}';
        } while (Module32NextW(modules, &module));
        CloseHandle(modules);
    }
    out << "],\"threads\":["; first = true;
    for (auto &thread : threads) {
        if (!first) out << ','; first = false;
        out << "{\"id\":" << thread.id << ",\"name\":" << quoted(thread.name) << ",\"priority\":" << thread.priority
            << ",\"rank_cpu_ms\":" << double(thread.cpu_delta) / 10000.0 << ",\"samples\":" << thread.samples
            << ",\"suspend_errors\":" << thread.suspend_errors << ",\"context_errors\":" << thread.context_errors
            << ",\"walk_errors\":" << thread.walk_errors << ",\"stacks\":[";
        bool first_stack = true;
        for (const auto &entry : thread.stacks) {
            if (!first_stack) out << ','; first_stack = false;
            out << "{\"count\":" << entry.second << ",\"frames\":[";
            for (size_t i = 0; i < entry.first.size(); ++i) { if (i) out << ','; out << quoted(hex(entry.first[i])); }
            out << "]}";
        }
        out << "]}"; CloseHandle(thread.handle);
    }
    out << "]}\n";
    SymCleanup(process); CloseHandle(process);
    return out.good() ? 0 : 6;
}
