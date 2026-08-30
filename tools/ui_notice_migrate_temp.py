from pathlib import Path
import re

root = Path('client/lib')
notice_file = Path('client/lib/ui/widgets/fx_notice.dart')


def scan_matching(text: str, open_index: int) -> int:
    pairs = {'(': ')', '[': ']', '{': '}'}
    stack: list[str] = []
    quote = None
    triple = False
    escape = False
    line_comment = False
    block_comment = False
    i = open_index
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ''
        if line_comment:
            if ch == '\n':
                line_comment = False
            i += 1
            continue
        if block_comment:
            if ch == '*' and nxt == '/':
                block_comment = False
                i += 2
            else:
                i += 1
            continue
        if quote:
            if escape:
                escape = False
                i += 1
                continue
            if ch == '\\':
                escape = True
                i += 1
                continue
            if triple:
                if text.startswith(quote * 3, i):
                    quote = None
                    triple = False
                    i += 3
                else:
                    i += 1
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch == '/' and nxt == '/':
            line_comment = True
            i += 2
            continue
        if ch == '/' and nxt == '*':
            block_comment = True
            i += 2
            continue
        if ch in "'\"":
            quote = ch
            triple = text.startswith(ch * 3, i)
            i += 3 if triple else 1
            continue
        if ch in pairs:
            stack.append(pairs[ch])
        elif stack and ch == stack[-1]:
            stack.pop()
            if not stack:
                return i
        i += 1
    raise RuntimeError(f'unmatched delimiter at {open_index}')


def split_top(text: str) -> list[str]:
    parts: list[str] = []
    start = 0
    stack: list[str] = []
    quote = None
    triple = False
    escape = False
    i = 0
    pairs = {'(': ')', '[': ']', '{': '}'}
    while i < len(text):
        ch = text[i]
        if quote:
            if escape:
                escape = False
            elif ch == '\\':
                escape = True
            elif triple and text.startswith(quote * 3, i):
                quote = None
                triple = False
                i += 2
            elif not triple and ch == quote:
                quote = None
            i += 1
            continue
        if ch in "'\"":
            quote = ch
            triple = text.startswith(ch * 3, i)
            if triple:
                i += 2
        elif ch in pairs:
            stack.append(pairs[ch])
        elif stack and ch == stack[-1]:
            stack.pop()
        elif ch == ',' and not stack:
            part = text[start:i].strip()
            if part:
                parts.append(part)
            start = i + 1
        i += 1
    tail = text[start:].strip()
    if tail:
        parts.append(tail)
    return parts


def split_named(text: str) -> tuple[str | None, str]:
    stack: list[str] = []
    quote = None
    triple = False
    escape = False
    pairs = {'(': ')', '[': ']', '{': '}'}
    i = 0
    while i < len(text):
        ch = text[i]
        if quote:
            if escape:
                escape = False
            elif ch == '\\':
                escape = True
            elif triple and text.startswith(quote * 3, i):
                quote = None
                triple = False
                i += 2
            elif not triple and ch == quote:
                quote = None
            i += 1
            continue
        if ch in "'\"":
            quote = ch
            triple = text.startswith(ch * 3, i)
            if triple:
                i += 2
        elif ch in pairs:
            stack.append(pairs[ch])
        elif stack and ch == stack[-1]:
            stack.pop()
        elif ch == ':' and not stack:
            return text[:i].strip(), text[i + 1:].strip()
        i += 1
    return None, text.strip()


def parse_snackbar(expr: str) -> dict[str, str]:
    raw = expr.strip().rstrip(',').strip()
    raw = re.sub(r'^const\s+', '', raw)
    match = re.match(r'^SnackBar\s*\(', raw)
    if not match:
        raise RuntimeError(f'unsupported showSnackBar argument: {raw[:160]}')
    open_index = raw.find('(', match.start())
    close_index = scan_matching(raw, open_index)
    if raw[close_index + 1:].strip():
        raise RuntimeError(f'unexpected SnackBar suffix: {raw[close_index + 1:]}')
    args: dict[str, str] = {}
    for part in split_top(raw[open_index + 1:close_index]):
        key, value = split_named(part)
        if key is None:
            raise RuntimeError(f'positional SnackBar arg is unsupported: {part}')
        args[key] = value
    allowed = {'content', 'duration', 'action', 'backgroundColor', 'behavior'}
    unknown = sorted(set(args) - allowed)
    if unknown:
        raise RuntimeError(f'unsupported SnackBar args: {unknown}')
    if 'content' not in args:
        raise RuntimeError('SnackBar without content')
    return args


