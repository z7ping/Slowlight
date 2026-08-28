#include "app_identity.h"

#include <windows.h>
#include <shobjidl.h>

namespace {

constexpr wchar_t kAppUserModelId[] = L"Slowlight";

}  // namespace

bool ConfigureWindowsAppIdentity() {
#ifdef _DEBUG
  // `flutter run -d windows` uses a transient Debug executable path. Giving
  // that process the release AppUserModelID makes Explorer resolve its taskbar
  // representation through the installed/recent Start Menu shortcut, which can
  // point at a different or already-deleted executable. Let Windows use the
  // Debug executable identity and the icon embedded by Runner.rc instead.
  return true;
#else
  // Release builds use the same stable AppUserModelID that the installer writes
  // to the Start Menu shortcut. Shortcut ownership belongs to the installer;
  // the application must not rewrite it on every launch.
  return SUCCEEDED(
      ::SetCurrentProcessExplicitAppUserModelID(kAppUserModelId));
#endif
}
