// In-game overlay menu built with Dear ImGui (Metal renderer on macOS, Vulkan elsewhere; input fed from SDL events).
//
// Threads: SDL events arrive on the main thread and are queued; the menu is laid out and drawn on the
// render thread inside backend_present, after the game image, into the same drawable.
#ifdef __APPLE__
#import <Metal/Metal.h>
#endif
#include <SDL3/SDL.h>
#include <math.h>
#include <pthread.h>
#include <atomic>
#include <vector>

#include "imgui.h"
#include "option_rows.h"
#include "imgui_internal.h"  // (NavCursorVisible)
#include "osk.h"
#ifdef __APPLE__
#include "imgui_impl_metal.h"
#else
#include "imgui_impl_vulkan.h"
extern "C" bool vk_imgui_backend_init(void);  // runtime/nvn/vulkan/imgui_glue.cpp
#endif

// 简体中文界面：中文字号（Baloo 2 的 39/72 在视觉上约等于下面这些值，可自行微调）
#ifndef ZH_MENU_PX
#define ZH_MENU_PX 33
#endif
#ifndef ZH_MENU_PX_BIG
#define ZH_MENU_PX_BIG 61
#endif
#ifndef ZH_OVERLAY_PX
#define ZH_OVERLAY_PX 30
#endif
#ifndef ZH_OVERLAY_PX_BIG
#define ZH_OVERLAY_PX_BIG 48
#endif
#include "zh_glyphs.h"  // ZH_UI_GLYPHS：界面里实际用到的汉字

extern "C" {
#include "../hle.h"
#include "../settings.h"
#include "../perfmon.h"
#include "menu.h"
extern "C" bool input_free_cam_active(void);  // runtime/hle/input.c: free camera session toggle
void input_reset(void);
void input_mouse_update(void *window, bool playing);
void save_editor_draw(float scale);  // save_editor.mm
extern "C" int game_in_play(void);  // hle/warp.c
void save_editor_on_open(void);
void rando_tab_draw(float scale);
bool warp_tab_draw(float scale);  // warp_tab.mm: true when a warp started
extern "C" void cheats_draw(float scale);  // cheats.mm
extern "C" void difficulty_rows(void);  // difficulty.mm
extern "C" void loftwing_rows(void);    // difficulty.mm
extern "C" void drop_rows(void);        // difficulty.mm
extern "C" void link_rows(void);        // difficulty.mm
void controls_bindings_draw(float scale);  // controls_ui.mm
#include "../input_bind.h"
#include "../paths.h"
}

// ------------------------------------------------------------------ state shared with the main thread
static std::atomic<bool> g_open{false};
static std::atomic<bool> g_text_busy{false};  // a text field / the on-screen keyboard has the keys (render thread: ui_text_busy)
static std::atomic<bool> g_want_fullscreen_apply{false};

// Zelda & Loftwing amiibo (runtime/services/nfp.c): the player loads their own figure's dump once; then Fi's
// "Use amiibo" recognises it. The file dialog opens on the main thread (macOS: AppKit panels only work there - from the
// render thread it aborted) and answers on another; the pick is handled on the menu's next frame.
extern "C" bool amiibo_loaded(void);
extern "C" bool amiibo_import(const char *path, char *msg, size_t cap);
static pthread_mutex_t amiibo_lock = PTHREAD_MUTEX_INITIALIZER;
static char amiibo_pick[1024], amiibo_msg[160];
static std::atomic<bool> g_amiibo_dialog{false};  // (opened on the main thread: menu_apply_window_requests)

static void SDLCALL amiibo_picked(void *, const char *const *files, int) {
    if (!files || !files[0]) return;
    pthread_mutex_lock(&amiibo_lock);
    snprintf(amiibo_pick, sizeof amiibo_pick, "%s", files[0]);
    pthread_mutex_unlock(&amiibo_lock);
}


struct QEvent {
    enum { KEY, ANALOG, MOUSE_POS, MOUSE_BUTTON, WHEEL, TEXT } kind;
    ImGuiKey key;
    bool down;
    float value, x, y;
    int button;
    char text[32];
};
static pthread_mutex_t q_lock = PTHREAD_MUTEX_INITIALIZER;
static std::vector<QEvent> q_events;
static float g_pixel_density = 1;

static void push(const QEvent &e) {
    pthread_mutex_lock(&q_lock);
    q_events.push_back(e);
    pthread_mutex_unlock(&q_lock);
}

bool menu_is_open(void) { return g_open.load(); }
static void set_open(bool open);
extern "C" void menu_test_open(void) {
    set_open(true);
    if (getenv("LARECOMP_MENU_TAB")) { extern int g_tab_request_ext; g_tab_request_ext = atoi(getenv("LARECOMP_MENU_TAB")); }
}

void menu_tabs_focus(bool first_tab);
static void set_open(bool open) {
    if (open == g_open.load()) return;
    g_open.store(open);
    input_reset();  // nothing held while the menu had focus leaks into the game
    bind_capture_cancel();
    if (open) {
        save_editor_on_open();
        static bool opened;  // the controller's cursor: the first tab (Controls) the first time this session, later the
        menu_tabs_focus(!opened);  // selected one
        opened = true;
    }
    else { settings_save(); osk_cancel(); g_text_busy = false; }
}

static ImGuiKey key_from_scancode(SDL_Scancode sc) {
    switch (sc) {
    case SDL_SCANCODE_UP: return ImGuiKey_UpArrow;
    case SDL_SCANCODE_DOWN: return ImGuiKey_DownArrow;
    case SDL_SCANCODE_LEFT: return ImGuiKey_LeftArrow;
    case SDL_SCANCODE_RIGHT: return ImGuiKey_RightArrow;
    case SDL_SCANCODE_RETURN: return ImGuiKey_Enter;
    case SDL_SCANCODE_KP_ENTER: return ImGuiKey_KeypadEnter;
    case SDL_SCANCODE_SPACE: return ImGuiKey_Space;
    case SDL_SCANCODE_TAB: return ImGuiKey_Tab;
    case SDL_SCANCODE_BACKSPACE: return ImGuiKey_Backspace;
    case SDL_SCANCODE_DELETE: return ImGuiKey_Delete;
    case SDL_SCANCODE_HOME: return ImGuiKey_Home;
    case SDL_SCANCODE_END: return ImGuiKey_End;
    case SDL_SCANCODE_PAGEUP: return ImGuiKey_PageUp;
    case SDL_SCANCODE_PAGEDOWN: return ImGuiKey_PageDown;
    case SDL_SCANCODE_LSHIFT: return ImGuiKey_LeftShift;
    case SDL_SCANCODE_RSHIFT: return ImGuiKey_RightShift;
    case SDL_SCANCODE_LCTRL: return ImGuiKey_LeftCtrl;
    case SDL_SCANCODE_RCTRL: return ImGuiKey_RightCtrl;
    case SDL_SCANCODE_LGUI: return ImGuiKey_LeftSuper;
    case SDL_SCANCODE_RGUI: return ImGuiKey_RightSuper;
    case SDL_SCANCODE_A: return ImGuiKey_A;
    case SDL_SCANCODE_C: return ImGuiKey_C;
    case SDL_SCANCODE_V: return ImGuiKey_V;
    case SDL_SCANCODE_X: return ImGuiKey_X;
    case SDL_SCANCODE_Z: return ImGuiKey_Z;
    case SDL_SCANCODE_Q: return ImGuiKey_Q;  // previous tab
    case SDL_SCANCODE_E: return ImGuiKey_E;  // next tab
    default: return ImGuiKey_None;
    }
}

// Nintendo layout: the right face button (A) confirms, the bottom one (B) goes back.
static ImGuiKey key_from_pad(Uint8 b) {
    switch (b) {
    case SDL_GAMEPAD_BUTTON_EAST: return ImGuiKey_GamepadFaceDown;   // activate
    case SDL_GAMEPAD_BUTTON_SOUTH: return ImGuiKey_GamepadFaceRight; // cancel / back
    case SDL_GAMEPAD_BUTTON_NORTH: return ImGuiKey_GamepadFaceUp;
    case SDL_GAMEPAD_BUTTON_WEST: return ImGuiKey_GamepadFaceLeft;
    case SDL_GAMEPAD_BUTTON_DPAD_UP: return ImGuiKey_GamepadDpadUp;
    case SDL_GAMEPAD_BUTTON_DPAD_DOWN: return ImGuiKey_GamepadDpadDown;
    case SDL_GAMEPAD_BUTTON_DPAD_LEFT: return ImGuiKey_GamepadDpadLeft;
    case SDL_GAMEPAD_BUTTON_DPAD_RIGHT: return ImGuiKey_GamepadDpadRight;
    case SDL_GAMEPAD_BUTTON_LEFT_SHOULDER: return ImGuiKey_GamepadL1;
    case SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER: return ImGuiKey_GamepadR1;
    case SDL_GAMEPAD_BUTTON_START: return ImGuiKey_GamepadStart;
    case SDL_GAMEPAD_BUTTON_BACK: return ImGuiKey_GamepadBack;
    default: return ImGuiKey_None;
    }
}

