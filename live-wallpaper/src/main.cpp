// Live Wallpaper - plays a looping video behind the desktop icons.
//
// Built to be light: the video is decoded and drawn by the graphics card
// (Media Foundation Media Engine), there is no UI besides a tray icon, and
// playback pauses whenever nobody can see it (game or maximised window on
// top, screen locked, display off, laptop on battery).
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <commdlg.h>
#include <shlwapi.h>
#include <wtsapi32.h>
#include <d3d11.h>
#include <dxgi.h>
#include <mfapi.h>
#include <mfidl.h>
#undef GetCurrentTime   // winbase.h macro clashes with IMFMediaEngine::GetCurrentTime
#include <initguid.h>
#include <mfmediaengine.h>
#include <cstdio>
#include <cstdarg>
#include <cwchar>
#include <string>
#include "resource.h"

// ---------------------------------------------------------------- texts
struct Texts {
    const wchar_t *choose, *pause, *resume, *pauseMax, *pauseBattery, *fill, *autostart, *exit,
                  *running, *paused, *videos, *pickFirst, *playError;
};
static const Texts TXT_DE = {
    L"Video wählen…", L"Pause", L"Fortsetzen",
    L"Pausieren, wenn ein Fenster maximiert ist", L"Im Akkubetrieb pausieren",
    L"Bildschirm ausfüllen (Rand abschneiden)", L"Mit Windows starten", L"Beenden",
    L"läuft", L"pausiert", L"Videos",
    L"Bitte wähle ein Video für den Hintergrund aus.",
    L"Das Video konnte nicht abgespielt werden. Bitte wähle eine andere Datei (MP4 empfohlen)."};
static const Texts TXT_FR = {
    L"Choisir une vidéo…", L"Pause", L"Reprendre",
    L"Mettre en pause si une fenêtre est agrandie", L"Mettre en pause sur batterie",
    L"Remplir l'écran (rogner les bords)", L"Lancer avec Windows", L"Quitter",
    L"en lecture", L"en pause", L"Vidéos",
    L"Choisis une vidéo pour le fond d'écran.",
    L"La vidéo ne peut pas être lue. Choisis un autre fichier (MP4 conseillé)."};
static const Texts TXT_EN = {
    L"Choose video…", L"Pause", L"Resume",
    L"Pause when a window is maximised", L"Pause on battery",
    L"Fill the screen (crop edges)", L"Start with Windows", L"Exit",
    L"playing", L"paused", L"Videos",
    L"Please choose a video for the wallpaper.",
    L"The video could not be played. Please choose another file (MP4 recommended)."};
static const Texts* T = &TXT_EN;

// ---------------------------------------------------------------- state
static const wchar_t* APP_NAME = L"Live Wallpaper";
static const wchar_t* RUN_KEY = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
static const wchar_t* RUN_VALUE = L"LiveWallpaper";
enum { WM_TRAY = WM_APP + 1, WM_ENGINE = WM_APP + 2 };
enum { TIMER_WATCH = 1, TIMER_REBUILD = 2, TIMER_TEST = 3 };
enum { CMD_CHOOSE = 100, CMD_PAUSE, CMD_PAUSE_MAX, CMD_PAUSE_BATTERY, CMD_FILL, CMD_AUTOSTART, CMD_EXIT };

struct Settings {
    std::wstring video;
    bool pauseMax = true;
    bool pauseBattery = true;
    bool fill = true;
} S;

static HINSTANCE gInst;
static HWND gMsg, gVideo;
static UINT gTaskbarCreated;
static HICON gIcon;
static std::wstring gExeDir, gDataDir, gIni, gLogPath;
static IMFMediaEngine* gEngine;
static IMFMediaEngineEx* gEngineEx;
static ID3D11Device* gDevice;
static IMFDXGIDeviceManager* gDxgi;
static HPOWERNOTIFY gDisplayNotify;
static bool gManualPause, gLocked, gDisplayOff, gPlaying, gTest, gGpu;
static int gTestSeconds;
static UINT gFailures;

