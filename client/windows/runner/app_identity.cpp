#include "app_identity.h"

#include <windows.h>

#include <filesystem>
#include <string>

#include <propkey.h>
#include <propvarutil.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

namespace {

constexpr wchar_t kAppUserModelId[] = L"Slowlight";
constexpr wchar_t kDisplayName[] = L"\u6240\u884C\u6620\u6211";
constexpr wchar_t kDisplayDescription[] =
    L"\u6240\u884C\u6620\u6211 \u00B7 Slowlight";

using Microsoft::WRL::ComPtr;

std::wstring CurrentExecutablePath() {
  std::wstring path(32768, L'\0');
  const DWORD length = ::GetModuleFileNameW(
      nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (length == 0 || length >= static_cast<DWORD>(path.size())) {
    return L"";
  }
  path.resize(length);
  return path;
}

HRESULT RefreshStartMenuShortcut() {
  const std::wstring executable = CurrentExecutablePath();
  if (executable.empty()) {
    return HRESULT_FROM_WIN32(::GetLastError());
  }

  PWSTR programs_directory = nullptr;
  HRESULT result = ::SHGetKnownFolderPath(FOLDERID_Programs, KF_FLAG_DEFAULT,
                                          nullptr, &programs_directory);
  if (FAILED(result)) {
    return result;
  }

  const std::filesystem::path programs_path(programs_directory);
  const std::filesystem::path executable_path(executable);
  const std::filesystem::path shortcut_path =
      programs_path / (std::wstring(kDisplayName) + L".lnk");
  ::CoTaskMemFree(programs_directory);

  ComPtr<IShellLinkW> shell_link;
  result = ::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(&shell_link));
  if (FAILED(result)) {
    return result;
  }

  result = shell_link->SetPath(executable.c_str());
  if (SUCCEEDED(result)) {
    result = shell_link->SetArguments(L"");
  }
  if (SUCCEEDED(result)) {
    result = shell_link->SetWorkingDirectory(
        executable_path.parent_path().c_str());
  }
  if (SUCCEEDED(result)) {
    result = shell_link->SetIconLocation(executable.c_str(), 0);
  }
  if (SUCCEEDED(result)) {
    result = shell_link->SetDescription(kDisplayDescription);
  }
  if (FAILED(result)) {
    return result;
  }

  ComPtr<IPropertyStore> property_store;
  result = shell_link.As(&property_store);
  if (FAILED(result)) {
    return result;
  }

  PROPVARIANT app_id;
  ::PropVariantInit(&app_id);
  result = ::InitPropVariantFromString(kAppUserModelId, &app_id);
  if (SUCCEEDED(result)) {
    result = property_store->SetValue(PKEY_AppUserModel_ID, app_id);
  }
  if (SUCCEEDED(result)) {
    result = property_store->Commit();
  }
  ::PropVariantClear(&app_id);
  if (FAILED(result)) {
    return result;
  }

  ComPtr<IPersistFile> persist_file;
  result = shell_link.As(&persist_file);
  if (FAILED(result)) {
    return result;
  }
  return persist_file->Save(shortcut_path.c_str(), TRUE);
}

void TraceFailure(const wchar_t* operation, HRESULT result) {
  if (SUCCEEDED(result)) {
    return;
  }
  wchar_t message[160] = {};
  swprintf_s(message, L"Slowlight %s failed: 0x%08X\n", operation,
             static_cast<unsigned int>(result));
  ::OutputDebugStringW(message);
}

}  // namespace

bool ConfigureWindowsAppIdentity() {
  const HRESULT shortcut_result = RefreshStartMenuShortcut();
  const HRESULT identity_result =
      ::SetCurrentProcessExplicitAppUserModelID(kAppUserModelId);
  TraceFailure(L"shortcut refresh", shortcut_result);
  TraceFailure(L"AppUserModelID registration", identity_result);
  return SUCCEEDED(shortcut_result) && SUCCEEDED(identity_result);
}
