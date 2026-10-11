"""Compute UE3 (Mirror's Edge, 32-bit) object memory layouts from decompiled UnrealScript.

Native C++ reads properties by byte offset, so mapping a decompiled `*(this + 0x6d0)` back
to a property name needs the class layout. UE3 links properties in the order they appear
in the class (the order UELib prints them), each aligned to its own alignment; consecutive
bools share one 32-bit word.

Validated against offsets read from the executable: Actor.Physics = 0x68,
Actor.Velocity = 0x100, sizeof(ATdPawn) = 0x8f8.

Usage:
    uv run --no-project --python 3.12 ue3_layout.py <script_root> <Class> [--grep REGEX] [--at HEX ...]
<script_root> holds one folder per package (Core, Engine, GameFramework, TdGame) of
UELib-decompiled .uc files.
"""
import os, re, sys

MODIFIERS = {
    'const', 'private', 'protected', 'public', 'native', 'transient', 'noexport', 'editinline',
    'export', 'config', 'globalconfig', 'localized', 'editconst', 'interp', 'repnotify', 'input',
    'deprecated', 'duplicatetransient', 'noimport', 'edithide', 'editfixedsize', 'editoronly',
    'nontransactional', 'instanced', 'databinding', 'privatewrite', 'protectedwrite', 'archetype',
    'crosslevelpassive', 'init', 'out', 'optional', 'skip', 'editinlineuse', 'notforconsole',
    'serializetext', 'editortextbox', 'repretry', 'simulated', 'coerce', 'noclear', 'editinlinenotify',
}
PRIMS = {  # size, align
    'bool': (4, 4), 'byte': (1, 1), 'int': (4, 4), 'float': (4, 4), 'name': (8, 4),
    'string': (12, 4),
}


class Index:
    def __init__(self, root):
        self.classes = {}   # name -> {'parent', 'vars': [(type, name, dim)]}
        self.structs = {}   # name -> {'parent', 'vars'}
        self.enums = set()
        for pkg in os.listdir(root):
            d = os.path.join(root, pkg)
            if not os.path.isdir(d):
                continue
            for fn in os.listdir(d):
                if fn.endswith('.uc'):
                    self._parse(open(os.path.join(d, fn), encoding='utf-8', errors='replace').read())

    def _parse(self, text):
        lines = text.split('\n')
        m = re.match(r'(?:interface|class) (\w+)(?: extends (\w+))?', lines[0])
        if not m:
            return
        cls = {'parent': m.group(2), 'vars': []}
        self.classes[m.group(1)] = cls
        i = 0
        while i < len(lines):
            line = lines[i]
            sm = re.match(r'\s*struct\b(.*)', line)
            em = re.match(r'\s*enum (\w+)', line)
            if em:
                self.enums.add(em.group(1))
            elif sm and not line.strip().startswith('structdefaultproperties'):
                words = sm.group(1).split()
                ext = None
                if 'extends' in words:
                    k = words.index('extends')
                    ext = words[k + 1]
                    words = words[:k]
                name = words[-1]
                st = {'parent': ext, 'vars': []}
                depth = 0
                i += 1
                while i < len(lines):
                    l2 = lines[i].strip()
                    if l2.startswith('{'):
                        depth += 1
                    elif l2.startswith('}'):
                        depth -= 1
                        if depth <= 0:
                            break
                    elif depth == 1 and l2.startswith('var'):
                        st['vars'].extend(parse_var(l2))
                    elif re.match(r'struct\b', l2) and not l2.startswith('structdefaultproperties'):
                        # nested struct definition: parse it recursively by re-entering the loop
                        pass
                    i += 1
                self.structs[name] = st
            elif line.startswith('var'):
                cls['vars'].extend(parse_var(line))
            i += 1


def split_type(rest):
    """Return (type, remainder) where type may contain balanced <> or {}."""
    depth = 0
    for j, ch in enumerate(rest):
        if ch in '<{':
            depth += 1
        elif ch in '>}':
            depth -= 1
        elif ch == ' ' and depth == 0:
            return rest[:j], rest[j + 1:]
    return rest, ''