// ---------------------------------------------------------------- log
static void Log(const wchar_t* fmt, ...) {
    FILE* f = _wfopen(gLogPath.c_str(), L"a, ccs=UTF-8");
    if (!f) return;
    SYSTEMTIME st; GetLocalTime(&st);
    fwprintf(f, L"%02d:%02d:%02d.%03d  ", st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);
    va_list ap; va_start(ap, fmt); vfwprintf(f, fmt, ap); va_end(ap);
    fputwc(L'\n', f);
    fclose(f);
}

// ---------------------------------------------------------------- settings
static bool ReadBool(const wchar_t* key, bool def) {
    return GetPrivateProfileIntW(L"LiveWallpaper", key, def ? 1 : 0, gIni.c_str()) != 0;
}
static void WriteBool(const wchar_t* key, bool v) {
    WritePrivateProfileStringW(L"LiveWallpaper", key, v ? L"1" : L"0", gIni.c_str());
}
static void LoadSettings() {
    wchar_t buf[MAX_PATH * 2] = {};
    GetPrivateProfileStringW(L"LiveWallpaper", L"Video", L"", buf, ARRAYSIZE(buf), gIni.c_str());
    S.video = buf;
    S.pauseMax = ReadBool(L"PauseWhenMaximized", true);
    S.pauseBattery = ReadBool(L"PauseOnBattery", true);
    S.fill = ReadBool(L"FillScreen", true);
}
static void SaveSettings() {
    if (gTest) return;
    WritePrivateProfileStringW(L"LiveWallpaper", L"Video", S.video.c_str(), gIni.c_str());
    WriteBool(L"PauseWhenMaximized", S.pauseMax);
    WriteBool(L"PauseOnBattery", S.pauseBattery);
    WriteBool(L"FillScreen", S.fill);
}

static std::wstring ExePath() {
    wchar_t p[MAX_PATH * 2]; GetModuleFileNameW(nullptr, p, ARRAYSIZE(p)); return p;
}
static bool AutostartEnabled() {
    wchar_t v[MAX_PATH * 2]; DWORD sz = sizeof v;
    return RegGetValueW(HKEY_CURRENT_USER, RUN_KEY, RUN_VALUE, RRF_RT_REG_SZ, nullptr, v, &sz) == ERROR_SUCCESS;
}
static void SetAutostart(bool on) {
    HKEY k;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, RUN_KEY, 0, KEY_SET_VALUE, &k) != ERROR_SUCCESS) return;
    if (on) {
        std::wstring cmd = L"\"" + ExePath() + L"\"";
        RegSetValueExW(k, RUN_VALUE, 0, REG_SZ, (const BYTE*)cmd.c_str(), (DWORD)((cmd.size() + 1) * sizeof(wchar_t)));
    } else {
        RegDeleteValueW(k, RUN_VALUE);
    }
    RegCloseKey(k);
}

static bool FileExists(const std::wstring& p) {
    DWORD a = GetFileAttributesW(p.c_str());
    return a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY);
}
// First video found next to the exe (the ZIP ships with some).
static std::wstring FindBundledVideo() {
    static const wchar_t* pats[] = {L"*.mp4", L"videos\\*.mp4"};
    for (auto pat : pats) {
        WIN32_FIND_DATAW fd;
        HANDLE h = FindFirstFileW((gExeDir + L"\\" + pat).c_str(), &fd);
        if (h == INVALID_HANDLE_VALUE) continue;
        FindClose(h);
        std::wstring dir = gExeDir + (wcschr(pat, L'\\') ? L"\\videos\\" : L"\\");
        return dir + fd.cFileName;
    }
    return L"";
}

// ---------------------------------------------------------------- desktop host
// Windows draws the wallpaper on a "WorkerW" window that sits behind the
// desktop icons. Message 0x052C asks Explorer to create it. Since Windows 11
// 24H2 it lives inside Progman (below the icon view) instead of being a
// separate top-level window, so both layouts are handled.
struct Host { HWND parent; HWND insertAfter; bool modern; };

