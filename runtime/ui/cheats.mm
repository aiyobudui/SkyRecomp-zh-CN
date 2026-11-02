// Cheats tab (Skyward Sword HD 1.0.0), from the community's Atmosphere codes for this build (switch-cheats-db, build
// id D824D4B1BBD45D03). Two kinds:
// - code: tools/patches.py SKY_PATCHES ask rt_cheat_*() at the instruction the code patches (stamina drain, Beetle
//   flight timer, Loftwing dash); off, the game's own instruction runs.
// - values topped up every frame: the live save file sits at a fixed spot of the game's static heap arena in main's
//   .bss (the codes' addresses). Each write first checks that the health fields look like a save file, so a layout
//   that differs (the title screen, another build) leaves memory alone.
// Settings persist in larecomp.ini (g_settings.cheat_*).
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "imgui.h"
#include "option_rows.h"

extern "C" {
#include "../hle.h"
#include "../settings.h"
}

#define SAVE_HEALTH 0x7005AF0056ull  // u16 heart capacity, u16 (unused), u16 current health: quarter hearts
#define SAVE_RUPEES 0x7005AEB7B2ull  // u16
static volatile uint16_t &U16(uint64_t a) { return *(volatile uint16_t *)(uintptr_t)a; }
#define PLAYER 0x7001826AD0ull         // dAcPy_c * (Link), null without him
#define PLAYER_VTABLE 0x7001637D28ull  // its vtable (main+0xab3c2c sets it)

extern "C" int rt_cheat_stamina(void) { return g_settings.cheat_stamina; }
extern "C" int rt_cheat_beetle(void) { return g_settings.cheat_beetle; }
extern "C" int rt_cheat_dash(void) { return g_settings.cheat_dash; }

// Once per presented frame (render thread), from save_editor_frame.
extern "C" void cheats_frame(void) {
    if (!g_is_skyward) return;
    if (g_settings.cheat_skyward) {  // the community code's "Lightning Skyward Sword", on Link himself
        uint64_t p = *(volatile uint64_t *)(uintptr_t)PLAYER;
        if (p && *(volatile uint64_t *)(uintptr_t)p == PLAYER_VTABLE) {
            *(volatile uint8_t *)(uintptr_t)(p + 0x446) |= 0x50;  // +0x444 bits 20 / 22: Skyward Strike charged
            *(volatile uint16_t *)(uintptr_t)(p + 0x641E) = 0x120;  // its timer
            *(volatile uint8_t *)(uintptr_t)(p + 0x63B7) = 0x37;
        }
    }
    static int env = -1;  // LARECOMP_CHEATS=hearts,stamina,rupees,beetle: force on for tests (not saved)
    if (env < 0) {
        const char *e = getenv("LARECOMP_CHEATS");
        env = e != NULL;
        if (e) {
            g_settings.cheat_hearts |= strstr(e, "hearts") != NULL;
            g_settings.cheat_stamina |= strstr(e, "stamina") != NULL;
            g_settings.cheat_rupees |= strstr(e, "rupees") != NULL;
            g_settings.cheat_beetle |= strstr(e, "beetle") != NULL;
        }
    }
    uint16_t cap = U16(SAVE_HEALTH), hp = U16(SAVE_HEALTH + 4);
    bool save = cap >= 12 && cap <= 80 && cap % 4 == 0 && hp <= cap;
    static int was = -1;
    if (save != was) LOG("[cheats] save file %s (capacity %u, health %u)\n", save ? "found" : "gone", cap, hp), was = save;
    if (!save) return;
    if (g_settings.cheat_hearts && hp > 0 && hp < cap) U16(SAVE_HEALTH + 4) = cap;  // (0 = defeated: left alone)
    if (g_settings.cheat_rupees && U16(SAVE_RUPEES) < 9900) U16(SAVE_RUPEES) = 9900;
}

extern "C" void cheats_draw(float scale) {
    opt_begin("##cheats", scale);
    opt_section("始终开启");
    if (opt_toggle("无限生命", &g_settings.cheat_hearts, false,
                   "林克受伤后生命会立即回满。\n\n但单次伤害超过其全部心数时仍会被击倒。"))
        settings_save();
    if (opt_toggle("无限耐力", &g_settings.cheat_stamina, false,
                   "耐力槽永不消耗：可以随意冲刺、攀爬与旋转。"))
        settings_save();
    if (opt_toggle("无限卢比", &g_settings.cheat_rupees, false, "卢比数量保持在 9,900。")) settings_save();
    if (opt_toggle("甲虫无限飞行", &g_settings.cheat_beetle, false,
                   "甲虫会一直飞行，直到你把它召回。"))
        settings_save();
    if (opt_toggle("天空斩始终蓄力", &g_settings.cheat_skyward, false,
                   "林克的剑始终保持蓄力：每次竖挥都会放出天空斩，不必先把剑举起。"))
        settings_save();
    if (opt_toggle("无限空中冲刺", &g_settings.cheat_dash, false,
                   "飞鸟的冲刺次数永不耗尽：想冲几次就冲几次。"))
        settings_save();
    if (opt_toggle("敌人必定掉落物品", &g_settings.drop_always, false,
                   "击败的敌人、割草与打碎的罐子必定从可掉落物中给出东西，敌人也必定掉落怪物素材。在「玩法」页里关掉的掉落仍然保持关闭。"))
        settings_save();
    opt_end();
}
