// lock_overlay.cpp
// Standalone DLL for fullscreen lock overlay on ALL monitors.
// Primary monitor: black bg + countdown + clickable buttons (skip/postpone).
// Secondary monitors: black bg + countdown only (same as before).
// No Flutter dependencies - pure Win32 API.
// Exports C functions for Dart FFI.

#include <windows.h>
#include <cstdint>
#include <vector>
#include <thread>
#include <atomic>
#include <mutex>

static const wchar_t* OVERLAY_CLASS_NAME = L"SlowlightLockOverlay";

static std::vector<HWND> g_overlay_windows;
static std::mutex g_windows_mutex;
static std::thread g_overlay_thread;
static std::atomic<bool> g_running{false};
static std::atomic<int32_t> g_remaining_seconds{0};
static std::atomic<int32_t> g_pending_action{0};  // 0=none, 1=skip, 2=postpone
static std::atomic<bool> g_strict{false};
static std::atomic<bool> g_allow_postpone{true};
// 0 = creating windows, 1 = every monitor covered, -1 = unavailable.
static std::atomic<int32_t> g_startup_status{0};
static std::atomic<int32_t> g_btn_hover{0};       // 0=none, 1=postpone, 2=skip
static std::atomic<int32_t> g_btn_pressed{0};     // 0=none, 1=postpone, 2=skip

#define TIMER_ID 1
#define PRESS_TIMER_ID 2
#define BTN_WIDTH 130
#define BTN_HEIGHT 44
#define BTN_GAP 24

// Colors (matching Flutter RestOverlay)
static const int C_WHITE     = RGB(255, 255, 255);
static const int C_WHITE70   = RGB(178, 178, 178);  // Colors.white70
static const int C_WHITE54   = RGB(138, 138, 138);  // Colors.white54
static const int C_WHITE38   = RGB( 97,  97,  97);  // Colors.white38
static const int C_HOVER_BG  = RGB( 28,  28,  28);
static const int C_PRESS_BG  = RGB( 45,  45,  45);
static const int C_PRESS_BDR = RGB( 80,  80,  80);

static const wchar_t* TXT_TITLE   = L"\x4F11\x606F\x4E00\x4E0B";
static const wchar_t* TXT_TIP     = L"\x770B\x770B\x8FDC\x5904\xFF0C\x8BA9\x773C\x775B\x4F11\x606F\x4E00\x4E0B";
static const wchar_t* TXT_POSTPONE= L"\x5EF6\x540E 5 \x5206\x949F";
static const wchar_t* TXT_SKIP    = L"\x8DF3\x8FC7";
static const wchar_t* TXT_STRICT  = L"\x4E25\x683C\x6A21\x5F0F";  // 严格模式

static void FormatTime(int32_t totalSec, wchar_t* buf, int bufSize) {
    if (totalSec < 0) totalSec = 0;
    int m = totalSec / 60;
    int s = totalSec % 60;
    wsprintfW(buf, L"%02d:%02d", m, s);
}

static void InvalidateAll() {
    // Countdown updates arrive on Dart's thread during window creation or
    // teardown; never iterate the native window vector concurrently.
    std::lock_guard<std::mutex> guard(g_windows_mutex);
    for (HWND h : g_overlay_windows) InvalidateRect(h, NULL, FALSE);
}

