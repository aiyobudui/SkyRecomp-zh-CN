#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从汉化后的界面源码里收集用到的汉字，生成 runtime/ui/zh_glyphs.h。

改了界面文案后重新跑一次，保证新增的字形也进图集：
    python tools/zh_glyphs.py
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
FILES = ['launcher.mm', 'menu.mm', 'cheats.mm', 'difficulty.mm',
         'option_rows.mm', 'controls_ui.mm', 'osk.mm']
EXTRA = '·—…“”‘’‹›→✓▸'  # 原来英文字体里带的符号，中文字体不一定有，一并加进去


def main():
    chars = set()
    for name in FILES:
        text = (ROOT / 'runtime' / 'ui' / name).read_text(encoding='utf-8')
        chars |= set(re.findall(r'[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef]', text))
    chars |= set(EXTRA)

    out = ['// 由 tools/zh_glyphs.py 生成：界面里实际用到的汉字与符号（用于构建 ImGui 字形范围）',
           '// 若新增了界面文案，重新跑一次生成脚本即可。',
           '#pragma once',
           '',
           'static const char *const ZH_UI_GLYPHS =']
    line = ''
    for ch in sorted(chars):
        if len(line) >= 56:
            out.append(f'    "{line}"')
            line = ''
        line += ch
    if line:
        out.append(f'    "{line}"')
    out.append('    ;')

    (ROOT / 'runtime' / 'ui' / 'zh_glyphs.h').write_text('\n'.join(out) + '\n', encoding='utf-8')
    print(f'已生成 zh_glyphs.h，共 {len(chars)} 个字形')


if __name__ == '__main__':
    main()
