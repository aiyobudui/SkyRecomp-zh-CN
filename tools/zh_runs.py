#!/usr/bin/env python3
"""List merged adjacent string-literal runs that belong to widget calls (whole-file scan).

A run counts when the line it starts on calls a widget helper, so multi-line
concatenated descriptions are reported as one translatable unit.
"""
import re
import sys
import pathlib

RUN = re.compile(r'"(?:[^"\\]|\\.)*"(?:[ \t\r\n]*"(?:[^"\\]|\\.)*")*')
LIT = re.compile(r'"((?:[^"\\]|\\.)*)"')
UI = re.compile(r'(ImGui::|heading\(|btn\(|choice\(|opt_|label\(|rows_help\(|row\(|tip\()')


def unescape(s):
    return s.replace('\\"', '"')


def main():
    for name in sys.argv[1:]:
        path = pathlib.Path(name)
        text = path.read_text(encoding='utf-8', errors='replace')
        line_starts = [0]
        for i, ch in enumerate(text):
            if ch == '\n':
                line_starts.append(i + 1)

        def lineno(pos):
            lo, hi = 0, len(line_starts) - 1
            while lo < hi:
                mid = (lo + hi + 1) // 2
                if line_starts[mid] <= pos:
                    lo = mid
                else:
                    hi = mid - 1
            return lo + 1

        print(f'\n##### {path.name}')
        for m in RUN.finditer(text):
            ln = lineno(m.start())
            line = text[line_starts[ln - 1]: text.find('\n', line_starts[ln - 1]) if text.find('\n', line_starts[ln - 1]) > 0 else len(text)]
            stmt = max(text.rfind(';', 0, m.start()), text.rfind('{', 0, m.start()), text.rfind('}', 0, m.start()))
            ctx = text[stmt: m.start()]
            if line.lstrip().startswith('//') or not UI.search(ctx):
                continue
            parts = [unescape(x) for x in LIT.findall(m.group(0))]
            merged = ''.join(parts)
            if not merged.strip() or not re.search(r'[A-Za-z]', merged):
                continue
            tag = 'M' if len(parts) > 1 else ' '
            print(f'{ln:5d} {tag} {merged}')


if __name__ == '__main__':
    main()
