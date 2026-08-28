// keyboard_hook_plugin.cpp
// Win32 low-level keyboard hook - blocks Alt+Tab / Win / Alt+F4 etc.

#include "keyboard_hook_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>

static HHOOK g_keyboard_hook = NULL;
static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;

static LRESULT CALLBACK LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
  if (nCode == HC_ACTION && (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN)) {
    KBDLLHOOKSTRUCT* p = reinterpret_cast<KBDLLHOOKSTRUCT*>(lParam);
    if (p->vkCode == VK_TAB && (p->flags & LLKHF_ALTDOWN)) return 1;
    if (p->vkCode == VK_F4 && (p->flags & LLKHF_ALTDOWN)) return 1;
    if (p->vkCode == VK_ESCAPE && (p->flags & LLKHF_ALTDOWN)) return 1;
    if (p->vkCode == VK_LWIN || p->vkCode == VK_RWIN) return 1;
    if (p->vkCode == VK_ESCAPE && (GetKeyState(VK_CONTROL) & 0x8000)) return 1;
  }
  return CallNextHookEx(NULL, nCode, wParam, lParam);
}

void KeyboardHookPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  auto plugin_registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);

  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      plugin_registrar->messenger(), "slowlight/keyboard_hook",
      &flutter::StandardMethodCodec::GetInstance());

  g_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name().compare("enableLock") == 0) {
          if (g_keyboard_hook) {
            UnhookWindowsHookEx(g_keyboard_hook);
            g_keyboard_hook = NULL;
          }
          g_keyboard_hook = SetWindowsHookExW(
              WH_KEYBOARD_LL, LowLevelKeyboardProc,
              GetModuleHandleW(NULL), 0);
          if (g_keyboard_hook) {
            result->Success(flutter::EncodableValue(true));
          } else {
            result->Error("HOOK_FAILED", "Failed to install keyboard hook");
          }
        } else if (call.method_name().compare("disableLock") == 0) {
          if (g_keyboard_hook) {
            UnhookWindowsHookEx(g_keyboard_hook);
            g_keyboard_hook = NULL;
          }
          result->Success(flutter::EncodableValue(true));
        } else {
          result->NotImplemented();
        }
      });
}