static void DrawButton(HDC hdc, RECT& r, const wchar_t* text,
                        bool hovered, bool pressed,
                        int normalColor, int hoverColor) {
    if (pressed) {
        HBRUSH hFill = CreateSolidBrush(C_PRESS_BG);
        FillRect(hdc, &r, hFill);
        DeleteObject(hFill);
        HBRUSH hBorder = CreateSolidBrush(C_PRESS_BDR);
        FrameRect(hdc, &r, hBorder);
        DeleteObject(hBorder);
        SetTextColor(hdc, RGB(180, 180, 180));
    } else if (hovered) {
        HBRUSH hFill = CreateSolidBrush(C_HOVER_BG);
        FillRect(hdc, &r, hFill);
        DeleteObject(hFill);
        SetTextColor(hdc, hoverColor);
    } else {
        SetTextColor(hdc, normalColor);
    }
    DrawTextW(hdc, text, -1, &r, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
}

static int HitTestButton(HWND hwnd, int x, int y) {
    RECT rc;
    GetClientRect(hwnd, &rc);
    const bool postpone = g_allow_postpone.load();
    const bool skip = !g_strict.load();
    if (!postpone && !skip) return 0;
    const int btnY = rc.bottom * 75 / 100;
    const int totalW = postpone && skip ? BTN_WIDTH * 2 + BTN_GAP : BTN_WIDTH;
    const int leftX = (rc.right - totalW) / 2;
    const int rightX = postpone ? leftX + BTN_WIDTH + BTN_GAP : leftX;
    if (y < btnY || y > btnY + BTN_HEIGHT) return 0;
    if (postpone && x >= leftX && x <= leftX + BTN_WIDTH) return 1;
    if (skip && x >= rightX && x <= rightX + BTN_WIDTH) return 2;
    return 0;
}

static bool IsPrimaryMonitor(HWND hwnd) {
    MONITORINFO mi;
    mi.cbSize = sizeof(mi);
    HMONITOR hMon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    GetMonitorInfoW(hMon, &mi);
    return (mi.dwFlags & MONITORINFOF_PRIMARY) != 0;
}

static LRESULT CALLBACK OverlayWndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_PAINT: {
            PAINTSTRUCT ps;
            HDC hdc = BeginPaint(hwnd, &ps);
            RECT rc;
            GetClientRect(hwnd, &rc);

            HBRUSH brush = CreateSolidBrush(RGB(0, 0, 0));
            FillRect(hdc, &rc, brush);
            DeleteObject(brush);

            SetBkMode(hdc, TRANSPARENT);

            HFONT hTitle    = CreateFontW(-22, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Microsoft YaHei");
            HFONT hTime     = CreateFontW(-50, 0, 0, 0, FW_LIGHT,  FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Microsoft YaHei");
            HFONT hTip      = CreateFontW(-14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Microsoft YaHei");
            HFONT hBtn      = CreateFontW(-16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Microsoft YaHei");

            int cy = rc.bottom / 2;
            int hh = rc.bottom;

            // ---- Title (centered at ~32%) ----
            {
                RECT r = {0, hh * 26 / 100, rc.right, hh * 33 / 100};
                SelectObject(hdc, hTitle);
                SetTextColor(hdc, C_WHITE70);
                DrawTextW(hdc, TXT_TITLE, -1, &r, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
            }

            // ---- Tip text (centered at ~43%) ----
            {
                RECT r = {0, hh * 38 / 100, rc.right, hh * 47 / 100};
                SelectObject(hdc, hTip);
                SetTextColor(hdc, C_WHITE38);
                DrawTextW(hdc, TXT_TIP, -1, &r, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
            }

            // ---- Timer (centered at ~55%) ----
            {
                wchar_t buf[16];
                FormatTime(g_remaining_seconds.load(), buf, 16);
                RECT r = {0, hh * 48 / 100, rc.right, hh * 62 / 100};
                SelectObject(hdc, hTime);
                SetTextColor(hdc, C_WHITE);
                DrawTextW(hdc, buf, -1, &r, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
            }

            // ---- Buttons / Strict label (at ~78%) ----
            if (IsPrimaryMonitor(hwnd)) {
                SelectObject(hdc, hBtn);
                const int btnY = hh * 75 / 100;
                const bool postpone = g_allow_postpone.load();
                const bool skip = !g_strict.load();
                const int totalW = postpone && skip ? BTN_WIDTH * 2 + BTN_GAP : BTN_WIDTH;
                const int leftX = (rc.right - totalW) / 2;
                const int rightX = postpone ? leftX + BTN_WIDTH + BTN_GAP : leftX;
                const int hover = g_btn_hover.load();
                const int pressed = g_btn_pressed.load();

                if (postpone) {
                    RECT rL = {leftX, btnY, leftX + BTN_WIDTH, btnY + BTN_HEIGHT};
                    DrawButton(hdc, rL, TXT_POSTPONE,
                               hover == 1, pressed == 1,
                               C_WHITE54, RGB(200, 200, 200));
                }
                if (skip) {
                    RECT rR = {rightX, btnY, rightX + BTN_WIDTH, btnY + BTN_HEIGHT};
                    DrawButton(hdc, rR, TXT_SKIP,
                               hover == 2, pressed == 2,
                               C_WHITE38, C_WHITE54);
                }
                if (g_strict) {
                    SetTextColor(hdc, C_WHITE38);
                    RECT r = {0, btnY + (postpone ? BTN_HEIGHT + 8 : 8),
                              rc.right, btnY + (postpone ? BTN_HEIGHT + 30 : 30)};
                    DrawTextW(hdc, TXT_STRICT, -1, &r, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
                }
            }

            DeleteObject(hTitle);
            DeleteObject(hTime);
            DeleteObject(hTip);
            DeleteObject(hBtn);

            EndPaint(hwnd, &ps);
            return 0;
        }
        case WM_MOUSEMOVE: {
            if ((g_strict && !g_allow_postpone) || !IsPrimaryMonitor(hwnd)) return 0;

            TRACKMOUSEEVENT tme = {sizeof(tme), TME_LEAVE, hwnd, 0};
            TrackMouseEvent(&tme);

            int x = LOWORD(lp);
            int y = HIWORD(lp);
            int hit = HitTestButton(hwnd, x, y);

            if (g_btn_pressed.load()) return 0;

            int old = g_btn_hover.exchange(hit);
            if (old != hit) InvalidateAll();
            return 0;
        }
        case WM_MOUSELEAVE: {
            if (!g_btn_pressed.load()) {
                g_btn_hover.store(0);
                InvalidateAll();
            }
            return 0;
        }
        case WM_LBUTTONDOWN: {
            if ((g_strict && !g_allow_postpone) || !IsPrimaryMonitor(hwnd)) return 0;

            int x = LOWORD(lp);
            int y = HIWORD(lp);
            int hit = HitTestButton(hwnd, x, y);
            if (hit == 0) return 0;

            g_btn_hover.store(0);
            g_btn_pressed.store(hit);
            InvalidateAll();
            SetTimer(hwnd, PRESS_TIMER_ID, 150, NULL);

            // 1=postpone(left) 2=skip(right)
            // g_pending_action: 1=skip 2=postpone (matches ReminderService)
            g_pending_action.store(hit == 2 ? 1 : 2);
            return 0;
        }
        case WM_TIMER: {
            if (wp == TIMER_ID) {
                InvalidateAll();
            } else if (wp == PRESS_TIMER_ID) {
                KillTimer(hwnd, PRESS_TIMER_ID);
                g_btn_pressed.store(0);
                InvalidateAll();
            }
            return 0;
        }
        case WM_ERASEBKGND:
            return 1;
        case WM_CLOSE:
            return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

struct MonitorData {
    HINSTANCE hInstance;
    std::vector<HWND>* windows;
};

static BOOL CALLBACK MonitorEnumProc(HMONITOR hMon, HDC hdc,
                                      LPRECT rc, LPARAM data) {
    MONITORINFOEXW mi;
    mi.cbSize = sizeof(mi);
    if (!GetMonitorInfoW(hMon, &mi)) return TRUE;

    MonitorData* md = reinterpret_cast<MonitorData*>(data);

    int x = mi.rcMonitor.left;
    int y = mi.rcMonitor.top;
    int w = mi.rcMonitor.right - mi.rcMonitor.left;
    int h = mi.rcMonitor.bottom - mi.rcMonitor.top;

    HWND hwnd = CreateWindowExW(
        WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        OVERLAY_CLASS_NAME, L"",
        WS_POPUP | WS_VISIBLE,
        x, y, w, h,
        NULL, NULL, md->hInstance, NULL);

    if (hwnd) {
        std::lock_guard<std::mutex> guard(g_windows_mutex);
        md->windows->push_back(hwnd);
    }
    return TRUE;
}

static void ThreadProc(HINSTANCE hInst) {
    // Create this thread's message queue before overlay_start can request
    // a cancellation: PostThreadMessage(WM_QUIT) must never race startup.
    MSG msg;
    PeekMessageW(&msg, NULL, WM_USER, WM_USER, PM_NOREMOVE);
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = OverlayWndProc;
    wc.hInstance = hInst;
    wc.lpszClassName = OVERLAY_CLASS_NAME;
    wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    const bool registered = RegisterClassExW(&wc) != 0;
    bool allCovered = false;
    if (registered && g_running.load()) {
        MonitorData data = {hInst, &g_overlay_windows};
        const BOOL enumerated = EnumDisplayMonitors(
            NULL, NULL, MonitorEnumProc, reinterpret_cast<LPARAM>(&data));
        std::lock_guard<std::mutex> guard(g_windows_mutex);
        const int monitors = GetSystemMetrics(SM_CMONITORS);
        allCovered = enumerated && monitors > 0 &&
            g_overlay_windows.size() == static_cast<size_t>(monitors);
        if (allCovered) {
            for (HWND h : g_overlay_windows) {
                if (!SetTimer(h, TIMER_ID, 1000, NULL)) allCovered = false;
            }
        }
    }
    // Do not report successful startup merely because std::thread started.
    // The Flutter main window may be hidden only after every monitor exists.
    g_startup_status.store(allCovered ? 1 : -1);
    while (allCovered && g_running.load() && GetMessageW(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }
    g_startup_status.store(-1);
    {
        std::lock_guard<std::mutex> guard(g_windows_mutex);
        for (HWND hwnd : g_overlay_windows) {
            KillTimer(hwnd, TIMER_ID);
            DestroyWindow(hwnd);
        }
        g_overlay_windows.clear();
    }
    if (registered) UnregisterClassW(OVERLAY_CLASS_NAME, hInst);
}

extern "C" {

__declspec(dllexport) int32_t overlay_start() {
    if (g_running.exchange(true)) return g_startup_status.load() == 1 ? 1 : -1;
    g_startup_status.store(0);
    g_pending_action.store(0);
    g_btn_hover.store(0);
    g_btn_pressed.store(0);
    HINSTANCE hInst = GetModuleHandleW(NULL);
    try {
        g_overlay_thread = std::thread(ThreadProc, hInst);
    } catch (...) {
        g_startup_status.store(-1);
        g_running.store(false);
        return -1;
    }
    // Bounded cold-start handshake: no hidden main window without actual
    // native surfaces on all monitors. Fail back to the Flutter rest view.
    for (int attempt = 0; attempt < 100; attempt++) {
        const int state = g_startup_status.load();
        if (state == 1 && g_running.load()) return 0;
        if (state < 0) break;
        Sleep(10);
    }
    g_running.store(false);
    if (g_overlay_thread.joinable()) {
        PostThreadMessageW(GetThreadId(g_overlay_thread.native_handle()),
                           WM_QUIT, 0, 0);
        g_overlay_thread.join();
    }
    g_startup_status.store(-1);
    return -1;
}

__declspec(dllexport) void overlay_stop() {
    g_running.store(false);
    if (g_overlay_thread.joinable()) {
        PostThreadMessageW(GetThreadId(g_overlay_thread.native_handle()),
                           WM_QUIT, 0, 0);
        g_overlay_thread.join();
    }
    g_startup_status.store(-1);
}

__declspec(dllexport) void overlay_set_remaining(int32_t seconds) {
    g_remaining_seconds.store(seconds);
    InvalidateAll();
}

__declspec(dllexport) int32_t overlay_consume_action() {
    return g_pending_action.exchange(0);
}

__declspec(dllexport) void overlay_set_strict(int32_t strict) {
    g_strict.store(strict != 0);
}

__declspec(dllexport) void overlay_set_postpone_allowed(int32_t allowed) {
    g_allow_postpone.store(allowed != 0);
}

__declspec(dllexport) int32_t overlay_is_ready() {
    return g_running.load() && g_startup_status.load() == 1 ? 1 : 0;
}

__declspec(dllexport) int32_t overlay_monitor_count() {
    return GetSystemMetrics(SM_CMONITORS);
}

}  // extern "C"
