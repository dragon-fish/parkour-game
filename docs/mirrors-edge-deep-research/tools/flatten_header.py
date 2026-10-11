"""Rewrite the summary of a package decompressed by ue3_decompress.py so it is a valid
uncompressed package. The logical (uncompressed) summary carries CompressionFlags=0 and an
empty chunk table, then PackageSource and AdditionalPackagesToCook -- 16 bytes shorter per
chunk than the on-disk summary, which is why NameOffset already points just past it."""
import sys, struct
raw_path, flat_path = sys.argv[1], sys.argv[2]
raw = open(raw_path, 'rb').read()
b = bytearray(open(flat_path, 'rb').read())
off = 12
slen, = struct.unpack_from('<i', raw, off); off += 4
off += slen if slen >= 0 else -slen * 2
name_off, = struct.unpack_from('<i', raw, off + 8)
off += 4 + 28 + 16
gen, = struct.unpack_from('<i', raw, off); off += 4 + gen * 12
off += 8
nchunks, = struct.unpack_from('<i', raw, off + 4)
after = off + 8 + nchunks * 16
rest = raw[after:after + (name_off - (off + 8))]
b[off:name_off] = struct.pack('<ii', 0, 0) + rest
assert len(b) == len(open(flat_path, 'rb').read())
open(flat_path, 'wb').write(b)
print(f'summary rewritten: {nchunks} chunks dropped, names at {name_off}')