static BOOL CALLBACK FindIconsWindow(HWND h, LPARAM lp) {
    if (FindWindowExW(h, nullptr, L"SHELLDLL_DefView", nullptr)) {
        HWND w = FindWindowExW(nullptr, h, L"WorkerW", nullptr);
        if (w) { *(HWND*)lp = w; return FALSE; }
    }
    return TRUE;
}

static bool FindHost(Host& out) {
    HWND progman = FindWindowW(L"Progman", nullptr);
    if (!progman) return false;
    DWORD_PTR r;
    SendMessageTimeoutW(progman, 0x052C, 0xD, 0x1, SMTO_NORMAL, 1000, &r);
    SendMessageTimeoutW(progman, 0x052C, 0, 0, SMTO_NORMAL, 1000, &r);

    HWND defView = FindWindowExW(progman, nullptr, L"SHELLDLL_DefView", nullptr);
    HWND innerWorker = FindWindowExW(progman, nullptr, L"WorkerW", nullptr);
    if (defView && innerWorker) {                 // Windows 11 24H2 and later
        out = {progman, defView, true};
        return true;
    }
    HWND worker = nullptr;
    EnumWindows(FindIconsWindow, (LPARAM)&worker);
    if (worker) {                                 // Windows 10 / 11 up to 23H2
        out = {worker, nullptr, false};
        return true;
    }
    if (defView) { out = {progman, defView, true}; return true; }
    return false;
}

static RECT PrimaryMonitor() {
    MONITORINFO mi = {sizeof mi};
    GetMonitorInfoW(MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY), &mi);
    return mi.rcMonitor;
}

static LRESULT CALLBACK VideoProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    switch (m) {
    case WM_ERASEBKGND: return 1;
    case WM_PAINT: {
        PAINTSTRUCT ps; HDC dc = BeginPaint(h, &ps);
        if (!gEngine) FillRect(dc, &ps.rcPaint, (HBRUSH)GetStockObject(BLACK_BRUSH));
        EndPaint(h, &ps);
        return 0;
    }
    case WM_NCHITTEST: return HTTRANSPARENT;
    }
    return DefWindowProcW(h, m, w, l);
}

static bool CreateVideoWindow() {
    Host host;
    if (!FindHost(host)) { Log(L"desktop host not found"); return false; }
    RECT mon = PrimaryMonitor();
    POINT p = {mon.left, mon.top};
    ScreenToClient(host.parent, &p);
    gVideo = CreateWindowExW(host.modern ? WS_EX_LAYERED : 0, L"LiveWallpaperVideo", L"",
                             WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_CLIPCHILDREN,
                             p.x, p.y, mon.right - mon.left, mon.bottom - mon.top,
                             host.parent, nullptr, gInst, nullptr);
    if (!gVideo) { Log(L"CreateWindowEx failed: %lu", GetLastError()); return false; }
    if (host.modern) {
        SetLayeredWindowAttributes(gVideo, 0, 255, LWA_ALPHA);
        SetWindowPos(gVideo, host.insertAfter, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }
    Log(L"video window %p in %ls host %p at %ld,%ld size %ldx%ld", (void*)gVideo,
        host.modern ? L"24H2" : L"classic", (void*)host.parent, p.x, p.y, mon.right - mon.left, mon.bottom - mon.top);
    return true;
}

// ---------------------------------------------------------------- media engine
struct EngineNotify : IMFMediaEngineNotify {
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
        if (riid == __uuidof(IUnknown) || riid == __uuidof(IMFMediaEngineNotify)) { *ppv = this; return S_OK; }
        *ppv = nullptr; return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return 2; }
    STDMETHODIMP_(ULONG) Release() override { return 1; }
    STDMETHODIMP EventNotify(DWORD ev, DWORD_PTR p1, DWORD p2) override {
        // Called on a Media Foundation thread: hand over to the UI thread.
        PostMessageW(gMsg, WM_ENGINE, ev, (LPARAM)(((UINT64)(p1 & 0xFFFF) << 32) | p2));
        return S_OK;
    }
} gNotify;

template <class I> static void SafeRelease(I*& p) { if (p) { p->Release(); p = nullptr; } }