// ---- software keyboard (runtime/hle/swkbd.c: the game's name entry etc.) --------------------------------------
// The game thread waits in menu_keyboard_run (re-presenting the last frame); this dialog takes the text: typed
// directly when the player last used a keyboard, an on-screen keyboard (d-pad + A, B deletes, Start / + OK) when
// they last used a controller.
static std::atomic<int> g_kbd{0};  // 1 open, 2 confirmed, 3 cancelled
static std::atomic<bool> g_last_pad{false};
static char g_kbd_text[96];
static int g_kbd_max = 8;
static bool capturing() { return g_open.load() || g_kbd.load() == 1; }
// The game gets no input while this is true (runtime/hle/input.c): menu or name entry up.
extern "C" bool menu_input_captured(void) { return capturing(); }

bool menu_handle_event(const SDL_Event *e) {
    static bool back_down, start_down;
    if (g_open.load() && bind_capture_event(e)) return true;  // Controls tab waiting for a new binding: it takes the press
    if (e->type == SDL_EVENT_KEY_DOWN) g_last_pad = false;
    if (e->type == SDL_EVENT_GAMEPAD_BUTTON_DOWN) g_last_pad = true;
    if (g_kbd.load() == 1 && e->type == SDL_EVENT_KEY_DOWN && !e->key.repeat) {  // Enter confirms, Esc cancels
        if (e->key.scancode == SDL_SCANCODE_RETURN || e->key.scancode == SDL_SCANCODE_KP_ENTER) { g_kbd = 2; return true; }
        if (e->key.scancode == SDL_SCANCODE_ESCAPE) { g_kbd = 3; return true; }
    }
    if (g_kbd.load() == 1 && e->type == SDL_EVENT_GAMEPAD_BUTTON_DOWN && e->gbutton.button == SDL_GAMEPAD_BUTTON_START) {
        g_kbd = 2;
        return true;
    }
    // typing (a text field, the on-screen keyboard, the name entry): keys are text, not menu shortcuts
    bool typing = g_kbd.load() == 1 || (g_open.load() && g_text_busy.load());
    switch (e->type) {
    case SDL_EVENT_KEY_DOWN:
        if (!e->key.repeat && (e->key.scancode == SDL_SCANCODE_F1 ||
                               (e->key.scancode == SDL_SCANCODE_ESCAPE && !g_open.load()))) {
            if (!typing) set_open(!g_open.load());  // (Esc with the menu open goes to ImGui below: it cancels a field)
            return true;
        }
        if (!e->key.repeat && e->key.scancode == SDL_SCANCODE_F10 && !typing) {  // performance overlay: off, FPS, full
            g_settings.perf_overlay = (g_settings.perf_overlay + 1) % 3;
            settings_save();
            return true;
        }
        if (!e->key.repeat && (e->key.scancode == SDL_SCANCODE_F11 ||
                               (e->key.scancode == SDL_SCANCODE_RETURN && (e->key.mod & (SDL_KMOD_ALT | SDL_KMOD_GUI))) ||
                               (e->key.scancode == SDL_SCANCODE_F && (e->key.mod & SDL_KMOD_GUI) && (e->key.mod & SDL_KMOD_CTRL)))) {
            g_settings.fullscreen = !g_settings.fullscreen;
            g_want_fullscreen_apply.store(true);
            settings_save();
            return true;
        }
        /* fallthrough */
    case SDL_EVENT_KEY_UP: {
        if (!capturing()) return false;
        bool down = e->type == SDL_EVENT_KEY_DOWN;
        if (down && e->key.scancode == SDL_SCANCODE_ESCAPE) {  // Esc: back out of popups, else close
            QEvent q = {};
            q.kind = QEvent::KEY; q.key = ImGuiKey_Escape; q.down = true; push(q);
            q.down = false; push(q);
            return true;
        }
        ImGuiKey k = key_from_scancode(e->key.scancode);
        if (k != ImGuiKey_None) { QEvent q = {}; q.kind = QEvent::KEY; q.key = k; q.down = down; push(q); }
        return true;
    }
    case SDL_EVENT_TEXT_INPUT:
        if (!capturing()) return false;
        { QEvent q = {}; q.kind = QEvent::TEXT; strlcpy(q.text, e->text.text, sizeof q.text); push(q); }
        return true;
    case SDL_EVENT_GAMEPAD_BUTTON_DOWN: case SDL_EVENT_GAMEPAD_BUTTON_UP: {
        bool down = e->type == SDL_EVENT_GAMEPAD_BUTTON_DOWN;
        if (e->gbutton.button == SDL_GAMEPAD_BUTTON_BACK) back_down = down;
        if (e->gbutton.button == SDL_GAMEPAD_BUTTON_START) start_down = down;
        if (down && !typing && ((back_down && start_down) || e->gbutton.button == SDL_GAMEPAD_BUTTON_GUIDE)) {
            set_open(!g_open.load());
            return true;
        }
        if (!capturing()) return false;
        ImGuiKey k = key_from_pad(e->gbutton.button);
        if (k != ImGuiKey_None) { QEvent q = {}; q.kind = QEvent::KEY; q.key = k; q.down = down; push(q); }
        return true;
    }
    case SDL_EVENT_GAMEPAD_AXIS_MOTION: {
        if (!capturing()) return false;
        float v = e->gaxis.value / 32767.0f;
        QEvent q = {};
        q.kind = QEvent::ANALOG;
        switch (e->gaxis.axis) {
        case SDL_GAMEPAD_AXIS_LEFTX:
            q.key = ImGuiKey_GamepadLStickLeft; q.value = v < -0.3f ? -v : 0; push(q);
            q.key = ImGuiKey_GamepadLStickRight; q.value = v > 0.3f ? v : 0; push(q);
            break;
        case SDL_GAMEPAD_AXIS_LEFTY:
            q.key = ImGuiKey_GamepadLStickUp; q.value = v < -0.3f ? -v : 0; push(q);
            q.key = ImGuiKey_GamepadLStickDown; q.value = v > 0.3f ? v : 0; push(q);
            break;
        case SDL_GAMEPAD_AXIS_LEFT_TRIGGER: q.key = ImGuiKey_GamepadL2; q.value = v; push(q); break;
        case SDL_GAMEPAD_AXIS_RIGHT_TRIGGER: q.key = ImGuiKey_GamepadR2; q.value = v; push(q); break;
        default: break;
        }
        return true;
    }
    case SDL_EVENT_MOUSE_MOTION:
        if (!capturing()) return false;
        { QEvent q = {}; q.kind = QEvent::MOUSE_POS; q.x = e->motion.x * g_pixel_density; q.y = e->motion.y * g_pixel_density; push(q); }
        return true;
    case SDL_EVENT_MOUSE_BUTTON_DOWN: case SDL_EVENT_MOUSE_BUTTON_UP:
        if (!capturing()) return false;
        {
            QEvent q = {};
            q.kind = QEvent::MOUSE_BUTTON;
            q.button = e->button.button == SDL_BUTTON_LEFT ? 0 : e->button.button == SDL_BUTTON_RIGHT ? 1 : 2;
            q.down = e->type == SDL_EVENT_MOUSE_BUTTON_DOWN;
            push(q);
        }
        return true;
    case SDL_EVENT_MOUSE_WHEEL:
        if (!capturing()) return false;
        { QEvent q = {}; q.kind = QEvent::WHEEL; q.x = e->wheel.x; q.y = e->wheel.y; push(q); }
        return true;
    default:
        return false;
    }
}

void menu_apply_window_requests(void *win) {
    SDL_Window *w = (SDL_Window *)win;
    g_pixel_density = SDL_GetWindowPixelDensity(w);
    static bool text_input;
    bool want_text = capturing();
    input_mouse_update(w, true);
    if (want_text != text_input) {
        if (want_text) SDL_StartTextInput(w);
        else SDL_StopTextInput(w);
        text_input = want_text;
    }
    static bool first = true;
    if (first || g_want_fullscreen_apply.exchange(false)) {
        first = false;
        SDL_SetWindowFullscreen(w, g_settings.fullscreen);
    }
    if (g_amiibo_dialog.exchange(false)) {
        static const SDL_DialogFileFilter f[] = {{"amiibo dump", "bin"}};
        SDL_ShowOpenFileDialog(amiibo_picked, NULL, w, f, 1, NULL, false);
    }
}

