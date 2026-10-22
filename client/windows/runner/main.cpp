#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <cwchar>
#include <string>

#include "app_identity.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

// URL return only wakes the app; credentials remain in the existing OAuth poll.
struct ExistingWindowSearch {
  std::wstring executable_path;
  HWND window = nullptr;
};

BOOL CALLBACK FindExistingAppWindow(HWND hwnd, LPARAM context) {
  auto* search = reinterpret_cast<ExistingWindowSearch*>(context);
  wchar_t window_class[64] = {};
  if (::GetClassNameW(hwnd, window_class, _countof(window_class)) == 0 ||
      std::wcscmp(window_class, L"FLUTTER_RUNNER_WIN32_WINDOW") != 0) {
    return TRUE;
  }

  DWORD process_id = 0;
  ::GetWindowThreadProcessId(hwnd, &process_id);
  if (process_id == 0 || process_id == ::GetCurrentProcessId()) {
    return TRUE;
  }
  HANDLE process = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                                 process_id);
  if (process == nullptr) {
    return TRUE;
  }
  wchar_t process_path[MAX_PATH] = {};
  DWORD path_length = _countof(process_path);
  const bool same_executable =
      ::QueryFullProcessImageNameW(process, 0, process_path, &path_length) &&
      _wcsicmp(process_path, search->executable_path.c_str()) == 0;
  ::CloseHandle(process);
  if (!same_executable) {
    return TRUE;
  }

  search->window = hwnd;
  return FALSE;
}

HWND FindRunningSlowlightWindow() {
  wchar_t self_path[MAX_PATH] = {};
  const DWORD length = ::GetModuleFileNameW(nullptr, self_path,
                                            _countof(self_path));
  if (length == 0 || length >= _countof(self_path)) {
    return nullptr;
  }
  ExistingWindowSearch search{self_path, nullptr};
  ::EnumWindows(FindExistingAppWindow, reinterpret_cast<LPARAM>(&search));
  return search.window;
}

bool EnvironmentVariableEquals(const wchar_t* name, const wchar_t* expected) {
  wchar_t value[32] = {};
  const DWORD length = ::GetEnvironmentVariableW(name, value, 32);
  return length > 0 && length < 32 && std::wcscmp(value, expected) == 0;
}

int ReadEngineSwitchCount() {
  wchar_t value[16] = {};
  const DWORD length =
      ::GetEnvironmentVariableW(L"FLUTTER_ENGINE_SWITCHES", value, 16);
  if (length == 0 || length >= 16) {
    return 0;
  }

  wchar_t* end = nullptr;
  const long count = std::wcstol(value, &end, 10);
  if (end == value || *end != L'\0' || count < 0 || count >= 100) {
    return 0;
  }
  return static_cast<int>(count);
}

bool HasSoftwareRenderingSwitch(int switch_count) {
  for (int index = 1; index <= switch_count; ++index) {
    wchar_t name[64] = {};
    swprintf_s(name, _countof(name), L"FLUTTER_ENGINE_SWITCH_%d", index);
    if (EnvironmentVariableEquals(name, L"enable-software-rendering=true")) {
      return true;
    }
  }
  return false;
}

void ConfigureRenderingMode() {
  if (EnvironmentVariableEquals(L"SLOWLIGHT_HARDWARE_RENDERING", L"1")) {
    return;
  }
  const int existing_switch_count = ReadEngineSwitchCount();
  if (HasSoftwareRenderingSwitch(existing_switch_count)) {
    return;
  }

  const int software_switch_index = existing_switch_count + 1;
  wchar_t switch_count[16] = {};
  wchar_t switch_name[64] = {};
  swprintf_s(switch_count, _countof(switch_count), L"%d",
             software_switch_index);
  swprintf_s(switch_name, _countof(switch_name),
             L"FLUTTER_ENGINE_SWITCH_%d", software_switch_index);
  ::SetEnvironmentVariableW(L"FLUTTER_ENGINE_SWITCHES", switch_count);
  ::SetEnvironmentVariableW(switch_name,
                            L"enable-software-rendering=true");
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  if (command_line_arguments.size() == 1 &&
      command_line_arguments.front() == "slowlight://oauth-complete") {
    // A second protocol invocation only brings the running tray/main window
    // to the front instead of creating an independent Flutter instance.
    const HWND existing_window = FindRunningSlowlightWindow();
    if (existing_window != nullptr) {
      ::ShowWindowAsync(existing_window,
                        ::IsIconic(existing_window) ? SW_RESTORE : SW_SHOW);
      ::SetForegroundWindow(existing_window);
      ::CoUninitialize();
      return EXIT_SUCCESS;
    }
    // If no instance is running, launch normally; return alone is not login.
  }

  ConfigureWindowsAppIdentity();

  ConfigureRenderingMode();
  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"\u6240\u884C\u6620\u6211 \u00B7 Slowlight", origin, size)) {
    return EXIT_FAILURE;
  }
  if (!ConfigureWindowsWindowIdentity(window.GetHandle())) {
    ::OutputDebugStringW(
        L"Slowlight: taskbar window identity configuration failed.\n");
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
