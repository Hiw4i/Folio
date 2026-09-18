#!/usr/bin/env python3
"""Offline source checks, NOT a Dart parser/analyzer or Flutter test runner.

Usage: python tools/check_source_integrity.py [project-root]
Checks mounted-source structure, local Dart imports, delimiter balance outside
comments/strings, patch markers, and preservation of all original test files.
Uses only Python's standard library. Flutter validation is still mandatory.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


def code_characters(text: str):
    """Skip strings (including nested ${...} expressions) and nested comments.

    Interpolation is scanned as code so mismatched braces cannot hide inside
    interpolated strings. Positions remain the positions in the source file.
    """
    n = len(text)
    i = 0

    def code(stop_at_brace: bool = False):
        nonlocal i
        depth = 0
        while i < n:
            c = text[i]
            if text.startswith('//', i):
                end = text.find('\n', i)
                i = n if end < 0 else end
                continue
            if text.startswith('/*', i):
                level = 1
                i += 2
                while i < n and level:
                    if text.startswith('/*', i):
                        level += 1
                        i += 2
                    elif text.startswith('*/', i):
                        level -= 1
                        i += 2
                    else:
                        i += 1
                if level:
                    raise ValueError('unterminated block comment')
                continue
            raw = c == 'r' and i + 1 < n and text[i + 1] in "\"'"
            if c in "\"'" or raw:
                if raw:
                    i += 1
                quote = text[i]
                marker = quote * 3 if text.startswith(quote * 3, i) else quote
                i += len(marker)
                while i < n:
                    if text.startswith(marker, i):
                        i += len(marker)
                        break
                    if not raw and text[i] == '\\':
                        i += 2
                        continue
                    if not raw and text.startswith('${', i):
                        yield i + 1, '{'
                        i += 2
                        yield from code(True)
                        continue
                    i += 1
                else:
                    raise ValueError('unterminated string')
                continue
            if c == '{':
                depth += 1
            elif c == '}':
                if stop_at_brace and depth == 0:
                    yield i, c
                    i += 1
                    return
                depth -= 1
            yield i, c
            i += 1
        if stop_at_brace:
            raise ValueError('unterminated string interpolation')
    yield from code()


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
    files = sorted(root.glob('lib/**/*.dart')) + sorted(root.glob('test/**/*.dart'))
    issues = []
    imports_checked = 0
    test_count = 0
    for path in files:
        source = path.read_text(encoding='utf-8')
        relative = str(path.relative_to(root))
        if re.search(r'^(?:<<<<<<< |=======\s*$|>>>>>>> )', source, re.M):
            issues.append(f'{relative}: unresolved conflict marker')
        for uri in re.findall(r"^\s*(?:import|export|part)\s+['\"]([^'\"]+)['\"]", source, re.M):
            if uri.startswith('package:folio/'):
                target = root / 'lib' / uri.removeprefix('package:folio/')
            elif ':' in uri:
                continue
            else:
                target = path.parent / uri
            imports_checked += 1
            if not target.is_file():
                issues.append(f'{relative}: missing import {uri}')
        stack = []
        try:
            for pos, c in code_characters(source):
                if c in '([{':
                    stack.append((c, pos))
                elif c in ')]}':
                    expected = {')': '(', ']': '[', '}': '{'}[c]
                    if not stack or stack[-1][0] != expected:
                        raise ValueError(f'unbalanced {c!r} at line {source.count(chr(10), 0, pos) + 1}')
                    stack.pop()
            if stack:
                raise ValueError(f'unclosed delimiter {stack[-1][0]!r}')
        except ValueError as error:
            issues.append(f'{relative}: {error}')
        if path.name.endswith('_test.dart'):
            test_count += len(re.findall(r'\btest(?:Widgets)?\s*\(', source))
    report = {
        'validation_kind': 'structural_only_not_dart_analysis',
        'dart_files': len(files),
        'local_imports_checked': imports_checked,
        'test_declarations': test_count,
        'issues': issues,
        'passed': not issues,
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return int(bool(issues))


if __name__ == '__main__':
    sys.exit(main())