// ------------------------------------------------------------------ render thread
// Performance overlay (F10, Settings > Video), in the style of MangoHud and of Savage Wind Recomp's (MIT): the game's
// frame rate and frame times, and the machine's load, memory and temperatures (runtime/perfmon.c). Numbers the
// platform doesn't give read "-". FPS mode keeps the old corner counter's size.
static void perf_cell(const char *fmt, float v) {
    ImGui::TableNextColumn();
    if (v < 0) ImGui::TextDisabled("-");
    else ImGui::Text(fmt, v);
}
static void perf_overlay_draw(ImGuiIO &io, float scale) {
    PerfStats s;
    perfmon_snapshot(&s);
    ImGui::SetNextWindowPos(ImVec2(io.DisplaySize.x - 16 * scale, 16 * scale), 0, ImVec2(1, 0));
    ImGui::SetNextWindowBgAlpha(g_settings.perf_overlay == PERF_FPS ? 0.45f : 0.6f);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(6 * scale, 2 * scale));
    ImGui::Begin("##perf", NULL, ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_AlwaysAutoResize |
                                     ImGuiWindowFlags_NoInputs | ImGuiWindowFlags_NoNav | ImGuiWindowFlags_NoFocusOnAppearing);
    if (g_settings.perf_overlay == PERF_FPS) {
        ImGui::SetWindowFontScale(0.65f);
        ImGui::Text("%.0f  %.1f ms", s.fps, s.frame_ms_avg);
        ImGui::End();
        ImGui::PopStyleVar();
        return;
    }
    ImGui::SetWindowFontScale(0.72f);
    const ImVec4 gpu_c(0.55f, 0.83f, 0.31f, 1), cpu_c(0.18f, 0.59f, 0.80f, 1), ram_c(0.80f, 0.45f, 0.70f, 1),
                 fps_c(0.95f, 0.95f, 0.95f, 1);
    if (ImGui::BeginTable("##perft", 5, ImGuiTableFlags_SizingFixedFit)) {
        ImGui::TableNextColumn(); ImGui::TextColored(gpu_c, "GPU");
        perf_cell("%.0f%%", s.gpu_pct); perf_cell("%.0f C", s.gpu_temp_c); perf_cell("%.0f W", s.gpu_power_w);
        perf_cell("%.0f MHz", s.gpu_clock_mhz);
        ImGui::TableNextColumn(); ImGui::TextColored(gpu_c, "VRAM");
        perf_cell("%.2f GB", s.vram_used_mb < 0 ? -1 : s.vram_used_mb / 1024);
        perf_cell("/ %.1f GB", s.vram_total_mb < 0 ? -1 : s.vram_total_mb / 1024);
        perf_cell("game %.2f GB", s.vram_game_mb < 0 ? -1 : s.vram_game_mb / 1024);
        ImGui::TableNextColumn();
        ImGui::TableNextColumn(); ImGui::TextColored(cpu_c, "CPU");
        perf_cell("%.0f%%", s.cpu_total_pct); perf_cell("%.0f C", s.cpu_temp_c); perf_cell("game %.0f%%", s.cpu_game_pct);
        ImGui::TableNextColumn();
        if (s.cpu_temp_c >= 0 && s.cpu_temp_source) ImGui::TextDisabled("%s", s.cpu_temp_source);
        ImGui::TableNextColumn(); ImGui::TextColored(ram_c, "RAM");
        perf_cell("%.1f GB", s.ram_used_mb / 1024); perf_cell("/ %.1f GB", s.ram_total_mb / 1024);
        perf_cell("game %.2f GB", s.ram_game_mb / 1024);
        ImGui::TableNextColumn();
        ImGui::TableNextColumn(); ImGui::TextColored(fps_c, "FPS");
        perf_cell("%.0f", s.fps); perf_cell("%.1f ms", s.frame_ms_avg); perf_cell("1%% %.1f ms", s.frame_ms_low1);
        perf_cell("max %.1f ms", s.frame_ms_max);
        ImGui::EndTable();
    }
    float top = s.frame_ms_max > 50 ? s.frame_ms_max : 50;
    ImGui::PlotLines("##ft", s.frame_ms, PERF_HISTORY, 0, NULL, 0, top, ImVec2(360 * scale, 48 * scale));
    ImGui::TextDisabled("%s", s.gpu_name[0] ? s.gpu_name : "GPU");
    ImGui::TextDisabled("%s", s.cpu_name);
    ImGui::End();
    ImGui::PopStyleVar();
}

static bool g_inited;
static ImGuiContext *g_ctx;  // ours: the start screen (back to it after a reboot) has its own context
static ImFont *g_font, *g_font_big;
static ImFont *g_menu_font, *g_menu_font_big;  // the menu window (Baloo 2); everything else keeps g_font
static int g_tab, g_tab_request = -2;  // (-2: no request; -1 is the Prelaunch tab)
static int g_focus_tab = -99;  // put the nav cursor on this tab next frame (-100: the selected one; -99: none)
static int g_focus_frames;

// The start screen's Settings opening: the controller's cursor starts on the first tab the first time in a session,
// later on the tab that's selected
void menu_tabs_focus(bool first_tab) { g_focus_tab = first_tab ? -1 : -100, g_focus_frames = 0; }
int g_tab_request_ext = -1;

static void style_init(void) {
    ImGuiStyle &s = ImGui::GetStyle();
    ImGui::StyleColorsDark();
    s.WindowRounding = 14; s.FrameRounding = 8; s.GrabRounding = 8; s.TabRounding = 8; s.ChildRounding = 10;
    s.WindowPadding = ImVec2(28, 24); s.FramePadding = ImVec2(14, 8); s.ItemSpacing = ImVec2(14, 12);
    s.WindowBorderSize = 0; s.ScrollbarSize = 18;
    ImVec4 *c = s.Colors;
    ImVec4 gold(0.93f, 0.76f, 0.33f, 1), gold_dim(0.62f, 0.49f, 0.20f, 1), green(0.15f, 0.36f, 0.25f, 1);
    c[ImGuiCol_WindowBg] = ImVec4(0.06f, 0.09f, 0.08f, 0.94f);
    c[ImGuiCol_ChildBg] = ImVec4(0.09f, 0.13f, 0.11f, 0.85f);
    c[ImGuiCol_PopupBg] = ImVec4(0.07f, 0.10f, 0.09f, 0.98f);
    c[ImGuiCol_Text] = ImVec4(0.96f, 0.94f, 0.88f, 1);
    c[ImGuiCol_TextDisabled] = ImVec4(0.62f, 0.64f, 0.58f, 1);
    c[ImGuiCol_FrameBg] = ImVec4(0.13f, 0.19f, 0.16f, 1);
    c[ImGuiCol_FrameBgHovered] = green;
    c[ImGuiCol_FrameBgActive] = ImVec4(0.19f, 0.45f, 0.31f, 1);
    c[ImGuiCol_Button] = ImVec4(0.14f, 0.22f, 0.18f, 1);
    c[ImGuiCol_ButtonHovered] = green;
    c[ImGuiCol_ButtonActive] = ImVec4(0.21f, 0.50f, 0.34f, 1);
    c[ImGuiCol_Header] = green;
    c[ImGuiCol_HeaderHovered] = ImVec4(0.19f, 0.45f, 0.31f, 1);
    c[ImGuiCol_HeaderActive] = ImVec4(0.21f, 0.50f, 0.34f, 1);
    c[ImGuiCol_Tab] = ImVec4(0.12f, 0.18f, 0.15f, 1);
    c[ImGuiCol_TabHovered] = green;
    c[ImGuiCol_TabSelected] = ImVec4(0.21f, 0.44f, 0.31f, 1);
    c[ImGuiCol_TabSelectedOverline] = gold;
    c[ImGuiCol_CheckMark] = gold;
    c[ImGuiCol_SliderGrab] = gold_dim;
    c[ImGuiCol_SliderGrabActive] = gold;
    c[ImGuiCol_NavCursor] = gold;
    c[ImGuiCol_Separator] = ImVec4(0.30f, 0.36f, 0.30f, 1);
    c[ImGuiCol_TitleBg] = c[ImGuiCol_TitleBgActive] = c[ImGuiCol_WindowBg];
}