static void CreateGpuDevice() {
    static const D3D_FEATURE_LEVEL lv[] = {D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1,
                                           D3D_FEATURE_LEVEL_10_0, D3D_FEATURE_LEVEL_9_3};
    UINT flags = D3D11_CREATE_DEVICE_VIDEO_SUPPORT | D3D11_CREATE_DEVICE_BGRA_SUPPORT;
    HRESULT hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, lv, ARRAYSIZE(lv),
                                   D3D11_SDK_VERSION, &gDevice, nullptr, nullptr);
    if (hr == E_INVALIDARG)
        hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, lv + 1, ARRAYSIZE(lv) - 1,
                               D3D11_SDK_VERSION, &gDevice, nullptr, nullptr);
    if (FAILED(hr)) { Log(L"no GPU video device (0x%08lx): software decoding", (unsigned long)hr); return; }

    ID3D10Multithread* mt = nullptr;
    if (SUCCEEDED(gDevice->QueryInterface(__uuidof(ID3D10Multithread), (void**)&mt))) {
        mt->SetMultithreadProtected(TRUE);
        mt->Release();
    }
    UINT token = 0;
    if (FAILED(MFCreateDXGIDeviceManager(&token, &gDxgi)) || FAILED(gDxgi->ResetDevice(gDevice, token))) {
        SafeRelease(gDxgi); SafeRelease(gDevice);
        Log(L"DXGI device manager failed: software decoding");
        return;
    }
    IDXGIDevice* dd = nullptr; IDXGIAdapter* ad = nullptr; DXGI_ADAPTER_DESC desc = {};
    if (SUCCEEDED(gDevice->QueryInterface(__uuidof(IDXGIDevice), (void**)&dd)) && SUCCEEDED(dd->GetAdapter(&ad)))
        ad->GetDesc(&desc);
    SafeRelease(ad); SafeRelease(dd);
    Log(L"GPU decoding on: %ls", desc.Description);
}

static void ApplyFit() {
    if (!gEngine || !gEngineEx || !gVideo) return;
    DWORD vw = 0, vh = 0;
    if (FAILED(gEngine->GetNativeVideoSize(&vw, &vh)) || !vw || !vh) return;
    RECT rc; GetClientRect(gVideo, &rc);
    double ww = rc.right - rc.left, wh = rc.bottom - rc.top;
    if (ww <= 0 || wh <= 0) return;
    double va = (double)vw / vh, wa = ww / wh;
    MFVideoNormalizedRect src = {0.f, 0.f, 1.f, 1.f};
    RECT dst = rc;
    if (S.fill) {                       // crop the video so it covers the whole screen
        if (va > wa) { float k = (float)(wa / va); src.left = (1.f - k) / 2; src.right = 1.f - src.left; }
        else         { float k = (float)(va / wa); src.top = (1.f - k) / 2;  src.bottom = 1.f - src.top; }
    } else {                            // whole video visible, black bars
        if (va > wa) { LONG h = (LONG)(ww / va); dst.top = (LONG)((wh - h) / 2); dst.bottom = dst.top + h; }
        else         { LONG w = (LONG)(wh * va); dst.left = (LONG)((ww - w) / 2); dst.right = dst.left + w; }
    }
    MFARGB black = {0, 0, 0, 255};
    HRESULT hr = gEngineEx->UpdateVideoStream(&src, &dst, &black);
    Log(L"video %lux%lu -> %ls (0x%08lx)", vw, vh, S.fill ? L"fill" : L"fit", (unsigned long)hr);
}

static void StopEngine() {
    if (gEngine) gEngine->Shutdown();
    SafeRelease(gEngineEx);
    SafeRelease(gEngine);
    SafeRelease(gDxgi);
    SafeRelease(gDevice);
    gPlaying = false;
}

