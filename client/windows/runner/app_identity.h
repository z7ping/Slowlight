#ifndef RUNNER_APP_IDENTITY_H_
#define RUNNER_APP_IDENTITY_H_

// Release builds use the stable AppUserModelID owned by the installer shortcut.
// Debug builds intentionally keep the shell-assigned executable identity so
// `flutter run -d windows` cannot be hijacked by a stale installed shortcut.
bool ConfigureWindowsAppIdentity();

#endif  // RUNNER_APP_IDENTITY_H_
