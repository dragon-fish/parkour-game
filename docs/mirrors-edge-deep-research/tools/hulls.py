"""Extract real convex collision hulls (KConvexElem) from UE3 RB_BodySetup."""
import sys, struct
from mapdump import MapReader


class HullReader:
    def __init__(self, path):
        self.mr = MapReader(path)
        self.pkg = self.mr.pkg
        self.d = self.mr.d

    def _tags(self, start, end):
        ok, props, nat = self.mr._chain(start, end)
        return props if ok else []

    def _calibrated(self, idx):
        e = self.pkg.exports[idx - 1]
        base, end = e['offset'], e['offset'] + e['size']
        best = []
        for off in range(0, min(32, e['size']), 4):
            p = self._tags(base + off, end)
            # The real body-setup list starts with PhysMaterial/AggGeom; a run
            # that lands inside the nested KConvexElem data parses too, so pick
            # the one that actually contains AggGeom rather than the longest.
            if any(t[0] == 'AggGeom' for t in p):
                return p, end
            if len(p) > len(best):
                best = p
        return best, end

    def _farray(self, q, sz):
        cnt = struct.unpack_from('<i', self.d, q)[0]
        if cnt <= 0 or (sz - 4) < cnt * 12:
            return []
        return [struct.unpack_from('<3f', self.d, q + 4 + i * 12) for i in range(cnt)]

    def _iarray(self, q, sz):
        cnt = struct.unpack_from('<i', self.d, q)[0]
        if cnt <= 0 or (sz - 4) < cnt * 4:
            return []
        return list(struct.unpack_from('<%di' % cnt, self.d, q + 4))

    def hulls_for(self, body_idx):
        """Return [{verts: [...], tris: [...]}, ...] for one RB_BodySetup."""
        props, end = self._calibrated(body_idx)
        agg = next((t for t in props if t[0] == 'AggGeom'), None)
        if agg is None:
            return []
        _, _, _, q, sz, _ = agg
        out = []
        for (name, typ, extra, vq, vsz, arr) in self._tags(q, q + sz):
            if name != 'ConvexElems' or typ != 'ArrayProperty':
                continue
            cnt = struct.unpack_from('<i', self.d, vq)[0]
            p = vq + 4
            limit = vq + vsz
            for _ in range(max(cnt, 0)):
                if p >= limit:
                    break
                elem = self._tags(p, limit)
                if not elem:
                    break
                verts, tris = [], []
                for (en, et, ex, eq, esz, ea) in elem:
                    if en == 'VertexData':
                        verts = self._farray(eq, esz)
                    elif en == 'FaceTriData':
                        tris = self._iarray(eq, esz)
                # advance past this element's terminating None
                last = elem[-1]
                p = last[3] + last[4]
                while p + 8 <= limit:
                    ni = struct.unpack_from('<i', self.d, p)[0]
                    if self.mr.nm(ni) == 'None':
                        p += 8
                        break
                    p += 4
                if verts:
                    out.append({'verts': verts, 'tris': tris})
        return out

    def by_mesh(self):
        """mesh name -> list of hulls."""
        res = {}
        for i, e in enumerate(self.pkg.exports):
            if self.pkg.class_of(e) != 'RB_BodySetup':
                continue
            owner = self.pkg.resolve(e['outer_idx'])
            if not owner:
                continue
            h = self.hulls_for(i + 1)
            if h:
                res[owner] = h
        return res


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    hr = HullReader(sys.argv[1])
    data = hr.by_mesh()
    print("解析出凸包的网格: %d 个" % len(data))
    tot = sum(len(v) for v in data.values())
    print("凸包总数: %d\n" % tot)
    for name in (sys.argv[2:] or list(data)[:6]):
        hs = data.get(name)
        if not hs:
            print("  %-32s <无>" % name[:32]); continue
        print("  %-32s %d 个凸包" % (name[:32], len(hs)))
        for k, h in enumerate(hs[:4]):
            vs = h['verts']
            xs = [v[0] for v in vs]; ys = [v[1] for v in vs]; zs = [v[2] for v in vs]
            print("     [%d] %3d 顶点 %4d 索引  局部尺寸 %.2f x %.2f x %.2f m"
                  % (k, len(vs), len(h['tris']),
                     (max(xs)-min(xs))/100, (max(ys)-min(ys))/100, (max(zs)-min(zs))/100))