static bool StartEngine(bool useGpu) {
    StopEngine();
    if (useGpu) CreateGpuDevice();
    gGpu = gDxgi != nullptr;

    IMFAttributes* attr = nullptr;
    IMFMediaEngineClassFactory* factory = nullptr;
    HRESULT hr = MFCreateAttributes(&attr, 4);
    if (SUCCEEDED(hr)) hr = attr->SetUnknown(MF_MEDIA_ENGINE_CALLBACK, &gNotify);
    if (SUCCEEDED(hr)) hr = attr->SetUINT64(MF_MEDIA_ENGINE_PLAYBACK_HWND, (UINT64)(UINT_PTR)gVideo);
    if (SUCCEEDED(hr)) hr = attr->SetUINT32(MF_MEDIA_ENGINE_VIDEO_OUTPUT_FORMAT, DXGI_FORMAT_B8G8R8A8_UNORM);
    if (SUCCEEDED(hr) && gDxgi) hr = attr->SetUnknown(MF_MEDIA_ENGINE_DXGI_MANAGER, gDxgi);
    if (SUCCEEDED(hr)) hr = CoCreateInstance(CLSID_MFMediaEngineClassFactory, nullptr, CLSCTX_INPROC_SERVER,
                                             __uuidof(IMFMediaEngineClassFactory), (void**)&factory);
    if (SUCCEEDED(hr)) hr = factory->CreateInstance(MF_MEDIA_ENGINE_FORCEMUTE, attr, &gEngine);
    SafeRelease(factory);
    SafeRelease(attr);
    if (FAILED(hr)) {
        Log(L"media engine creation failed (0x%08lx)", (unsigned long)hr);
        StopEngine();
        return useGpu ? StartEngine(false) : false;
    }
    gEngine->QueryInterface(__uuidof(IMFMediaEngineEx), (void**)&gEngineEx);
    gEngine->SetLoop(TRUE);
    gEngine->SetMuted(TRUE);
    gEngine->SetAutoPlay(FALSE);
    gEngine->SetPreload(MF_MEDIA_ENGINE_PRELOAD_AUTOMATIC);

    wchar_t url[4096]; DWORD n = ARRAYSIZE(url);
    if (FAILED(UrlCreateFromPathW(S.video.c_str(), url, &n, 0))) wcsncpy(url, S.video.c_str(), ARRAYSIZE(url) - 1);
    BSTR b = SysAllocString(url);
    hr = gEngine->SetSource(b);
    SysFreeString(b);
    Log(L"source %ls (0x%08lx)", S.video.c_str(), (unsigned long)hr);
    return SUCCEEDED(hr);
}

// ---------------------------------------------------------------- tray
static void UpdateTray(DWORD op) {
    NOTIFYICONDATAW n = {sizeof n};
    n.hWnd = gMsg; n.uID = 1;
    n.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    n.uCallbackMessage = WM_TRAY;
    n.hIcon = gIcon;
    swprintf(n.szTip, ARRAYSIZE(n.szTip), L"%ls – %ls", APP_NAME, gPlaying ? T->running : T->paused);
    Shell_NotifyIconW(op, &n);
}
static void RemoveTray() {
    NOTIFYICONDATAW n = {sizeof n}; n.hWnd = gMsg; n.uID = 1;
    Shell_NotifyIconW(NIM_DELETE, &n);
}

// ---------------------------------------------------------------- pause logic
static bool OnBattery() {
    SYSTEM_POWER_STATUS ps;
    return GetSystemPowerStatus(&ps) && ps.ACLineStatus == 0;
}

static const wchar_t* HiddenReason() {
    QUERY_USER_NOTIFICATION_STATE q;
    if (SUCCEEDED(SHQueryUserNotificationState(&q)) &&
        (q == QUNS_RUNNING_D3D_FULL_SCREEN || q == QUNS_BUSY || q == QUNS_PRESENTATION_MODE))
        return L"fullscreen app";
    HWND fg = GetForegroundWindow();
    if (!fg || !gVideo) return nullptr;
    wchar_t cls[64] = {};
    GetClassNameW(fg, cls, ARRAYSIZE(cls));
    if (!wcscmp(cls, L"Progman") || !wcscmp(cls, L"WorkerW") || !wcscmp(cls, L"Shell_TrayWnd")) return nullptr;
    if (MonitorFromWindow(fg, MONITOR_DEFAULTTONULL) != MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY)) return nullptr;
    RECT m = PrimaryMonitor(), r;
    GetWindowRect(fg, &r);
    if (r.left <= m.left && r.top <= m.top && r.right >= m.right && r.bottom >= m.bottom) return L"fullscreen window";
    if (S.pauseMax && IsZoomed(fg) && !IsIconic(fg)) return L"maximised window";
    return nullptr;
}

