#include "app_identity.h"

#include <propkey.h>
#include <propvarutil.h>
#include <propsys.h>
#include <shobjidl.h>
#include <windows.h>

#include <string>

namespace {

constexpr wchar_t kAppUserModelId[] = L"Slowlight";
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

}  // namespace

bool ConfigureWindowsAppIdentity() {
#ifdef _DEBUG
  // Debug keeps a separate taskbar identity at the window level. Do not assign
  // the release process AppUserModelID, otherwise Explorer may resolve an
  // installed/recent release shortcut that points at another executable.
  return true;
#else
  // Release builds use the same stable AppUserModelID that the installer writes
  // to the Start Menu shortcut. Shortcut ownership belongs to the installer;
  // the application must not rewrite it on every launch.
  return SUCCEEDED(
      ::SetCurrentProcessExplicitAppUserModelID(kAppUserModelId));
#endif
}

bool ConfigureWindowsWindowIdentity(HWND window) {
  if (window == nullptr) {
    return false;
  }

  IPropertyStore* store = nullptr;
  const HRESULT store_result =
      ::SHGetPropertyStoreForWindow(window, IID_PPV_ARGS(&store));
  if (FAILED(store_result) || store == nullptr) {
    ::OutputDebugStringW(
        L"Slowlight: failed to acquire taskbar window property store.\n");
    return false;
  }

#ifdef _DEBUG
  const wchar_t* app_user_model_id = kDebugAppUserModelId;
#else
  const wchar_t* app_user_model_id = kAppUserModelId;
#endif

  const std::wstring icon_resource = ExecutableIconResource();
  const bool id_set = SetStringProperty(
      store, PKEY_AppUserModel_ID, std::wstring(app_user_model_id));
  const bool icon_set = !icon_resource.empty() &&
                        SetStringProperty(store,
                                          PKEY_AppUserModel_RelaunchIconResource,
                                          icon_resource);

  store->Release();

  if (!id_set) {
    ::OutputDebugStringW(
        L"Slowlight: failed to set taskbar window AppUserModelID.\n");
  }
  if (!icon_set) {
    ::OutputDebugStringW(
        L"Slowlight: failed to set taskbar relaunch icon resource.\n");
  }
  return id_set && icon_set;
}
