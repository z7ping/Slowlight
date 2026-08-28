// keyhook.cpp - Standalone DLL, no Flutter dependencies
// Registers WH_KEYBOARD_LL hook on a dedicated thread with its own message loop.
// Exposes 3 C functions for Dart FFI.

#include <windows.h>
#include <cstdint>

static HHOOK g_hook = NULL;
static HANDLE g_thread = NULL;
static DWORD g_thread_id = 0;
static volatile BOOL g_blocking = FALSE;
static HANDLE g_hook_ready = NULL;  // sync event: hook installed

// Keyboard hook callback - runs on the dedicated thread
static LRESULT CALLBACK LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
    if (nCode == HC_ACTION && (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN)) {
        KBDLLHOOKSTRUCT* p = reinterpret_cast<KBDLLHOOKSTRUCT*>(lParam);
        if (g_blocking) {
            // Alt+Tab
            if (p->vkCode == VK_TAB && (p->flags & LLKHF_ALTDOWN)) return 1;
            // Alt+F4
            if (p->vkCode == VK_F4 && (p->flags & LLKHF_ALTDOWN)) return 1;
            // Alt+Esc
            if (p->vkCode == VK_ESCAPE && (p->flags & LLKHF_ALTDOWN)) return 1;
            // Win key (left/right)
            if (p->vkCode == VK_LWIN || p->vkCode == VK_RWIN) return 1;
            // Ctrl+Esc (Start menu)
            if (p->vkCode == VK_ESCAPE && (GetKeyState(VK_CONTROL) & 0x8000)) return 1;
        }
    }
    return CallNextHookEx(NULL, nCode, wParam, lParam);
}

// Dedicated thread - own GetMessage loop
static DWORD WINAPI HookThreadProc(LPVOID lpParam) {
    g_hook = SetWindowsHookExW(WH_KEYBOARD_LL, LowLevelKeyboardProc, GetModuleHandleW(NULL), 0);

    // Signal caller: hook installed (or failed)
    if (g_hook_ready) SetEvent(g_hook_ready);

    if (!g_hook) return 1;

    // Message loop (blocks until WM_QUIT)
    MSG msg;
    while (GetMessage(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    // Cleanup
    if (g_hook) {
        UnhookWindowsHookEx(g_hook);
        g_hook = NULL;
    }
    return 0;
}

extern "C" {

__declspec(dllexport) int32_t keyhook_start() {
    if (g_thread) return 1;  // already running

    g_blocking = TRUE;
    g_hook_ready = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!g_hook_ready) return -1;

    g_thread = CreateThread(NULL, 0, HookThreadProc, NULL, 0, &g_thread_id);
    if (!g_thread) {
        CloseHandle(g_hook_ready);
        g_hook_ready = NULL;
        return -1;
    }

    // Wait for hook install (max 500ms)
    WaitForSingleObject(g_hook_ready, 500);
    CloseHandle(g_hook_ready);
    g_hook_ready = NULL;

    return g_hook ? 0 : -1;
}

__declspec(dllexport) void keyhook_stop() {
    if (g_thread) {
        g_blocking = FALSE;
        PostThreadMessage(g_thread_id, WM_QUIT, 0, 0);
        WaitForSingleObject(g_thread, 2000);
        CloseHandle(g_thread);
        g_thread = NULL;
        g_thread_id = 0;
        g_hook = NULL;
    }
}

__declspec(dllexport) void keyhook_set_block(int32_t enabled) {
    g_blocking = enabled ? TRUE : FALSE;
}

} // extern "C"