def variant_from_background(bg: str | None) -> str | None:
    if bg is None:
        return None
    compact = re.sub(r'\s+', ' ', bg).strip()
    if compact == 'color':
        return 'noticeVariant'
    replacements = {
        'AppTheme.warning': 'FxNoticeVariant.warning',
        'AppTheme.success': 'FxNoticeVariant.success',
        'AppTheme.error': 'FxNoticeVariant.destructive',
        'AppTheme.priorityHigh': 'FxNoticeVariant.destructive',
        'Theme.of(context).colorScheme.error': 'FxNoticeVariant.destructive',
        'theme.colorScheme.error': 'FxNoticeVariant.destructive',
        'Colors.red': 'FxNoticeVariant.destructive',
    }
    if '?' in bg:
        result = bg
        for old, new in replacements.items():
            result = result.replace(old, new)
        result = re.sub(r'\bnull\b', 'FxNoticeVariant.normal', result)
        if 'AppTheme.' in result or 'colorScheme.error' in result or 'Colors.red' in result:
            raise RuntimeError(f'unmapped conditional notice color: {bg}')
        return result.strip()
    for old, new in replacements.items():
        if compact == old:
            return new
    raise RuntimeError(f'unmapped notice backgroundColor: {bg}')


def build_notice(context_expr: str, snackbar_expr: str, handle: str | None = None) -> str:
    args = parse_snackbar(snackbar_expr)
    content = args['content']
    action = args.get('action')
    if action:
        action = re.sub(r'\bSnackBarAction\s*\(', 'FxNoticeAction(', action)
    variant = variant_from_background(args.get('backgroundColor'))
    named: list[str] = []
    if action:
        named.append(f'action: {action}')
    if args.get('duration'):
        named.append(f'duration: {args["duration"]}')
    if variant:
        named.append(f'variant: {variant}')
    suffix = ', ' + ', '.join(named) if named else ''
    if handle:
        return f'{handle}.showContent({content}{suffix})'
    return f'FxNotice.showContent({context_expr}, {content}{suffix})'


def skip_ws(text: str, index: int) -> int:
    while index < len(text) and text[index].isspace():
        index += 1
    return index


changed: set[str] = set()
initial_snackbars = 0
for path in root.rglob('*.dart'):
    if path == notice_file:
        continue
    initial_snackbars += len(re.findall(r'\bSnackBar\s*\(', path.read_text(encoding='utf-8')))
if initial_snackbars != 58:
    raise SystemExit(f'expected 58 SnackBar constructors, found {initial_snackbars}')

# CalDAV 的动态颜色先提升为通知语义，避免把任意 Color 泄漏到 Fx API。
caldav = Path('client/lib/screens/caldav_screen.dart')
source = caldav.read_text(encoding='utf-8')
replacements = [
    ('        Color color;', '        FxNoticeVariant noticeVariant;'),
    ('          color = AppTheme.success;', '          noticeVariant = FxNoticeVariant.success;'),
    ('          color = AppTheme.warning;', '          noticeVariant = FxNoticeVariant.warning;'),
    ('          color = AppTheme.error;', '          noticeVariant = FxNoticeVariant.destructive;'),
]
for old, new in replacements:
    if source.count(old) != 1:
        raise SystemExit(f'CalDAV semantic line changed unexpectedly: {old!r}')
    source = source.replace(old, new, 1)
caldav.write_text(source, encoding='utf-8')
changed.add(caldav.as_posix())

# 两处 Sheet 会在关闭 Route 后继续通知，先捕获 FxNoticeHandle。
cached_expected = 0
for path in [Path('client/lib/screens/task_create_sheet.dart'), Path('client/lib/widgets/task_detail_sheet.dart')]:
    source = path.read_text(encoding='utf-8')
    source, count = re.subn(
        r'final\s+messenger\s*=\s*ScaffoldMessenger\.of\(context\);',
        'final notice = FxNotice.capture(context);',
        source,
    )
    cached_expected += count
    if count != 1:
        raise SystemExit(f'{path}: expected one cached ScaffoldMessenger, found {count}')

    while True:
        marker = 'messenger.showSnackBar('
        start = source.find(marker)
        if start < 0:
            break
        open_index = start + len(marker) - 1
        close_index = scan_matching(source, open_index)
        body = source[open_index + 1:close_index]
        replacement = build_notice('context', body, handle='notice')
        source = source[:start] + replacement + source[close_index + 1:]
    source = source.replace('messenger.hideCurrentSnackBar()', 'notice.clear()')
    path.write_text(source, encoding='utf-8')
    changed.add(path.as_posix())