def parse_var(line):
    s = line.strip().rstrip(';')
    s = re.sub(r'^var(\([^)]*\))?\s*', '', s)
    while True:
        word = s.split(' ', 1)[0]
        if word in MODIFIERS:
            s = s.split(' ', 1)[1]
        else:
            break
    typ, names = split_type(s)
    out = []
    for n in names.split(','):
        n = n.strip()
        if not n:
            continue
        m = re.match(r'(\w+)(?:\[(\d+)\])?', n)
        out.append((typ, m.group(1), int(m.group(2)) if m.group(2) else 1))
    return out


class Layout:
    def __init__(self, idx):
        self.idx = idx
        self.struct_cache = {}
        self.warned = set()

    def type_info(self, typ):
        t = typ.split('.')[-1] if '<' not in typ and '{' not in typ else typ
        if t in PRIMS:
            return PRIMS[t]
        if t.startswith('array<') or t.startswith('array '):
            return (12, 4)
        if t.startswith('delegate<'):
            return (12, 4)
        if t.startswith('map{'):
            return (60, 4)
        if t.startswith('Class<'):
            return (4, 4)
        if t in self.idx.enums:
            return (1, 1)
        if t in self.idx.structs:
            return self.struct_info(t)
        if t in self.idx.classes:
            return (8, 4) if self._is_interface(t) else (4, 4)
        if re.fullmatch(r'\w+', t):
            # Intrinsic Core classes (Class, Field, Function...) are not decompiled; they are
            # object references all the same.
            if t not in self.warned:
                self.warned.add(t)
                print(f'warning: assuming object reference for {t}', file=sys.stderr)
            return (4, 4)
        raise KeyError('unknown type ' + typ)

    def _is_interface(self, t):
        while t:
            if t == 'Interface':
                return True
            t = self.idx.classes.get(t, {}).get('parent')
        return False

    def struct_info(self, name):
        if name in self.struct_cache:
            return self.struct_cache[name]
        st = self.idx.structs[name]
        off, align = 0, 1
        if st['parent']:
            off, align = self.struct_info(st['parent'])
        rows, end, a = self.place(st['vars'], off)
        align = max(align, a)
        size = (end + align - 1) // align * align
        self.struct_cache[name] = (size, align)
        return size, align

    def place(self, vars_, off):
        """Lay out vars starting at off; returns (rows, end, max_align)."""
        rows, max_align = [], 1
        bool_word, bool_bit = None, 32
        for typ, name, dim in vars_:
            if typ == 'bool' and dim == 1:
                if bool_word is None or bool_bit >= 32:
                    off = (off + 3) // 4 * 4
                    bool_word, bool_bit = off, 0
                    off += 4
                rows.append((bool_word, 'bool', name, 1 << bool_bit))
                bool_bit += 1
                max_align = max(max_align, 4)
                continue
            bool_word = None
            size, align = self.type_info(typ)
            off = (off + align - 1) // align * align
            rows.append((off, typ, name, dim))
            off += size * dim
            max_align = max(max_align, align)
        return rows, off, max_align

    def class_layout(self, name):
        chain = []
        c = name
        while c:
            chain.append(c)
            c = self.idx.classes[c]['parent']
        rows, off = [], 0
        for c in reversed(chain):
            r, off, _ = self.place(self.idx.classes[c]['vars'], (off + 3) // 4 * 4)
            rows.extend((o, t, n, d, c) for o, t, n, d in r)
        return rows, off


def main():
    root, cls = sys.argv[1], sys.argv[2]
    args = sys.argv[3:]
    lay = Layout(Index(root))
    rows, size = lay.class_layout(cls)
    grep = None
    ats = []
    i = 0
    while i < len(args):
        if args[i] == '--grep':
            grep = re.compile(args[i + 1], re.I); i += 2
        elif args[i] == '--at':
            i += 1
            while i < len(args) and not args[i].startswith('--'):
                ats.append(int(args[i], 16)); i += 1
        else:
            i += 1
    print(f'{cls}: size 0x{size:x}')
    for o, t, n, d, c in rows:
        extra = f' mask 0x{d:x}' if t == 'bool' else (f'[{d}]' if d > 1 else '')
        line = f'0x{o:04x}  {c}.{n}  ({t}){extra}'
        if ats:
            size_t = 4 if t == 'bool' else lay.type_info(t)[0] * d
            if any(o <= a < o + size_t for a in ats):
                print(line)
        elif grep is None or grep.search(n) or grep.search(c):
            print(line)


if __name__ == '__main__':
    main()
