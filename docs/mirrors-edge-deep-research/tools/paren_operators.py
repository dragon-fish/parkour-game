"""Rewrite UELib's raw decompile (operators as __NFUN_<token>__ calls) into infix form with
EVERY operator parenthesised.

UELib's pretty printer drops parentheses (`a && (b || c)` comes out as `a && b || c`), so the
pretty output cannot be trusted for precedence. The raw output keeps the structure but is hard to
read. This produces the readable AND unambiguous version.

Usage:
    uv run --no-project --python 3.12 paren_operators.py <script_raw_root> <out_root>
Operator names come from the `native(N) ... operator/preoperator/postoperator` declarations in
<script_raw_root>/Core/Object.uc (and any other package that declares one).
"""
import os, re, sys

FUNC = re.compile(r'native\((\d+)\)[^;(]*?\b(?:function|event)\s+(?:[\w.<>]+\s+)?(\w+)\s*\(')
DECL = re.compile(r'native\((\d+)\)\s+static\s+final\s+(operator|preoperator|postoperator)(?:\(\d+\))?\s+[\w.<> ]+?\s+(\S+)\s*\(')


def load_operators(root):
    ops = {}
    for dirpath, _, files in os.walk(root):
        for fn in files:
            if not fn.endswith('.uc'):
                continue
            text = open(os.path.join(dirpath, fn), encoding='utf-8', errors='replace').read()
            for m in FUNC.finditer(text):
                ops.setdefault(int(m.group(1)), ('function', m.group(2)))
            for m in DECL.finditer(text):
                ops[int(m.group(1))] = (m.group(2), m.group(3))
    return ops


CALL = re.compile(r'__NFUN_(\d+)__\(')


def split_args(s, start):
    """s[start] is just after '('. Return (args, index after the closing ')')."""
    depth, args, cur, i, quote = 0, [], [], start, None
    while i < len(s):
        ch = s[i]
        if quote:
            cur.append(ch)
            if ch == quote and s[i - 1] != '\\':
                quote = None
        elif ch in '"\'':
            quote = ch
            cur.append(ch)
        elif ch in '([{':
            depth += 1
            cur.append(ch)
        elif ch in ')]}':
            if depth == 0:
                args.append(''.join(cur).strip())
                return args, i + 1
            depth -= 1
            cur.append(ch)
        elif ch == ',' and depth == 0:
            args.append(''.join(cur).strip())
            cur = []
        else:
            cur.append(ch)
        i += 1
    raise ValueError('unbalanced call')


def rewrite(s, ops):
    out, i = [], 0
    while True:
        m = CALL.search(s, i)
        if not m:
            out.append(s[i:])
            return ''.join(out)
        out.append(s[i:m.start()])
        token = int(m.group(1))
        args, end = split_args(s, m.end())
        args = [rewrite(a, ops) for a in args]
        kind, name = ops.get(token, (None, None))
        if kind == 'operator' and len(args) == 2:
            out.append(f'({args[0]} {name} {args[1]})')
        elif kind == 'preoperator' and len(args) == 1:
            out.append(f'({name}{args[0]})')
        elif kind == 'postoperator' and len(args) == 1:
            out.append(f'({args[0]}{name})')
        elif kind == 'function':
            out.append(f'{name}(' + ', '.join(args) + ')')
        else:
            out.append(f'__NFUN_{token}__(' + ', '.join(args) + ')')
        i = end


def main():
    src, dst = sys.argv[1], sys.argv[2]
    ops = load_operators(src)
    print(f'{len(ops)} operators')
    for dirpath, _, files in os.walk(src):
        for fn in files:
            if not fn.endswith('.uc'):
                continue
            rel = os.path.relpath(os.path.join(dirpath, fn), src)
            text = open(os.path.join(dirpath, fn), encoding='utf-8', errors='replace').read()
            os.makedirs(os.path.dirname(os.path.join(dst, rel)), exist_ok=True)
            try:
                text = rewrite(text, ops)
            except ValueError as e:
                print(f'warning: {rel}: {e}; copied unchanged')
            with open(os.path.join(dst, rel), 'w', encoding='utf-8') as f:
                f.write(text)


if __name__ == '__main__':
    main()
