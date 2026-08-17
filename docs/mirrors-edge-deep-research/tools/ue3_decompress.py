"""Decompress a UE3 LZO-chunked package (Mirror's Edge TdGame.u) into a flat file."""
import sys, struct, io
sys.stdout.reconfigure(encoding='utf-8')
from lzallright import LZOCompressor

SRC = sys.argv[1]
DST = sys.argv[2]

raw = open(SRC, 'rb').read()

# ---- header walk to reach the compressed-chunk table ----
off = 12
slen, = struct.unpack_from('<i', raw, off); off += 4
off += slen if slen >= 0 else -slen * 2
off += 4 + 28 + 16                                   # PackageFlags, counts/offsets, GUID
gencount, = struct.unpack_from('<i', raw, off); off += 4
off += gencount * 12
off += 8                                             # EngineVersion, CookerVersion
cflags, = struct.unpack_from('<I', raw, off); off += 4
assert cflags == 2, "expected LZO, got 0x%X" % cflags
nchunks, = struct.unpack_from('<i', raw, off); off += 4

chunks = []
for _ in range(nchunks):
    chunks.append(struct.unpack_from('<4i', raw, off)); off += 16

total = max(u_off + u_size for u_off, u_size, _, _ in chunks)
out = bytearray(total)
out[:chunks[0][0]] = raw[:chunks[0][0]]              # uncompressed header prefix

def lzo_dec(src, want):
    try:
        return LZOCompressor.decompress(src, want)
    except TypeError:
        return LZOCompressor.decompress(src, output_size_hint=want)

nblocks_total = 0
for i, (u_off, u_size, c_off, c_size) in enumerate(chunks):
    p = c_off
    magic, blocksize, sum_c, sum_u = struct.unpack_from('<4I', raw, p); p += 16
    assert magic == 0x9E2A83C1, "bad block magic in chunk %d" % i
    nblocks = (sum_u + blocksize - 1) // blocksize
    infos = []
    for _ in range(nblocks):
        infos.append(struct.unpack_from('<2I', raw, p)); p += 8
    w = u_off
    for bc, bu in infos:
        dec = lzo_dec(raw[p:p + bc], bu)
        assert len(dec) == bu, "chunk %d block size mismatch: %d != %d" % (i, len(dec), bu)
        out[w:w + bu] = dec
        w += bu; p += bc
    nblocks_total += nblocks
    assert w - u_off == u_size, "chunk %d size mismatch" % i

open(DST, 'wb').write(out)
print("chunks=%d blocks=%d  %d bytes -> %d bytes (x%.2f)"
      % (nchunks, nblocks_total, len(raw), len(out), len(out) / len(raw)))
print("written:", DST)