if cached_expected != 2:
    raise SystemExit(f'expected 2 cached messengers, found {cached_expected}')

# 其余 ScaffoldMessenger 直接调用与 Android 返回键 cascade。
for path in sorted(root.rglob('*.dart')):
    if path == notice_file:
        continue
    source = path.read_text(encoding='utf-8')
    original = source
    pos = 0
    marker = 'ScaffoldMessenger.of('
    while True:
        start = source.find(marker, pos)
        if start < 0:
            break
        open_index = start + len(marker) - 1
        close_of = scan_matching(source, open_index)
        context_expr = source[open_index + 1:close_of].strip().rstrip(',').strip()
        cursor = skip_ws(source, close_of + 1)

        if source.startswith('.showSnackBar(', cursor):
            show_open = cursor + len('.showSnackBar')
            show_close = scan_matching(source, show_open)
            body = source[show_open + 1:show_close]
            replacement = build_notice(context_expr, body)
            source = source[:start] + replacement + source[show_close + 1:]
            pos = start + len(replacement)
            continue

        if source.startswith('.clearSnackBars()', cursor):
            end = cursor + len('.clearSnackBars()')
            replacement = f'FxNotice.clear({context_expr})'
            source = source[:start] + replacement + source[end:]
            pos = start + len(replacement)
            continue

        if source.startswith('..hideCurrentSnackBar()', cursor):
            after_hide = cursor + len('..hideCurrentSnackBar()')
            after_hide = skip_ws(source, after_hide)
            if not source.startswith('..showSnackBar(', after_hide):
                raise RuntimeError(f'{path}: unsupported ScaffoldMessenger cascade')
            show_open = after_hide + len('..showSnackBar')
            show_close = scan_matching(source, show_open)
            body = source[show_open + 1:show_close]
            notice = build_notice(context_expr, body)
            replacement = f'FxNotice.clear({context_expr});\n      {notice}'
            source = source[:start] + replacement + source[show_close + 1:]
            pos = start + len(replacement)
            continue

        line = source.count('\n', 0, start) + 1
        raise RuntimeError(f'{path}:{line}: unsupported ScaffoldMessenger usage')

    if source != original:
        path.write_text(source, encoding='utf-8')
        changed.add(path.as_posix())

# 所有改动文件补 Fx 统一入口；part 文件由宿主 library 提供 import。
for raw in sorted(changed):
    path = Path(raw)
    source = path.read_text(encoding='utf-8')
    if re.search(r'^\s*part\s+of\s+', source, flags=re.MULTILINE):
        continue
    if re.search(r"import\s+['\"][^'\"]*ui/fx\.dart['\"]", source):
        continue
    imports = list(re.finditer(r'^import\s+[^;]+;\s*$', source, flags=re.MULTILINE))
    if not imports:
        raise RuntimeError(f'{path}: cannot locate imports')
    end = imports[-1].end()
    source = source[:end] + "\nimport 'package:slowlight/ui/fx.dart';" + source[end:]
    path.write_text(source, encoding='utf-8')

residual: list[str] = []
for path in sorted(root.rglob('*.dart')):
    if path == notice_file:
        continue
    source = path.read_text(encoding='utf-8')
    hits: list[str] = []
    if re.search(r'\bSnackBar\s*\(', source):
        hits.append('SnackBar')
    if re.search(r'\bSnackBarAction\s*\(', source):
        hits.append('SnackBarAction')
    if re.search(r'\bScaffoldMessenger\.of\s*\(', source):
        hits.append('ScaffoldMessenger.of')
    if hits:
        residual.append(f'{path}: {", ".join(hits)}')
if residual:
    raise SystemExit('notice migration residuals:\n' + '\n'.join(residual))

Path('.ui-notice-changed.txt').write_text('\n'.join(sorted(changed)) + '\n', encoding='utf-8')
print(f'migrated {initial_snackbars} SnackBars across {len(changed)} files')
for raw in sorted(changed):
    print(raw)
