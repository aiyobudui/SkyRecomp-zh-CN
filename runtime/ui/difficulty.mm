// Difficulty (Gameplay tab): damage taken multiplier / one-hit KO, applied where the game
// computes Link's damage (tools/patches.py DAMAGE_SHIFT_SITE; Link's Awakening: DAMAGE_*_SITES, with rt_hero_mode()
// reading its Hero Mode flag, PlayerStatus+0x120 = save 0x55E0). Settings persist in larecomp.ini (g_settings.diff_*).
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "imgui.h"
#include "option_rows.h"

extern "C" {
#include "../hle.h"
#include "../settings.h"
}

#define LIVE_SAVE 0x7001CBB220ull
#define HERO_FLAG (LIVE_SAVE + 0x55E0)  // PlayerStatus (save+0x54C0) + 0x120

extern "C" int rt_hero_mode(void) { return *(volatile uint8_t *)(uintptr_t)HERO_FLAG == 1; }

// damage in quarter hearts before the Hero Mode shift; returns the damage to subtract
extern "C" int32_t rt_damage(int32_t dmg, int32_t shift) {
    static int envd = -1;  // LARECOMP_DAMAGE=<mult> / ohko: test override
    if (envd < 0) {
        const char *e = getenv("LARECOMP_DAMAGE");
        envd = e != NULL;
        if (e) {
            if (!strcmp(e, "ohko")) g_settings.diff_ohko = true;
            else g_settings.diff_damage = (float)atof(e);
        }
    }
    int32_t base = dmg << (shift & 31);
    if (base <= 0) return base;  // healing / zero: untouched
    if (g_settings.diff_ohko) return 999;
    float m = g_settings.diff_damage > 0 ? g_settings.diff_damage : 1.0f;
    int32_t r = (int32_t)lroundf((float)base * m);
    if (ENV("LARECOMP_LOG_DAMAGE")) LOG("[difficulty] damage %d (shift %d) -> %d\n", dmg, shift, r < 1 ? 1 : r);
    return r < 1 ? 1 : r;  // at least a quarter heart
}

// Once per presented frame (from save_editor_frame).
extern "C" void difficulty_frame(void) {}

// Loftwing (tools/patches.py DASH_*_SITE, FLIGHT_SPEED_SITE)
extern "C" uint32_t rt_dash_max(void) { return g_settings.dash_max >= 3 && g_settings.dash_max <= 7 ? g_settings.dash_max : 3; }
extern "C" float rt_flight_speed(void) { return g_settings.flight_speed > 0 ? g_settings.flight_speed : 1.0f; }
extern "C" float rt_walk_speed(void) { return g_settings.walk_speed > 0 ? g_settings.walk_speed : 1.0f; }

// Drops (tools/patches.py DROP_*_SITE: drop table entry kinds; TREASURE_ROLL_SITES: monster materials)
extern "C" int rt_drop_kind(uint32_t kind) {
    if (kind == 1 || kind == 2) return g_settings.drop_hearts;
    if ((kind >= 3 && kind <= 5) || kind == 12 || kind == 13) return g_settings.drop_rupees;
    if (kind >= 7 && kind <= 11) return g_settings.drop_ammo;
    return 1;  // (fairies, keys, Eldin Ore, Farore's Tears, Rupoors: as the game has them)
}

extern "C" int rt_drop_always(uint64_t list) {
    uint64_t table = (list - (MAIN_BASE + 0x164c8f0)) >> 4;  // (not the Heart / Rupee Medals' extra rolls)
    return g_settings.drop_always && table != 0x27 && table != 0x28;
}

extern "C" uint32_t rt_treasure_roll(uint64_t ret, uint32_t won) {
    // tryDropItem's callers that drop an item: Bokoblins (skulls), Chuchus, Keese, Guay, Lizalfos... (+4: return address)
    static const uint32_t item_calls[] = {0x2c782c, 0x2e4de4, 0x2f09f8, 0x3368b4, 0x358ff8, 0x35a350,
                                          0x387e50, 0x38ba34, 0x3a23a8, 0x3b5060, 0x441820};
    for (uint32_t a : item_calls)
        if (ret == MAIN_BASE + a + 4) return !g_settings.drop_treasures ? 0 : g_settings.drop_always ? 1 : won;
    return won;
}