#ifdef __APPLE__
static void init(id<MTLDevice> dev) {
#else
static void init(void) {
#endif
    IMGUI_CHECKVERSION();
    g_ctx = ImGui::CreateContext();
    ImGui::SetCurrentContext(g_ctx);
    ImGuiIO &io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard | ImGuiConfigFlags_NavEnableGamepad;
    io.BackendFlags |= ImGuiBackendFlags_HasGamepad;
    io.IniFilename = NULL;
    ImFontConfig cfg;
    cfg.OversampleH = 2;
    const char *paths[] = {"/System/Library/Fonts/Avenir Next.ttc", "/System/Library/Fonts/Helvetica.ttc",
                           "C:/Windows/Fonts/segoeui.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                           "/usr/share/fonts/TTF/DejaVuSans.ttf", "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf"};
    for (const char *p : paths) {
        if (FILE *f = fopen(p, "rb")) fclose(f);  // a missing file is an assertion in ImGui, not a NULL return
        else continue;
        if (!g_font) g_font = io.Fonts->AddFontFromFileTTF(p, 34, &cfg);
        if (g_font && !g_font_big) { ImFontConfig b = cfg; b.FontNo = 0; g_font_big = io.Fonts->AddFontFromFileTTF(p, 56, &b); }
    }
    // the menu window itself: Baloo 2 SemiBold, as on the start screen (shipped, OFL), at its Settings window's sizes; the
    // FPS counter, overlays and on-screen keyboard keep the fonts above
    char baloo[1024];
    if (const char *f = getenv("LARECOMP_MENU_FONT")) strlcpy(baloo, f, sizeof baloo);  // (test) another weight / face
    bool have_baloo = getenv("LARECOMP_MENU_FONT") || rt_resource("Baloo2-SemiBold.ttf", "fonts/Baloo2-SemiBold.ttf", baloo, sizeof baloo);
    // 简体中文界面：Baloo 2 与 Segoe UI 都没有汉字，菜单改用系统中文字体，字形按界面实际用到的字生成
    const char *zh_fonts[] = {getenv("SKYRECOMP_ZH_FONT") ? getenv("SKYRECOMP_ZH_FONT") : "",
                              "C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/msyhbd.ttc",
                              "C:/Windows/Fonts/simhei.ttf", "/System/Library/Fonts/PingFang.ttc",
                              "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
                              "fonts/NotoSansSC-Regular.ttf", "fonts/msyh.ttc"};
    const char *zf = NULL;
    for (const char *p : zh_fonts) {
        if (!*p) continue;
        FILE *f = fopen(p, "rb");
        if (!f) continue;
        fclose(f);
        zf = p;
        break;
    }
    static ImVector<ImWchar> zh_ranges;
    if (zf && zh_ranges.empty()) {
        ImFontGlyphRangesBuilder b;
        b.AddRanges(io.Fonts->GetGlyphRangesDefault());
        b.AddText(ZH_UI_GLYPHS);
        b.BuildRanges(&zh_ranges);
        io.Fonts->TexDesiredWidth = 4096;
    }
    if (zf) {  // (中文比 Baloo 的视觉字号大，所以标称字号略收一点；覆盖层字体也换掉，免得个别页面缺字)
        ImFontConfig zc = cfg;
        g_menu_font = io.Fonts->AddFontFromFileTTF(zf, ZH_MENU_PX, &zc, zh_ranges.Data);
        g_menu_font_big = io.Fonts->AddFontFromFileTTF(zf, ZH_MENU_PX_BIG, &zc, zh_ranges.Data);
        g_font = io.Fonts->AddFontFromFileTTF(zf, ZH_OVERLAY_PX, &zc, zh_ranges.Data);
        ImFontConfig b2 = zc;
        b2.FontNo = 0;
        g_font_big = io.Fonts->AddFontFromFileTTF(zf, ZH_OVERLAY_PX_BIG, &b2, zh_ranges.Data);
    }
    if (have_baloo && (!g_menu_font || !g_menu_font_big)) {  // (没找到中文字体：沿用 Baloo 2)
        if (!g_menu_font) g_menu_font = io.Fonts->AddFontFromFileTTF(baloo, 39, &cfg);
        if (!g_menu_font_big) g_menu_font_big = io.Fonts->AddFontFromFileTTF(baloo, 72, &cfg);
    }
    if (!g_font) g_font = io.Fonts->AddFontDefault();
    if (!g_font_big) g_font_big = g_font;
    if (!g_menu_font || !g_menu_font_big) g_menu_font = g_font, g_menu_font_big = g_font_big;
    style_init();
#ifdef __APPLE__
    ImGui_ImplMetal_Init(dev);
#else
    vk_imgui_backend_init();
#endif
    g_inited = true;
}

static void drain_events(ImGuiIO &io) {
    pthread_mutex_lock(&q_lock);
    std::vector<QEvent> ev;
    ev.swap(q_events);
    pthread_mutex_unlock(&q_lock);
    for (const QEvent &q : ev) {
        switch (q.kind) {
        case QEvent::KEY: io.AddKeyEvent(q.key, q.down); break;
        case QEvent::ANALOG: io.AddKeyAnalogEvent(q.key, q.value > 0.1f, q.value); break;
        case QEvent::MOUSE_POS: io.AddMousePosEvent(q.x, q.y); break;
        case QEvent::MOUSE_BUTTON: io.AddMouseButtonEvent(q.button, q.down); break;
        case QEvent::WHEEL: io.AddMouseWheelEvent(q.x, q.y); break;
        case QEvent::TEXT: io.AddInputCharactersUTF8(q.text); break;
        }
    }
}

// Section header in the big font.
static void header(const char *t) {
    ImGui::PushFont(g_font_big);
    ImGui::TextColored(ImVec4(0.93f, 0.76f, 0.33f, 1), "%s", t);
    ImGui::PopFont();
    ImGui::Separator();
    ImGui::Spacing();
}

static void hint(const char *t) {
    ImGui::PushTextWrapPos(0);
    ImGui::TextDisabled("%s", t);
    ImGui::PopTextWrapPos();
}

// A row with a label on the left and a choice of options on the right (dpad left/right cycles).
// reserve: room kept free right of the combo (a button on the same line)
static bool choice(const char *label, int *value, const char *const *names, int n, float reserve = 0) {
    ImGui::PushID(label);
    ImGui::AlignTextToFramePadding();
    ImGui::TextUnformatted(label);
    ImGui::SameLine(ImGui::GetContentRegionAvail().x * 0.45f);
    bool changed = false;
    ImGui::SetNextItemWidth(reserve > 0 ? -reserve : -1);
    if (ImGui::BeginCombo("##c", names[*value])) {
        for (int i = 0; i < n; i++) {
            if (ImGui::Selectable(names[i], i == *value)) { *value = i; changed = true; }
            if (i == *value) ImGui::SetItemDefaultFocus();
        }
        ImGui::EndCombo();
    }
    if (ImGui::IsItemFocused() && !ImGui::IsPopupOpen("##c")) {
        if (ImGui::IsKeyPressed(ImGuiKey_GamepadDpadRight) || ImGui::IsKeyPressed(ImGuiKey_RightArrow)) {
            *value = (*value + 1) % n; changed = true;
        }
        if (ImGui::IsKeyPressed(ImGuiKey_GamepadDpadLeft) || ImGui::IsKeyPressed(ImGuiKey_LeftArrow)) {
            *value = (*value + n - 1) % n; changed = true;
        }
    }
    ImGui::PopID();
    return changed;
}

static bool toggle(const char *label, bool *v) {
    const char *names[] = {"关", "开"};
    int i = *v;
    bool ch = choice(label, &i, names, 2);
    *v = i;
    return ch;
}

static bool slider(const char *label, float *value, float min, float max, const char *fmt) {
    ImGui::PushID(label);
    ImGui::AlignTextToFramePadding();
    ImGui::TextUnformatted(label);
    ImGui::SameLine(ImGui::GetContentRegionAvail().x * 0.45f);
    ImGui::SetNextItemWidth(-1);
    bool changed = ImGui::SliderFloat("##s", value, min, max, fmt);
    ImGui::PopID();
    return changed;
}

extern "C" void renderer_get_scale(float *sx, float *sy);
extern "C" int input_pad_family(void);  // runtime/hle/input.c
extern "C" bool input_pad_connected(void);
extern "C" double output_scale_dynamic_factor(void);

static void tab_display(void) {
    float scale = ImGui::GetFontSize() / 34;
    opt_begin("##video", scale);
    opt_section("显示");
    const char *aspects[] = {"自由", "原始 16:9"};
    opt_choice("画面比例", &g_settings.aspect, aspects, 2, ASPECT_UNLOCKED,
               "自由：画面铺满窗口，窗口越宽（或越高）就能看到越多岛屿，最宽可到超宽屏；房屋与迷宫保持原有构图。原始 16:9：保持游戏本身的构图，四周留黑边。");
    bool fs = g_settings.fullscreen;
    if (opt_toggle("全屏", &fs, false, "铺满屏幕。也可用 F11、Alt+Enter 或 Cmd+Ctrl+F。")) {
        g_settings.fullscreen = fs;
        g_want_fullscreen_apply.store(true);
    }
    static const char *const perf_names[] = {"关", "FPS", "完整"};
    if (opt_choice("性能覆盖层", &g_settings.perf_overlay, perf_names, 3, PERF_OFF,
                   "显示在右上角。FPS：帧率与帧时间。完整：另外显示 GPU、CPU、内存占用、温度、显存与帧时间曲线，便于跑分。游戏中按 F10 切换。"))
        settings_save();
    if (g_is_skyward) {
        const char *rates[] = {"60 帧", "120 帧（实验性）"};
        int rate = g_settings.frame_rate == 120;
        if (opt_choice("帧率", &rate, rates, 2, 0,
                       "在保持游戏速度不变的前提下设定渲染目标帧率。120 帧需要更强的硬件和支持高刷新率的显示器。"))
            g_settings.frame_rate = rate ? 120 : 60;
    }

    opt_section("渲染");
#ifndef __APPLE__
    opt_toggle("4K 纹理", &g_settings.hd_textures, true,
               "全程使用随附的高分辨率纹理。关闭则使用原始纹理。改动立即生效，无需重启。");
#endif
#ifdef _WIN32
    if (opt_toggle("ReShade", &g_settings.reshade, true,
               "启用随附的光影与色彩效果。关闭会在游玩时停用效果，并在下次启动时不再加载 ReShade。若以关闭状态启动后想要启用，请关闭并重新打开程序。"))
        settings_save();
#endif
    // display order -> RES_* (the ini / enum order predates the menu order)
    // (up to 4x: 7680 x 4320, 8K - more only ran out of GPU memory, and sat next to 75% in the list)
    // (Match display in the middle: left from it 75% / 50% / 25%, right Dynamic then 1x-4x; user 2026-10-11)
    static const char *res[] = {"25%", "50%", "75%", "匹配显示器", "动态", "1x", "2x", "3x", "4x"};
    static const int res_mode[] = {RES_Q25, RES_Q50, RES_Q75, RES_MATCH, RES_DYNAMIC, 1, 2, 3, 4};
    enum { RES_MATCH_AT = 3 };
    enum { NRES = sizeof res_mode / sizeof res_mode[0] };
    {
        int ri = RES_MATCH_AT;
        for (int i = 0; i < NRES; i++) if (res_mode[i] == g_settings.res_mode) ri = i;
        float sx, sy;
        renderer_get_scale(&sx, &sy);
        char d[400];
        int n = snprintf(d, sizeof d, "3D 画面的清晰程度。匹配显示器：使用屏幕自身分辨率。动态：在不掉帧的前提下尽可能锐利。1x-4x：Switch 的 1080p 乘以该倍数。75%% / 50%% / 25%%：按显示器的比例渲染，适合较慢的机器。\n\n当前渲染分辨率 %.0f x %.0f。", 1920.0 * sx, 1080.0 * sy);
        if (g_settings.res_mode == RES_DYNAMIC)
            snprintf(d + n, sizeof d - n, " 动态：当前为显示器的 %.0f%%。", output_scale_dynamic_factor() * 100);
        if (opt_choice("内部渲染分辨率", &ri, res, NRES, RES_MATCH_AT, d, false)) g_settings.res_mode = res_mode[ri];
    }
    {   // each OS's own upscaler next to bilinear (UPSCALE_SHARP: MetalFX on macOS, AMD FSR 1 on Windows)
#ifdef __APPLE__
        static const char *ups[] = {"双线性", "MetalFX"};
        const char *ud = "画面以较低分辨率渲染时，如何放大到窗口尺寸。MetalFX：Apple 的放大技术，更锐利。双线性：简单柔和。";
        int ui = g_settings.upscaler == UPSCALE_BILINEAR ? 0 : 1;
#else
        static const char *ups[] = {"双线性", "AMD FSR 1", "NVIDIA NIS"};
        const char *ud = "画面以较低分辨率渲染时，如何放大到窗口尺寸。AMD FSR 1：AMD FidelityFX 的边缘感知放大与锐化。NVIDIA NIS：NVIDIA Image Scaling，带方向性 6 抽头滤波与自适应锐化。双线性：简单柔和。";
        int ui = g_settings.upscaler == UPSCALE_BILINEAR ? 0 : g_settings.upscaler == UPSCALE_NIS ? 2 : 1;
#endif
        char udm[512];
        if (g_settings.res_mode == RES_MATCH) {  // (renders at the window's size: nothing to scale up)
            snprintf(udm, sizeof udm, "%s\n\n在「匹配显示器」下不使用此项：游戏本身就按显示器分辨率渲染。", ud);
            ud = udm;
            opt_disable_next();
        }
#ifdef __APPLE__
        if (opt_choice("放大方式", &ui, ups, 2, 1, ud)) g_settings.upscaler = ui ? UPSCALE_SHARP : UPSCALE_BILINEAR;
#else
        if (opt_choice("放大方式", &ui, ups, 3, 1, ud)) g_settings.upscaler = ui == 2 ? UPSCALE_NIS : ui == 1 ? UPSCALE_FSR1 : UPSCALE_BILINEAR;
#endif
    }
    static const char *aa[] = {"关", "SMAA", "FXAA"};  // AA_* order
    opt_choice("抗锯齿", &g_settings.antialias, aa, 3, AA_OFF,
               "在画面放大到窗口之前，先平滑游戏图像边缘的锯齿。SMAA：只沿检测到的边缘混合，纹理保持锐利。FXAA：能平滑更多边缘（含细线与曲线），但整体会略微变软。两者在较低的内部渲染分辨率下最有用；想要最干净的画面，请把内部渲染分辨率调到高于显示器分辨率（超采样）。");
    {
        static const char *af[] = {"游戏", "2x", "4x", "8x", "16x"};
        static const int af_level[] = {0, 2, 4, 8, 16};
        int ai = 0;
        for (int i = 0; i < 5; i++) if (af_level[i] == g_settings.aniso) ai = i;
        if (opt_choice("各向异性过滤", &ai, af, 5, 0,
                       "让以很小夹角看到的纹理（伸向远处的小路、地面与墙面）保持清晰，而不是糊成一片。游戏：使用游戏请求的等级。16x：最锐利，在多数显卡上开销很小。"))
            g_settings.aniso = af_level[ai];
    }
    static const char *shc[] = {"混合", "等待", "异步"};  // SHADERS_* order
    opt_choice("着色器编译（实验性）", &g_settings.shader_compile, shc, 3, SHADERS_HYBRID,
               "第一次需要新着色器时如何处理。混合：每帧都要绘制的画面稍后出现，而不是卡住游戏；阴影等会被复用的图像仍然等待，因此不会出错。等待：全部等待，可能出现卡顿。异步：都不等待，阴影在重绘前可能缺失。");
    opt_end();
}

static void amiibo_rows(void) {
    pthread_mutex_lock(&amiibo_lock);
    if (amiibo_pick[0]) {
        amiibo_import(amiibo_pick, amiibo_msg, sizeof amiibo_msg);
        amiibo_pick[0] = 0;
    }
    pthread_mutex_unlock(&amiibo_lock);
    bool have = amiibo_loaded();
    char d[400];
    snprintf(d, sizeof d, "在法伊菜单中，「使用 amiibo」会立刻识别你的塞尔达与飞鸟 amiibo：在地面时法伊会送你上天，在天上时则送回你离开的位置。需要你自己手办的转储文件，请在下方载入。%s%s", amiibo_msg[0] ? "\n\n" : "", amiibo_msg);
    if (!have) opt_disable_next();
    opt_toggle("塞尔达与飞鸟 amiibo", &g_settings.amiibo, true, d);
    snprintf(d, sizeof d, "选择你自己塞尔达与飞鸟 amiibo 的转储文件（用 TagMo 等手机 NFC 应用生成的 .bin）。副本会保存在游戏数据目录中，程序只从中读取手办 ID。%s%s",
             amiibo_msg[0] ? "\n\n" : "", amiibo_msg);
    if (opt_button(have ? "载入其他 amiibo 转储" : "载入 amiibo 转储", d)) g_amiibo_dialog = true;
}


// Gameplay: the game's text language, difficulty, accessibility and the Zelda & Loftwing amiibo
static void tab_gameplay(void) {
    opt_begin("##gameplay", ImGui::GetFontSize() / 34);
    opt_section("游戏");
    const char *names[N_LANGUAGES];
    for (int i = 0; i < N_LANGUAGES; i++) names[i] = g_language_names[i];
    int lang = g_settings.language;
    if (opt_choice("语言", &lang, names, N_LANGUAGES, LANG_AUTO,
                   "游戏的文本语言。更改语言需要重启游戏以重新载入文本包。")) {
        g_settings.language = lang;
        settings_save();
    }
    if (settings_language_pending()) {
        if (opt_button("重启以应用语言",
                       "立即重启游戏，按所选语言重新加载文本。上次存档之后的进度会丢失。")) {
            settings_save();
            rt_request_reboot(RT_REBOOT_GAME);
            set_open(false);
        }
    }
    opt_section("难度");
    difficulty_rows();
    opt_section("林克");
    link_rows();
    opt_section("飞鸟");
    loftwing_rows();
    opt_section("掉落");
    drop_rows();
    opt_section("辅助功能");
    static const char *const cb[] = {"关", "红色弱（protan）", "绿色弱（deutan）", "蓝色弱（tritan）"};
    opt_choice("色盲模式", &g_settings.colorblind, cb, 4, COLORBLIND_OFF,
               "针对常见的各类色觉异常，把你难以区分的颜色偏移成能够区分的颜色（色觉矫正）。作用于整个游戏画面。");
    opt_section("amiibo");
    amiibo_rows();
    opt_end();
}

// Cosmetics: tunic / heart colours, live (runtime/nvn/texpatch.c); never part of a seed
__attribute__((unused)) static void tab_cosmetics(void) {
    opt_begin("##cosmetics", ImGui::GetFontSize() / 34);
    opt_section("颜色");
    opt_choice("服装颜色", &g_settings.tunic, g_tunic_colours, N_TUNIC_COLOURS, 0,
               "林克衣服的颜色。默认：游戏本来的颜色（随机化模式下则取该种子的设定）。");
    opt_choice("心的颜色", &g_settings.hearts, g_heart_colours, N_HEART_COLOURS, 0,
               "界面心数图标的颜色。");
    if (opt_action("随机配色", "", "随机挑选服装颜色与心的颜色（「默认」之外的任意颜色）。")) {
        g_settings.tunic = (g_settings.tunic + 1 + rand() % (N_TUNIC_COLOURS - 1)) % N_TUNIC_COLOURS;
        g_settings.hearts = (g_settings.hearts + 1 + rand() % (N_HEART_COLOURS - 1)) % N_HEART_COLOURS;
    }
    opt_end();
}

static void tab_audio(void) {
    opt_begin("##audio", ImGui::GetFontSize() / 34);
    opt_section("声音");
    float pct = roundf(g_settings.volume * 100);
    if (opt_slider("音量", &pct, 0, 200, 5, 100, "%g%%",
                   "游戏音量。100% 为游戏原始音量，高于此值会更响。"))
        g_settings.volume = pct / 100.0f;
    opt_toggle("房间混响", &g_settings.reverb, true,
               "游戏在洞穴、迷宫与大房间中的回响。");
    opt_toggle("影片音频", &g_settings.movie_audio, true,
               "游戏影片（片头与结局）的声音。下次影片播放时生效。");
    opt_end();
}

// Quit: back to the start screen (in game: the game reboots to it) or out to the desktop. Each asks first (progress
// since the last save is lost); B / Esc or Cancel backs out.
extern "C" void rt_request_reboot(int kind);  // runtime/main.c (RT_REBOOT_TITLE = 2: the start screen)
static void tab_quit(float scale, bool in_game) {
    static int ask;  // 0: the two choices; 1: start screen?; 2: desktop?
    if (ask && (ImGui::IsKeyPressed(ImGuiKey_GamepadFaceRight, false) || ImGui::IsKeyPressed(ImGuiKey_Escape, false)))
        ask = 0;
    const char *lost = in_game ? "\n\nProgress since your last save is lost." : "";
    char d1[200], d2[200];
    snprintf(d1, sizeof d1, "离开游戏并回到 Sky Recomp 启动界面。%s", lost);
    snprintf(d2, sizeof d2, "关闭 Sky Recomp。%s", lost);
    opt_begin("##quit", scale);
    opt_section("退出");
    if (!ask) {
        if (!in_game) opt_disable_next();  // (already on it)
        if (opt_action("退回启动界面", "", in_game ? d1 : "你当前已在启动界面。")) ask = 1;
        if (opt_action("退出到桌面", "", d2)) ask = 2;
    } else {
        if (opt_action(ask == 1 ? "是，退回启动界面" : "是，退出到桌面", "", ask == 1 ? d1 : d2)) {
            settings_save();
            if (ask == 1) {
                rt_request_reboot(2);
                set_open(false);
            } else {
                SDL_Event q = {};
                q.type = SDL_EVENT_QUIT;
                SDL_PushEvent(&q);
            }
            ask = 0;
        }
        if (opt_action("取消", "", "保持当前状态。")) ask = 0;
    }
    opt_end();
}

static void tab_about(void) {
    header("移动");
    toggle("用十字键移动林克", &g_settings.dpad_move);
    toggle("自由视角", &g_settings.free_cam);
    hint("无需先按住 L，推右摇杆即可环视。短按 L 可在本次会话中开/关；按住 L 时右下角眼睛图标亮起，表示按住期间关闭自由视角，此时右摇杆恢复挥剑。右下角的眼睛图标显示当前状态。锁定（ZL）、道具（ZR）与布袋（R）仍保持右摇杆原有行为。");
    if (g_settings.free_cam) {
        slider("自由视角灵敏度", &g_settings.free_cam_sens, 0.25f, 2.0f, "%.2fx");
        hint("自由视角开启时右摇杆转动镜头的速度（1.00x = 游戏原速）。");
        toggle("鼠标视角与战斗", &g_settings.mouse_controls);
        if (g_settings.mouse_controls) {
            slider("鼠标灵敏度", &g_settings.mouse_sens, 0.25f, 4.0f, "%.2fx");
            hint("移动鼠标即可环视。左键：挥剑（点击前先移动可决定方向）。右键：锁定 / 盾击。中键：突刺。按住左 Alt 或鼠标 4 号键进入道具瞄准：左键准备 / 使用所选道具；按住再松开可射箭。按住 3：道具轮盘。鼠标 5 号键或 E：布袋。K 仍可交互。Esc 释放鼠标。显式绑定的鼠标按键优先。");
        }
    }
    slider("陀螺仪灵敏度", &g_settings.gyro_sens, 0.1f, 2.0f, "%.2fx");
    hint("转动带陀螺仪的手柄时准星移动的幅度（弓、弹弓、第一人称视角）。1.00x = 手柄本身的动作幅度；若准星太飘可以调低。");
    ImGui::Spacing();
    header("按键提示");
    {
        static const char *const fam[] = {"Nintendo", "Xbox", "PlayStation"};
        char autol[64];
        snprintf(autol, sizeof autol, "自动（%s）", input_pad_connected() ? fam[input_pad_family() % 3] : "键盘");
        const char *names[] = {autol, "Nintendo", "Xbox", "PlayStation", "键盘"};
        choice("按键图标", &g_settings.prompts, names, 5);
        static const char *const looks[] = {"浅色（同游戏本体）", "深色"};
        choice("按键外观", &g_settings.prompt_look, looks, 2);
    }
    hint("Xbox、PlayStation 与键盘图标：使用和游戏本体一致的浅色按键，或使用深色按键。");
    ImGui::Spacing();
    header("按键设置");
    controls_bindings_draw(ImGui::GetFontSize() / 34);
    ImGui::Spacing();
    header("菜单");
    ImGui::TextUnformatted("打开/关闭本菜单：F1、Esc、手柄的 Home / Xbox / PlayStation 键，或 Back + Start");
    ImGui::TextUnformatted("切换标签：L / R（Q / E）        返回：B（Esc）");
    ImGui::TextUnformatted("全屏：F11 / Alt+Enter");
}

extern "C" bool inventory_overlay_wanted(void);
extern "C" bool tracker_overlay_wanted(void);
extern "C" void tracker_overlay_draw(ImVec2 display, ImFont *font);
extern "C" bool chaos_overlay_wanted(void);
extern "C" void chaos_overlay_draw(ImVec2 display, ImFont *font);
extern "C" void inventory_overlay_draw(ImVec2 display, ImFont *font);

// Reboot (runtime/main.c): the game is gone - menu and name dialog close; the ImGui context stays.
RT_ON_RESET(menu_reset) {
    set_open(false);
    g_kbd = 0;
    osk_cancel();
    pthread_mutex_lock(&q_lock);
    q_events.clear();
    pthread_mutex_unlock(&q_lock);
}

static void keyboard_draw(ImGuiIO &io, float scale) {
    ImGui::GetBackgroundDrawList()->AddRectFilled(ImVec2(0, 0), io.DisplaySize, IM_COL32(0, 0, 0, 120));
    float w = fminf(io.DisplaySize.x * 0.9f, 1100 * scale);
    ImGui::SetNextWindowPos(ImVec2(io.DisplaySize.x * 0.5f, io.DisplaySize.y * 0.5f), ImGuiCond_Always, ImVec2(0.5f, 0.5f));
    ImGui::SetNextWindowSize(ImVec2(w, 0), ImGuiCond_Always);
    ImGui::Begin("##kbd", NULL, ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoSavedSettings |
                                    ImGuiWindowFlags_AlwaysAutoResize);
    ImGui::PushFont(g_font_big);
    ImGui::TextColored(ImVec4(0.93f, 0.76f, 0.33f, 1), "输入名称");
    ImGui::PopFont();
    static bool was_open, was_pad;
    bool pad = g_last_pad.load(), appearing = !was_open || pad != was_pad;  // (switching device: focus the new one)
    was_open = true, was_pad = pad;
    if (!pad) {  // keyboard: type straight into the field
        if (appearing) ImGui::SetKeyboardFocusHere();
        ImGui::SetNextItemWidth(-1);
        ImGui::PushFont(g_font_big);
        ImGui::InputText("##name", g_kbd_text, (size_t)(g_kbd_max * 4 + 1 < (int)sizeof g_kbd_text ? g_kbd_max * 4 + 1 : sizeof g_kbd_text),
                         ImGuiInputTextFlags_CallbackCharFilter,
                         [](ImGuiInputTextCallbackData *d) -> int { return d->EventChar < 0x20 ? 1 : 0; });
        ImGui::PopFont();
        if ((int)strlen(g_kbd_text) > g_kbd_max) g_kbd_text[g_kbd_max] = 0;
        ImGui::TextDisabled("回车 确认      Esc 取消      (%d / %d)", (int)strlen(g_kbd_text), g_kbd_max);
    } else {  // controller: on-screen keyboard (osk.mm, shared with our menus' text fields)
        int r = osk_keys(g_kbd_text, sizeof g_kbd_text, g_kbd_max, appearing, scale, g_font_big);
        if (r) g_kbd = r > 0 ? 2 : 3;  // (Start / + confirms in menu_handle_event too)
    }
    ImGui::End();
    if (g_kbd.load() != 1) was_open = false;
}

// Game thread (runtime/hle/swkbd.c): show the dialog, re-present the last frame until it's answered.
// Returns 1 confirmed (out = text, UTF-8), 0 cancelled.
extern "C" int menu_keyboard_run(const char *initial, int max_len, char *out, int cap) {
    extern void backend_represent(void);
    snprintf(g_kbd_text, sizeof g_kbd_text, "%s", initial ? initial : "");
    g_kbd_max = max_len > 0 && max_len < (int)sizeof g_kbd_text / 4 ? max_len : 8;
    input_reset();
    g_kbd = 1;
    // (test) LARECOMP_KBD_AUTO=<text>: answer at once
    if (getenv("LARECOMP_KBD_AUTO")) { snprintf(g_kbd_text, sizeof g_kbd_text, "%s", getenv("LARECOMP_KBD_AUTO")); g_kbd = 2; }
    while (g_kbd.load() == 1 && !g_rt_unwind) {  // ~60 Hz (a reboot cancels)
        uint64_t t0 = SDL_GetTicks();
        backend_represent();
        uint64_t dt = SDL_GetTicks() - t0;
        if (dt < 16) SDL_Delay((uint32_t)(16 - dt));
    }
    bool ok = g_kbd.load() == 2 && g_kbd_text[0];
    if (ok) snprintf(out, cap, "%s", g_kbd_text);
    g_kbd = 0;
    input_reset();
    return ok;
}

extern void tab_mods(float scale);

// The tab bar and its pages, into the current window: the in-game menu, and the start screen's Settings (in_game
// false: nothing of the game is loaded yet - the tabs that need it are greyed out; prelaunch: the start screen's own
// first tab, game files and fonts, drawn by launcher.mm).
static void tabs_body(float scale, bool in_game, void (*prelaunch)(float)) {
    // (id: the page; -1 = Prelaunch)
    struct Tab { const char *name; int id; bool on; };
    Tab tabs[12];
    int ntabs = 0;
    if (prelaunch) tabs[ntabs++] = {"启动前", -1, true};
    static const char *names[] = {"画面", "音频", "存档编辑", "随机化", "传送", "作弊", "玩法",
                                  "外观", "按键设置", "退出", "Mod"};
    static const int order[] = {8, 0, 1, 6, 5, 9};  // Controls, Video, Audio, Gameplay, Cheats, Quit (Mods: hidden for now)
    for (int i : order)  // (Quit: in game only - the start screen has its own QUIT)
        if (i != 9 || !prelaunch) tabs[ntabs++] = {names[i], i, true};
    int cur = 0;  // g_tab / g_tab_request hold ids
    for (int i = 0; i < ntabs; i++) if (tabs[i].id == g_tab) cur = i;
    if (!tabs[cur].on) cur = 0;
    // L/R (or Q/E) switch tabs, skipping greyed-out ones (not while typing: Q / E are letters then, and the on-screen
    // keyboard has the controller)
    if (g_tab_request_ext >= 0) { g_tab_request = g_tab_request_ext; g_tab_request_ext = -1; }
    bool any_popup = ImGui::IsPopupOpen("", ImGuiPopupFlags_AnyPopupId), typing = ui_text_busy();
    static int focused_tab = -99;  // the tab the controller's cursor is on (from the frame before; -99: none)
    if (!any_popup && !typing) {
        int step = ImGui::IsKeyPressed(ImGuiKey_GamepadR1, false) || ImGui::IsKeyPressed(ImGuiKey_E, false) ? 1
                 : ImGui::IsKeyPressed(ImGuiKey_GamepadL1, false) || ImGui::IsKeyPressed(ImGuiKey_Q, false) ? -1 : 0;
        if (step) {
            int i = cur;
            do i = (i + step + ntabs) % ntabs; while (!tabs[i].on);
            g_tab_request = tabs[i].id;
            // the cursor on the tab bar goes along (left behind, A on it switched straight back; user 2026-10-11)
            if (focused_tab != -99) g_focus_tab = tabs[i].id, g_focus_frames = 0;
        }
    }
    // Down with the cursor on the tab bar: the page's first row (option rows; other pages keep ImGui's own pick)
    bool down_from_tab = focused_tab != -99 && ImGui::GetCurrentContext()->NavCursorVisible && !any_popup &&
                         (ImGui::IsKeyPressed(ImGuiKey_GamepadDpadDown) || ImGui::IsKeyPressed(ImGuiKey_GamepadLStickDown) ||
                          ImGui::IsKeyPressed(ImGuiKey_DownArrow));
    opt_focus_first(down_from_tab);
    if (ImGui::BeginTabBar("##tabs", ImGuiTabBarFlags_NoTabListScrollingButtons)) {
        for (int k = 0; k < ntabs; k++) {
            const Tab &t = tabs[k];
            ImGuiTabItemFlags f = g_tab_request == t.id && t.on ? ImGuiTabItemFlags_SetSelected : 0;
            char lbl[64];
            snprintf(lbl, sizeof lbl, prelaunch ? " %s " : "  %s  ", t.name);  // (ten tabs: tighter, so none is cut short)
            ImGui::BeginDisabled(!t.on);  // (out of the game: Save Editor, Warp, Cheats)
            // focus (controller / keyboard): the tab lights up a little with a gold bar along its bottom, instead of
            // ImGui's outline (it sits 4 px outside the tab and the tab bar's clipping could cut its top off on macOS)
            // (focused_tab: from the frame before - colours go in before the tab is drawn)
            bool lit = focused_tab == t.id && ImGui::GetCurrentContext()->NavCursorVisible;
            ImGui::PushStyleColor(ImGuiCol_NavCursor, ImVec4(0, 0, 0, 0));
            if (lit) {
                ImGui::PushStyleColor(ImGuiCol_Tab, ImVec4(0.19f, 0.27f, 0.22f, 1));
                ImGui::PushStyleColor(ImGuiCol_TabHovered, ImVec4(0.19f, 0.27f, 0.22f, 1));
            }
            if (g_focus_tab == -1 && !prelaunch) g_focus_tab = 8;  // (no Prelaunch in game: Controls, the first tab)
            bool focus_here = g_focus_tab == t.id || (g_focus_tab == -100 && t.id == g_tab);
            bool open = ImGui::BeginTabItem(lbl, NULL, f);
            ImGui::PopStyleColor(lit ? 3 : 1);
            if (focus_here) {  // the controller's cursor starts on this tab (SetKeyboardFocusHere skips tabs: no tab stop)
                ImGui::SetFocusID(ImGui::GetItemID(), ImGui::GetCurrentWindow());
                ImGui::SetNavCursorVisible(true);
                // a few frames: the page's child window appearing makes ImGui pick its first widget once it's laid out
                if (++g_focus_frames >= 4) g_focus_tab = -99, g_focus_frames = 0;
                else g_focus_tab = t.id;
            }
            if (lit) {
                ImVec2 a = ImGui::GetItemRectMin(), b = ImGui::GetItemRectMax();
                float h = 4 * scale > 2 ? 4 * scale : 2;
                ImGui::GetWindowDrawList()->AddRectFilled(ImVec2(a.x + 2, b.y - h), ImVec2(b.x - 2, b.y),
                                                          IM_COL32(236, 194, 84, 255));  // (the menu's gold)
            }
            if (ImGui::IsItemFocused()) focused_tab = t.id;
            else if (focused_tab == t.id) focused_tab = -99;
            ImGui::EndDisabled();
            if (open) {
                g_tab = t.id;
                ImGui::Spacing();
                ImGui::BeginChild("##page", ImVec2(0, 0), ImGuiChildFlags_None,  // (the rest of the window: no hint line)
                                  ImGuiWindowFlags_NavFlattened);
                // Down from the tab bar, pages that aren't option rows (Prelaunch, Controls): their first control
                // (option-row pages: opt_focus_first)
                if (down_from_tab && (t.id == -1 || t.id == 8 || t.id == 10)) {
                    opt_focus_first(false);
                    ImGui::SetKeyboardFocusHere();
                    ImGui::SetNavCursorVisible(true);
                }
                switch (t.id) {
                case -1: prelaunch(scale); break;
                case 0: tab_display(); break;
                case 1: tab_audio(); break;
                case 6: tab_gameplay(); break;
                case 5: cheats_draw(scale); break;
                case 8: tab_about(); break;
                case 10: tab_mods(scale); break;
                case 9: tab_quit(scale, in_game); break;
                }
                static const char *scroll_test = getenv("LARECOMP_MENU_SCROLL");  // test hook: page scroll, 0..1
                if (scroll_test) ImGui::SetScrollY(ImGui::GetScrollMaxY() * (float)atof(scroll_test));
                ImGui::EndChild();
                ImGui::EndTabItem();
            }
        }
        g_tab_request = -2;
        opt_focus_first(false);  // (a page without option rows: nothing took it)
        ImGui::EndTabBar();
    }
}

void menu_tabs_draw(float scale, ImFont *font, ImFont *font_big, bool in_game, void (*prelaunch)(float)) {
    ImFont *f0 = g_font, *f1 = g_font_big;
    g_font = font, g_font_big = font_big;
    ImGuiStyle saved = ImGui::GetStyle();  // the menu's look (the start screen has its own style)
    style_init();
    ImGui::GetStyle().ScaleAllSizes(scale);
    tabs_body(scale, in_game, prelaunch);
    ImGui::GetStyle() = saved;
    g_font = f0, g_font_big = f1;
}

#ifdef __APPLE__
void menu_render(id<MTLDevice> dev, id<MTLCommandBuffer> cb, id<MTLTexture> target) {
    const double tw = target.width, th = target.height;
#else
void menu_render(void *cmd, uint32_t target_w, uint32_t target_h) {
    const double tw = target_w, th = target_h;
#endif
    bool open = g_open.load();
    bool inv = !open && inventory_overlay_wanted();
    bool trk = !open && tracker_overlay_wanted();
    bool chaos = !open && chaos_overlay_wanted();
    bool kbd = g_kbd.load() == 1;
    if (!open && !kbd && g_settings.perf_overlay == PERF_OFF && !inv && !trk && !chaos && !g_settings.free_cam) {
        if (g_inited) { pthread_mutex_lock(&q_lock); q_events.clear(); pthread_mutex_unlock(&q_lock); }
        return;
    }
#ifdef __APPLE__
    if (!g_inited) init(dev);
#else
    if (!g_inited) init();
#endif
    ImGui::SetCurrentContext(g_ctx);
    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize = ImVec2((float)tw, (float)th);
    io.DisplayFramebufferScale = ImVec2(1, 1);
    static double last;
    double now = SDL_GetTicks() / 1000.0;
    io.DeltaTime = last > 0 && now > last ? (float)(now - last) : 1.0f / 60;
    last = now;
    drain_events(io);
    // fonts are built at 34/56 px for a ~1080 px tall output; scale to the window
    float scale = (float)(th / 1080.0);
    if (scale < 0.45f) scale = 0.45f;
    io.FontGlobalScale = scale;

#ifdef __APPLE__
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = target;
    rp.colorAttachments[0].loadAction = MTLLoadActionLoad;
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
#endif
    // spacing/rounding follow the output size too (style tuned for 1080 p)
    static ImGuiStyle base;
    static float style_scale = -1;
    if (style_scale < 0) base = ImGui::GetStyle();
    if (fabsf(style_scale - scale) > 0.01f) {
        ImGui::GetStyle() = base;
        ImGui::GetStyle().ScaleAllSizes(scale);
        style_scale = scale;
    }
#ifdef __APPLE__
    ImGui_ImplMetal_NewFrame(rp);
#else
    ImGui_ImplVulkan_NewFrame();
#endif
    ImGui::NewFrame();

    if (g_settings.perf_overlay != PERF_OFF) perf_overlay_draw(io, scale);

    if (g_settings.free_cam) {
        // Free camera mode, bottom right, no text: an eye while it is on, a crossed-out eye while L toggled it off.
        ImDrawList *dl = ImGui::GetForegroundDrawList();
        const float s = scale;
        const ImVec2 c(io.DisplaySize.x - 30 * s, io.DisplaySize.y - 28 * s);
        const float rx = 14 * s, ry = 8 * s;
        const bool on = input_free_cam_active();
        const ImU32 line = on ? IM_COL32(240, 235, 220, 80) : IM_COL32(240, 235, 220, 38);
        dl->AddBezierQuadratic(ImVec2(c.x - rx, c.y), ImVec2(c.x, c.y - ry * 1.6f), ImVec2(c.x + rx, c.y), line, 1.5f * s);
        dl->AddBezierQuadratic(ImVec2(c.x - rx, c.y), ImVec2(c.x, c.y + ry * 1.6f), ImVec2(c.x + rx, c.y), line, 1.5f * s);
        dl->AddCircleFilled(c, 3.2f * s, on ? IM_COL32(240, 235, 220, 120) : IM_COL32(240, 235, 220, 55));
        if (!on)
            dl->AddLine(ImVec2(c.x - rx * 0.9f, c.y + ry * 1.2f), ImVec2(c.x + rx * 0.9f, c.y - ry * 1.2f),
                        IM_COL32(240, 235, 220, 90), 1.5f * s);
    }

    if (trk) tracker_overlay_draw(io.DisplaySize, g_font_big ? g_font_big : ImGui::GetFont());
    if (chaos) chaos_overlay_draw(io.DisplaySize, g_font_big ? g_font_big : ImGui::GetFont());
    if (inv) {
        inventory_overlay_draw(io.DisplaySize, g_font_big ? g_font_big : ImGui::GetFont());
    }

    if (open) {
        // dim the game behind the menu
        ImGui::GetBackgroundDrawList()->AddRectFilled(ImVec2(0, 0), io.DisplaySize, IM_COL32(0, 0, 0, 110));
        float w = fminf(io.DisplaySize.x * 0.9f, 1500 * scale), h = io.DisplaySize.y - 2 * 18 * scale;  // (all the height: a slim margin)
        ImGui::SetNextWindowPos(ImVec2(io.DisplaySize.x * 0.5f, io.DisplaySize.y * 0.5f), ImGuiCond_Always, ImVec2(0.5f, 0.5f));
        ImGui::SetNextWindowSize(ImVec2(w, h), ImGuiCond_Always);
        ImGui::Begin("##menu", NULL, ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoSavedSettings);
        ImFont *keep_big = g_font_big;  // (the window in the menu's font; header() uses g_font_big)
        g_font_big = g_menu_font_big;
        ImGui::PushFont(g_menu_font);
        // header as on the start screen's Settings: the title, and a close X in the corner (B / Esc too). ("Title
        // screen" - rt_request_reboot(RT_REBOOT_TITLE) - is to find a new home; user 2026-10-11.)
        ImGui::PushFont(g_font_big);
        ImGui::TextColored(ImVec4(0.93f, 0.76f, 0.33f, 1), "设置");
        ImGui::PopFont();
        {
            float bx = 44 * scale;
            ImGui::SameLine(ImGui::GetWindowWidth() - ImGui::GetStyle().WindowPadding.x - bx);
            ImVec2 p = ImGui::GetCursorScreenPos();
            ImGui::PushStyleColor(ImGuiCol_NavCursor, ImVec4(0, 0, 0, 0));
            bool close = ImGui::InvisibleButton("##close", ImVec2(bx, bx), ImGuiButtonFlags_EnableNav);
            ImGui::PopStyleColor();
            bool hot = ImGui::IsItemHovered() || ImGui::IsItemFocused();
            ImU32 col = hot ? IM_COL32(236, 194, 84, 255) : IM_COL32(220, 216, 205, 255);
            float m = bx * 0.3f, t = (hot ? 3.0f : 2.4f) * scale * 1.5f;
            ImDrawList *dl = ImGui::GetWindowDrawList();
            if (hot) dl->AddRectFilled(p, ImVec2(p.x + bx, p.y + bx), IM_COL32(255, 255, 255, 20), 8 * scale);
            dl->AddLine(ImVec2(p.x + m, p.y + m), ImVec2(p.x + bx - m, p.y + bx - m), col, t);
            dl->AddLine(ImVec2(p.x + bx - m, p.y + m), ImVec2(p.x + m, p.y + bx - m), col, t);
            if (close) set_open(false);
        }

        bool any_popup = ImGui::IsPopupOpen("", ImGuiPopupFlags_AnyPopupId), typing = ui_text_busy();  // (before the
        tabs_body(scale, true, NULL);                                                                          //  pages run)
        // B with nothing focused-deeper closes the menu (not the Esc / B that ends typing: typing is from the frame
        // before, so it's still true the frame a field lets go)
        if (!any_popup && !typing && !ui_text_busy() && ImGui::IsWindowFocused(ImGuiFocusedFlags_RootAndChildWindows) &&
            (ImGui::IsKeyPressed(ImGuiKey_GamepadFaceRight, false) || ImGui::IsKeyPressed(ImGuiKey_Escape, false)))
            set_open(false);
        ImGui::PopFont();
        g_font_big = keep_big;
        ImGui::End();
        osk_draw(g_font_big, scale);  // (a text field activated with the controller)
    }

    if (kbd) keyboard_draw(io, scale);
    ImGui::Render();
    g_text_busy = open && ui_text_busy();
#ifdef __APPLE__
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), cb, enc);
    [enc endEncoding];
#else
    ImGui_ImplVulkan_RenderDrawData(ImGui::GetDrawData(), (VkCommandBuffer)cmd);  // inside the window image's rendering
#endif
}
