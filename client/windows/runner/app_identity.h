#ifndef RUNNER_APP_IDENTITY_H_
#define RUNNER_APP_IDENTITY_H_

// Configures the process AppUserModelID and refreshes the matching Start Menu
// shortcut so Windows never resolves the taskbar icon through a stale binary.
// Returns false when either operation fails; startup may continue safely.
bool ConfigureWindowsAppIdentity();

#endif  // RUNNER_APP_IDENTITY_H_
