"""Drops `const` from expressions that read `S.<text>` (texts are runtime
values since the app is translated). Declarations become `final`.

Run once over lib/: python tool/unconst_strings.py lib
"""
import os, re, sys

OPEN, CLOSE = '([{', ')]}'


def skip_string(s, i):
    """Index after the string literal starting at i (handles r'', ''' and ${})."""
    raw = s[i] == 'r'
    if raw:
        i += 1
    q = s[i]
    triple = s[i:i + 3] == q * 3
    end = q * 3 if triple else q
    i += 3 if triple else 1
    while i < len(s):
        if not raw and s[i] == '\\':
            i += 2
            continue
        if s.startswith(end, i):
            return i + len(end)
        if not raw and s[i] == '$' and s[i + 1:i + 2] == '{':
            i = match(s, i + 1) + 1
            continue
        i += 1
    return i


def match(s, i):
    """Index of the bracket closing the one at i (strings and comments skipped)."""
    depth = 0
    while i < len(s):
        c = s[i]
        if s.startswith('//', i):
            i = s.find('\n', i)
            continue
        if s.startswith('/*', i):
            i = s.find('*/', i) + 2
            continue
        if c in '\'"' or (c == 'r' and s[i + 1:i + 2] in '\'"' and not s[i - 1].isalnum()):
            i = skip_string(s, i)
            continue
        if c in OPEN:
            depth += 1
        elif c in CLOSE:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(s) - 1


def code_positions(s):
    """Positions of `const` keywords outside strings and comments."""
    i, out = 0, []
    while i < len(s):
        if s.startswith('//', i):
            i = s.find('\n', i)
            if i < 0:
                break
            continue
        if s.startswith('/*', i):
            i = s.find('*/', i) + 2
            continue
        c = s[i]
        if c in '\'"' or (c == 'r' and s[i + 1:i + 2] in '\'"' and (i == 0 or not s[i - 1].isalnum())):
            i = skip_string(s, i)
            continue
        if s.startswith('const', i) and (i == 0 or not (s[i - 1].isalnum() or s[i - 1] == '_')) and not (s[i + 5:i + 6].isalnum() or s[i + 5:i + 6] == '_'):
            out.append(i)
            i += 5
            continue
        i += 1
    return out


# what makes an expression runtime-only: texts and the palette
PATTERN = r'(?<![\w.])(S|Palette|NothingColors)\.\w'

DECL = re.compile(r'\s+(?:[\w<>?, ]+\s+)?\w+\s*=(?!=)')


def span(s, i):
    """(end, is_declaration) of the expression introduced by `const` at i."""
    j = i + 5
    m = DECL.match(s, j)
    if m:
        # declaration: up to the `;` at depth 0
        k = m.end()
        while k < len(s):
            if s[k] in OPEN:
                k = match(s, k) + 1
                continue
            if s[k] in '\'"':
                k = skip_string(s, k)
                continue
            if s[k] == ';':
                return k, True
            k += 1
        return k, True
    while j < len(s) and s[j].isspace():
        j += 1
    if j < len(s) and s[j] in OPEN:
        return match(s, j), False
    if s[j] == '<':  # const <T>[...]
        j = s.index('>', j) + 1
        while s[j].isspace():
            j += 1
        return match(s, j), False
    # Name, Name<T>, Name.named, then (...)
    m = re.compile(r'[\w.]+(?:<[^()]*?>)?(?:\.\w+)?\s*').match(s, j)
    k = m.end() if m else j
    if k < len(s) and s[k] == '(':
        return match(s, k), False
    return k, False


def fix(s):
    changed = 0
    while True:
        hit = None
        for i in code_positions(s):
            end, decl = span(s, i)
            if re.search(PATTERN, s[i:end + 1]):
                hit = (i, decl)
                break
        if hit is None:
            return s, changed
        i, decl = hit
        if decl:
            s = s[:i] + 'final' + s[i + 5:]
        else:
            # also eat the space after `const`
            k = i + 5
            while k < len(s) and s[k] == ' ':
                k += 1
            s = s[:i] + s[k:]
        changed += 1


def main(root):
    total = 0
    for dp, _, fs in os.walk(root):
        for f in fs:
            if not f.endswith('.dart') or 'l10n' in dp or f == 'theme.dart' or 'src' + os.sep + 'rust' in os.path.join(dp, f):
                continue
            p = os.path.join(dp, f)
            s = open(p, encoding='utf-8').read()
            t, n = fix(s)
            if n:
                open(p, 'w', encoding='utf-8', newline='').write(t)
                total += n
                print(f'{p}: {n}')
    print('removed', total)


if __name__ == '__main__':
    main(sys.argv[1])
