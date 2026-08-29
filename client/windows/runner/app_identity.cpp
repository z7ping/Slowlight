#include "app_identity.h"

#include <shobjidl.h>
#include <windows.h>

#include <string>

#ifdef _DEBUG
#include <propkey.h>
#include <propvarutil.h>
#include <propsys.h>
#endif

namespace {

constexpr wchar_t kAppUserModelId[] = L"Slowlight";

#ifdef _DEBUG
constexpr wchar_t kDebugAppUserModelId[] = L"Slowlight.Debug";
constexpr wchar_t kAppIconResourceSuffix[] = L",-101";

bool SetStringProperty(IPropertyStore* store,
                       REFPROPERTYKEY key,
                       const std::wstring& value) {
  PROPVARIANT property{};
  const HRESULT init_result =
      ::InitPropVariantFromString(value.c_str(), &property);
  if (FAILED(init_result)) {
    return false;
  }

  const HRESULT set_result = store->SetValue(key, property);
  ::PropVariantClear(&property);
  return SUCCEEDED(set_result);
}

std::wstring ExecutableIconResource() {
  wchar_t executable[MAX_PATH] = {};
  const DWORD length =
      ::GetModuleFileNameW(nullptr, executable, static_cast<DWORD>(_countof(executable)));
  if (length == 0 || length >= _countof(executable)) {
    return {};
  }

  std::wstring icon_resource(executable, length);
  icon_resource.append(kAppIconResourceSuffix);
  return icon_resource;
}
#endif

}  // namespace

bool ConfigureWindowsAppIdentity() {
#ifdef _DEBUG
  // Debug uses a window-level identity so flutter run never groups with an
  // installed Slowlight release shortcut.
  return true;
#else
  // Release uses one stable process identity matching the Start Menu shortcut
  // created by the installer. The shortcut owns the display name, relaunch
  // target, and icon used by the Windows taskbar.
  return SUCCEEDED(
      ::SetCurrentProcessExplicitAppUserModelID(kAppUserModelId));
#endif
}

bool ConfigureWindowsWindowIdentity(HWND window) {
  if (window == nullptr) {
    return false;
  }

#ifndef _DEBUG
  // Do not set release window-level AppUserModel properties here. Windows
  // should resolve the matching installer-owned shortcut for taskbar identity
  // instead of mixing shortcut metadata with Relaunch* window properties.
  return true;
#else
  IPropertyStore* store = nullptr;
  const HRESULT store_result =
      ::SHGetPropertyStoreForWindow(window, IID_PPV_ARGS(&store));
  if (FAILED(store_result) || store == nullptr) {
    ::OutputDebugStringW(
        L"Slowlight: failed to acquire taskbar window property store.\n");
    return false;
  }

  const std::wstring icon_resource = ExecutableIconResource();
  const bool id_set = SetStringProperty(
      store, PKEY_AppUserModel_ID, std::wstring(kDebugAppUserModelId));
  const bool icon_set = !icon_resource.empty() &&
                        SetStringProperty(store,
                                          PKEY_AppUserModel_RelaunchIconResource,
                                          icon_resource);

  store->Release();

  if (!id_set) {
    ::OutputDebugStringW(
        L"Slowlight: failed to set debug taskbar window AppUserModelID.\n");
  }
  if (!icon_set) {
    ::OutputDebugStringW(
        L"Slowlight: failed to set debug taskbar relaunch icon resource.\n");
  }
  return id_set && icon_set;
#endif
}
