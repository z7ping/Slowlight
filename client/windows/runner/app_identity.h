#ifndef RUNNER_APP_IDENTITY_H_
#define RUNNER_APP_IDENTITY_H_

#include <windows.h>

// Release builds use the stable AppUserModelID owned by the installer shortcut.
// Debug builds intentionally avoid the release process identity so `flutter run`
// cannot collide with an installed Slowlight shortcut.
bool ConfigureWindowsAppIdentity();

// Applies a window-level Shell identity and explicit relaunch icon resource.
// This gives the taskbar a deterministic icon source even when Explorer does not
// fall back to WM_SETICON/the executable resource as expected.
bool ConfigureWindowsWindowIdentity(HWND window);

#endif  // RUNNER_APP_IDENTITY_H_
