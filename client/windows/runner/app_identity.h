#ifndef RUNNER_APP_IDENTITY_H_
#define RUNNER_APP_IDENTITY_H_

#include <windows.h>

// Keep installed releases and local debug runs in separate namespaces.
#ifdef _DEBUG
inline constexpr wchar_t kSlowlightMainWindowProperty[] =
    L"z7ping.Slowlight.Debug.MainWindow";
#else
inline constexpr wchar_t kSlowlightMainWindowProperty[] =
    L"z7ping.Slowlight.MainWindow";
#endif
inline constexpr UINT kActivateSlowlightWindow = WM_APP + 1;

// Release builds use the stable AppUserModelID owned by the installer shortcut.
// Debug builds intentionally avoid the release process identity so `flutter run`
// cannot collide with an installed Slowlight shortcut.
bool ConfigureWindowsAppIdentity();

// Applies a window-level Shell identity and explicit relaunch icon resource.
// This gives the taskbar a deterministic icon source even when Explorer does not
// fall back to WM_SETICON/the executable resource as expected.
bool ConfigureWindowsWindowIdentity(HWND window);

#endif  // RUNNER_APP_IDENTITY_H_