static void UpdatePlayback() {
    if (!gEngine) return;
    const wchar_t* why = nullptr;
    if (gManualPause) why = L"paused by user";
    else if (gTest) why = nullptr;              // the self-test always plays
    else if (gLocked) why = L"session locked";
    else if (gDisplayOff) why = L"display off";
    else if (S.pauseBattery && OnBattery()) why = L"on battery";
    else why = HiddenReason();
    bool want = why == nullptr;
    if (want == gPlaying) return;
    gPlaying = want;
    if (want) gEngine->Play();
    else {
        gEngine->Pause();
        SetProcessWorkingSetSize(GetCurrentProcess(), (SIZE_T)-1, (SIZE_T)-1);   // give RAM back while paused
    }
    Log(want ? L"play" : L"pause: %ls", why);
    UpdateTray(NIM_MODIFY);
}

// ---------------------------------------------------------------- lifecycle
static bool ChooseVideo(HWND owner) {
    wchar_t file[MAX_PATH * 2] = {};
    wchar_t filter[256];
    swprintf(filter, ARRAYSIZE(filter), L"%ls (*.mp4;*.mkv;*.mov;*.m4v;*.wmv;*.avi)%c*.mp4;*.mkv;*.mov;*.m4v;*.wmv;*.avi%c%c",
             T->videos, 0, 0, 0);
    OPENFILENAMEW of = {sizeof of};
    of.hwndOwner = owner;
    of.lpstrFilter = filter;
    of.lpstrFile = file;
    of.nMaxFile = ARRAYSIZE(file);
    of.lpstrTitle = T->choose;
    of.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;
    if (!GetOpenFileNameW(&of)) return false;
    S.video = file;
    SaveSettings();
    return true;
}

static void Teardown() {
    StopEngine();
    if (gVideo) { DestroyWindow(gVideo); gVideo = nullptr; }
}

static void Rebuild() {
    Teardown();
    if (!CreateVideoWindow()) { SetTimer(gMsg, TIMER_REBUILD, 3000, nullptr); return; }
    StartEngine(true);
}

static void RestoreWallpaper() {
    wchar_t wp[MAX_PATH] = {};
    SystemParametersInfoW(SPI_GETDESKWALLPAPER, MAX_PATH, wp, 0);
    SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, wp, 0);    // repaint the normal wallpaper
}