// Gameplay tab rows (menu.mm tab_gameplay), each at the game's own value by default.
extern "C" void difficulty_rows(void) {
    static const char *const names[] = {"一半", "默认", "2x", "3x", "4x", "5x", "6x", "7x", "8x"};
    static const float mult[] = {0.5f, 1, 2, 3, 4, 5, 6, 7, 8};
    int di = 1;  // (the closest step to the setting: older files may hold any multiplier)
    for (int i = 0; i < 9; i++)
        if (fabsf(mult[i] - g_settings.diff_damage) < fabsf(mult[di] - g_settings.diff_damage)) di = i;
    if (opt_choice("受到伤害", &di, names, 9, 1,
                   "敌人对林克造成的伤害：一半、游戏原值，或最多八倍。在此之上还会叠加英雄模式的双倍伤害。")) {
        g_settings.diff_damage = mult[di];
        settings_save();
    }
    if (opt_toggle("一击必杀", &g_settings.diff_ohko, false, "任何攻击都会击倒林克，无视心数。"))
        settings_save();
}

extern "C" void loftwing_rows(void) {
    static const char *const dashes[] = {"3（默认）", "4", "5", "6", "7"};
    int di = rt_dash_max() - 3;
    if (opt_choice("冲刺次数", &di, dashes, 5, 0,
                   "飞鸟一次可用的冲刺次数；仍按原规则逐个回复。\n\n从下次召唤飞鸟起生效，界面上的额外羽翼要等下次启动游戏才会显示。")) {
        g_settings.dash_max = di + 3;
        settings_save();
    }
    static const char *const names[] = {"0.5x", "0.75x", "默认", "1.25x", "1.5x", "2x"};
    static const float mult[] = {0.5f, 0.75f, 1, 1.25f, 1.5f, 2};
    int si = 2;
    for (int i = 0; i < 6; i++)
        if (fabsf(mult[i] - g_settings.flight_speed) < fabsf(mult[si] - g_settings.flight_speed)) si = i;
    if (opt_choice("飞行速度", &si, names, 6, 2,
                   "飞鸟的飞行速度（含冲刺）。转向速度不变，因此速度越快转弯越宽。")) {
        g_settings.flight_speed = mult[si];
        settings_save();
    }
}

extern "C" void drop_rows(void) {
    bool c = false;
    c |= opt_toggle("心", &g_settings.drop_hearts, true, "击败的敌人、割草与罐子可以掉落回复之心。");
    c |= opt_toggle("卢比", &g_settings.drop_rupees, true, "击败的敌人、割草与罐子可以掉落卢比。");
    c |= opt_toggle("弹药", &g_settings.drop_ammo, true,
                    "击败的敌人、割草与罐子可以掉落箭、德库种子与炸弹（需先拿到对应的袋）。");
    c |= opt_toggle("宝物", &g_settings.drop_treasures, true,
                    "击败敌人可以掉落怪物素材：丘丘胶、怪物爪、装饰骷髅与黄金骷髅、邪恶结晶。");
    if (c) settings_save();
}

static void speed_row(const char *label, float *v, const char *desc) {
    static const char *const names[] = {"0.5x", "0.75x", "默认", "1.25x", "1.5x", "2x"};
    static const float mult[] = {0.5f, 0.75f, 1, 1.25f, 1.5f, 2};
    int si = 2;
    for (int i = 0; i < 6; i++)
        if (fabsf(mult[i] - *v) < fabsf(mult[si] - *v)) si = i;
    if (opt_choice(label, &si, names, 6, 2, desc)) {
        *v = mult[si];
        settings_save();
    }
}

extern "C" void link_rows(void) {
    speed_row("行走与奔跑速度", &g_settings.walk_speed,
              "林克走路、奔跑与冲刺的速度。动作节奏不变，因此在极端值下可能会出现脚步滑动。");
}
