"""Minimal UE3 (FileVersion 536 / Mirror's Edge) package reader: names, imports, exports."""
import struct, sys

class Reader:
    def __init__(self, data, pos=0):
        self.d = data; self.p = pos
    def i32(self):
        v, = struct.unpack_from('<i', self.d, self.p); self.p += 4; return v
    def u32(self):
        v, = struct.unpack_from('<I', self.d, self.p); self.p += 4; return v
    def u64(self):
        v, = struct.unpack_from('<Q', self.d, self.p); self.p += 8; return v
    def f32(self):
        v, = struct.unpack_from('<f', self.d, self.p); self.p += 4; return v
    def u8(self):
        v = self.d[self.p]; self.p += 1; return v
    def string(self):
        l = self.i32()
        if l == 0: return ''
        if l > 0:
            s = self.d[self.p:self.p + l].decode('latin-1').rstrip('\x00'); self.p += l
        else:
            n = -l * 2
            s = self.d[self.p:self.p + n].decode('utf-16-le').rstrip('\x00'); self.p += n
        return s
    def skip(self, n):
        self.p += n


class Package:
    def __init__(self, path):
        self.d = open(path, 'rb').read()
        r = Reader(self.d, 4)
        self.file_ver, self.lic_ver = struct.unpack_from('<hh', self.d, 4); r.skip(4)
        self.header_size = r.i32()
        r.string()                      # folder name
        self.pkg_flags = r.u32()
        self.name_count = r.i32(); self.name_off = r.i32()
        self.exp_count = r.i32();  self.exp_off = r.i32()
        self.imp_count = r.i32();  self.imp_off = r.i32()
        self.depends_off = r.i32()
        self._read_names()
        self._read_imports()
        self._read_exports()

    def _read_names(self):
        r = Reader(self.d, self.name_off)
        self.names = []
        for _ in range(self.name_count):
            s = r.string()
            r.u64()                     # name flags
            self.names.append(s)

    def name(self, i):
        return self.names[i] if 0 <= i < len(self.names) else '<bad:%d>' % i

    def _fname(self, r):
        idx = r.i32(); num = r.i32()
        n = self.name(idx)
        return n if num == 0 else '%s_%d' % (n, num - 1)

    def _read_imports(self):
        r = Reader(self.d, self.imp_off)
        self.imports = []
        for _ in range(self.imp_count):
            pkg = self._fname(r); cls = self._fname(r)
            outer = r.i32(); obj = self._fname(r)
            self.imports.append({'package': pkg, 'class': cls, 'outer': outer, 'name': obj})

    def _read_exports(self):
        r = Reader(self.d, self.exp_off)
        self.exports = []
        for _ in range(self.exp_count):
            e = {}
            e['class_idx'] = r.i32()
            e['super_idx'] = r.i32()
            e['outer_idx'] = r.i32()
            e['name'] = self._fname(r)
            e['archetype'] = r.i32()
            e['flags'] = r.u64()
            e['size'] = r.i32()
            e['offset'] = r.i32()
            if self.file_ver < 543:             # ComponentMap: FName -> int
                ncomp = r.i32()
                r.skip(ncomp * 12)
            e['export_flags'] = r.u32()
            netcount = r.i32()
            r.skip(netcount * 4)
            r.skip(16)                  # package guid
            r.skip(4)                   # package flags
            self.exports.append(e)

    # ---- object-reference resolution (UE3 index convention) ----
    def resolve(self, idx):
        if idx > 0:  return self.exports[idx - 1]['name']
        if idx < 0:  return self.imports[-idx - 1]['name']
        return None

    def class_of(self, e):
        return self.resolve(e['class_idx']) or 'Class'

    def full_name(self, i):
        """Dotted path of export i (1-based)."""
        parts = []
        cur = i
        while cur > 0:
            e = self.exports[cur - 1]
            parts.append(e['name'])
            cur = e['outer_idx']
        return '.'.join(reversed(parts))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    pkg = Package(sys.argv[1])
    print("names=%d imports=%d exports=%d" % (pkg.name_count, pkg.imp_count, pkg.exp_count))
    classes = [(i + 1, e) for i, e in enumerate(pkg.exports) if pkg.class_of(e) == 'Class']
    print("classes=%d" % len(classes))
    kw = [k.lower() for k in sys.argv[2:]] or ['tdmove', 'tdpawn', 'tdplayer']
    for i, e in classes:
        if any(k in e['name'].lower() for k in kw):
            sup = pkg.resolve(e['super_idx'])
            print("  %-42s extends %-30s size=%d" % (e['name'], sup, e['size']))