static void ShowMenu() {
    HMENU m = CreatePopupMenu();
    AppendMenuW(m, MF_STRING, CMD_CHOOSE, T->choose);
    AppendMenuW(m, MF_STRING, CMD_PAUSE, gManualPause ? T->resume : T->pause);
    AppendMenuW(m, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(m, MF_STRING | (S.fill ? MF_CHECKED : 0), CMD_FILL, T->fill);
    AppendMenuW(m, MF_STRING | (S.pauseMax ? MF_CHECKED : 0), CMD_PAUSE_MAX, T->pauseMax);
    AppendMenuW(m, MF_STRING | (S.pauseBattery ? MF_CHECKED : 0), CMD_PAUSE_BATTERY, T->pauseBattery);
    AppendMenuW(m, MF_STRING | (AutostartEnabled() ? MF_CHECKED : 0), CMD_AUTOSTART, T->autostart);
    AppendMenuW(m, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(m, MF_STRING, CMD_EXIT, T->exit);
    POINT pt; GetCursorPos(&pt);
    SetForegroundWindow(gMsg);
    TrackPopupMenu(m, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, pt.x, pt.y, 0, gMsg, nullptr);
    PostMessageW(gMsg, WM_NULL, 0, 0);
    DestroyMenu(m);
}

static LRESULT CALLBACK MsgProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == gTaskbarCreated && gTaskbarCreated) {      // Explorer restarted
        Log(L"explorer restarted");
        UpdateTray(NIM_ADD);
        SetTimer(h, TIMER_REBUILD, 1500, nullptr);
        return 0;
    }
    switch (m) {
    case WM_TRAY:
        if (l == WM_RBUTTONUP || l == WM_CONTEXTMENU) ShowMenu();
        else if (l == WM_LBUTTONDBLCLK) PostMessageW(h, WM_COMMAND, CMD_PAUSE, 0);
        return 0;
    case WM_COMMAND:
        switch (LOWORD(w)) {
        case CMD_CHOOSE: if (ChooseVideo(nullptr)) { gFailures = 0; Rebuild(); } break;
        case CMD_PAUSE: gManualPause = !gManualPause; UpdatePlayback(); break;
        case CMD_FILL: S.fill = !S.fill; SaveSettings(); ApplyFit(); break;
        case CMD_PAUSE_MAX: S.pauseMax = !S.pauseMax; SaveSettings(); UpdatePlayback(); break;
        case CMD_PAUSE_BATTERY: S.pauseBattery = !S.pauseBattery; SaveSettings(); UpdatePlayback(); break;
        case CMD_AUTOSTART: SetAutostart(!AutostartEnabled()); break;
        case CMD_EXIT: DestroyWindow(h); break;
        }
        return 0;
    case WM_ENGINE: {
        DWORD ev = (DWORD)w;
        if (ev == MF_MEDIA_ENGINE_EVENT_LOADEDMETADATA) { ApplyFit(); gPlaying = false; UpdatePlayback(); }
        else if (ev == MF_MEDIA_ENGINE_EVENT_PLAYING) Log(L"playing (%ls decoding)", gGpu ? L"GPU" : L"software");
        else if (ev == MF_MEDIA_ENGINE_EVENT_ERROR) {
            Log(L"playback error %u (0x%08lx)", (unsigned)((UINT64)l >> 32), (unsigned long)(l & 0xFFFFFFFF));
            if (gGpu && gFailures++ == 0) { StartEngine(false); }      // retry once without the GPU
            else if (!gTest) { MessageBoxW(nullptr, T->playError, APP_NAME, MB_ICONWARNING); PostMessageW(h, WM_COMMAND, CMD_CHOOSE, 0); }
        }
        return 0;
    }
    case WM_TIMER:
        if (w == TIMER_WATCH) UpdatePlayback();
        else if (w == TIMER_REBUILD) { KillTimer(h, TIMER_REBUILD); Rebuild(); }
        else if (w == TIMER_TEST) {
            double t = gEngine ? gEngine->GetCurrentTime() : -1;
            DWORD vw = 0, vh = 0; if (gEngine) gEngine->GetNativeVideoSize(&vw, &vh);
            Log(L"TEST position %.2f s, video %lux%lu, decoding %ls, window %ls", t, vw, vh,
                gGpu ? L"GPU" : L"software", gVideo && IsWindow(gVideo) ? L"ok" : L"missing");
            PostQuitMessage(t > 0.5 && gVideo ? 0 : 2);
        }
        return 0;
    case WM_DISPLAYCHANGE:
        SetTimer(h, TIMER_REBUILD, 1500, nullptr);
        return 0;
    case WM_WTSSESSION_CHANGE:
        if (w == WTS_SESSION_LOCK) gLocked = true;
        else if (w == WTS_SESSION_UNLOCK) gLocked = false;
        UpdatePlayback();
        return 0;
    case WM_POWERBROADCAST:
        if (w == PBT_POWERSETTINGCHANGE) {
            auto* ps = (POWERBROADCAST_SETTING*)l;
            if (ps && IsEqualGUID(ps->PowerSetting, GUID_CONSOLE_DISPLAY_STATE) && ps->DataLength >= sizeof(DWORD))
                gDisplayOff = *(DWORD*)ps->Data == 0;
        }
        UpdatePlayback();
        return TRUE;
    case WM_DESTROY:
        KillTimer(h, TIMER_WATCH);
        if (gDisplayNotify) UnregisterPowerSettingNotification(gDisplayNotify);
        WTSUnRegisterSessionNotification(h);
        RemoveTray();
        Teardown();
        RestoreWallpaper();
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(h, m, w, l);
}

static void ParseArgs() {
    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    for (int i = 1; argv && i < argc; i++) {
        if (!wcscmp(argv[i], L"--video") && i + 1 < argc) S.video = argv[++i];
        else if (!wcscmp(argv[i], L"--test") && i + 1 < argc) { gTest = true; gTestSeconds = _wtoi(argv[++i]); }
        else if (!wcscmp(argv[i], L"--log") && i + 1 < argc) gLogPath = argv[++i];
    }
    LocalFree(argv);
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE, PWSTR, int) {
    gInst = inst;
    LANGID lang = PRIMARYLANGID(GetUserDefaultUILanguage());
    T = lang == LANG_GERMAN ? &TXT_DE : lang == LANG_FRENCH ? &TXT_FR : &TXT_EN;

    std::wstring exe = ExePath();
    gExeDir = exe.substr(0, exe.find_last_of(L'\\'));
    wchar_t appdata[MAX_PATH] = {};
    GetEnvironmentVariableW(L"APPDATA", appdata, MAX_PATH);
    gDataDir = std::wstring(appdata) + L"\\LiveWallpaper";
    CreateDirectoryW(gDataDir.c_str(), nullptr);
    gIni = gDataDir + L"\\settings.ini";
    gLogPath = gDataDir + L"\\log.txt";
    LoadSettings();
    ParseArgs();
    DeleteFileW(gLogPath.c_str());
    Log(L"Live Wallpaper start (%ls)", gTest ? L"self-test" : L"normal");

    HANDLE single = CreateMutexW(nullptr, TRUE, L"LiveWallpaper.SingleInstance");
    if (GetLastError() == ERROR_ALREADY_EXISTS && !gTest) return 0;

    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    MFStartup(MF_VERSION, MFSTARTUP_LITE);
    gIcon = LoadIconW(inst, MAKEINTRESOURCEW(IDI_APP));

    WNDCLASSW wc = {};
    wc.lpfnWndProc = MsgProc; wc.hInstance = inst; wc.lpszClassName = L"LiveWallpaperMsg"; wc.hIcon = gIcon;
    RegisterClassW(&wc);
    wc.lpfnWndProc = VideoProc; wc.lpszClassName = L"LiveWallpaperVideo";
    wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH); wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    RegisterClassW(&wc);
    gMsg = CreateWindowExW(WS_EX_TOOLWINDOW, L"LiveWallpaperMsg", APP_NAME, WS_POPUP, 0, 0, 0, 0, nullptr, nullptr, inst, nullptr);
    gTaskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");

    if (S.video.empty() || !FileExists(S.video)) {
        S.video = FindBundledVideo();
        if (S.video.empty() && !gTest) {
            MessageBoxW(nullptr, T->pickFirst, APP_NAME, MB_ICONINFORMATION);
            if (!ChooseVideo(nullptr)) { DestroyWindow(gMsg); return 0; }
        }
        SaveSettings();
    }

    UpdateTray(NIM_ADD);
    WTSRegisterSessionNotification(gMsg, NOTIFY_FOR_THIS_SESSION);
    gDisplayNotify = RegisterPowerSettingNotification(gMsg, &GUID_CONSOLE_DISPLAY_STATE, DEVICE_NOTIFY_WINDOW_HANDLE);
    Rebuild();
    SetTimer(gMsg, TIMER_WATCH, 1000, nullptr);
    if (gTest) SetTimer(gMsg, TIMER_TEST, (UINT)gTestSeconds * 1000, nullptr);

    MSG msg;
    int code = 0;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) { TranslateMessage(&msg); DispatchMessageW(&msg); }
    code = (int)msg.wParam;
    if (IsWindow(gMsg)) DestroyWindow(gMsg);      // test mode ends via PostQuitMessage
    MFShutdown();
    CoUninitialize();
    if (single) CloseHandle(single);
    return code;
}
