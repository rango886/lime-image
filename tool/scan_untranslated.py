"""扫描 Dart 源码里的中文字面量：哪些没进 translations.tsv、哪些没包 lt()。
用法: uv run tool/scan_untranslated.py [目录...]   (默认 lib)
"""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
known = set()
for line in (root / 'tool/translations.tsv').read_text(encoding='utf-8').splitlines():
    if line:
        known.add(line.split('|')[0].replace(r'\n', '\n'))

han = re.compile(r'[\u4e00-\u9fff]')
# 单/双引号字符串字面量（不处理三引号和跨行）
lit = re.compile(r"""(?<![\w])(r?)('(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*")""")

dirs = sys.argv[1:] or ['lib']
missing, unwrapped = {}, []
for d in dirs:
    for f in sorted((root / d).rglob('*.dart')):
        if f.name == 'translations.dart':
            continue
        for no, line in enumerate(f.read_text(encoding='utf-8').splitlines(), 1):
            code = line.split('//')[0] if '//' in line and "'" not in line.split('//')[0][-1:] else line
            s = code.strip()
            if s.startswith('//') or s.startswith('///'):
                continue
            for m in lit.finditer(code):
                body = m.group(2)[1:-1]
                if not han.search(body):
                    continue
                text = body.encode().decode('unicode_escape').encode('latin1').decode('utf-8') if '\\' in body else body
                before = code[:m.start()].rstrip()
                wrapped = before.endswith('lt(') or before.endswith('translate(')
                rel = f.relative_to(root)
                if wrapped:
                    if text not in known:
                        missing.setdefault(text, f'{rel}:{no}')
                else:
                    unwrapped.append(f'{rel}:{no}: {text}')

print(f'== lt() 里但 TSV 没有: {len(missing)}')
for k, v in missing.items():
    print(f'{v}\t{k}')
print(f'\n== 中文字面量没包 lt(): {len(unwrapped)}')
for u in unwrapped:
    print(u)
