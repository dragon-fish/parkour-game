import sys, re
sys.stdout.reconfigure(encoding='utf-8')
src, dst = sys.argv[1], sys.argv[2]
prefixes = tuple(sys.argv[3:])
NOISE = re.compile(r'(Sound|Cue|Anim|Waveform|Effect|Particle|Material|Texture|Mesh|'
                   r'DrawFrust|Component\b|Font|Color|Icon|Image)', re.I)
txt = open(src, encoding='utf-8').read()
out = []
kept = 0
for b in re.split(r'(?m)^## ', txt)[1:]:
    head = b.split('\n', 1)[0]
    cls = head.split()[0]
    if not cls.startswith(prefixes):
        continue
    lines = [l for l in b.rstrip().split('\n')[1:] if l.strip() and not NOISE.search(l)]
    if not lines:
        continue
    kept += 1
    out.append('### %s\n\n```\n%s\n```\n' % (cls, '\n'.join(lines)))
open(dst, 'w', encoding='utf-8').write('\n'.join(out))
print('wrote %d classes -> %s' % (kept, dst))
