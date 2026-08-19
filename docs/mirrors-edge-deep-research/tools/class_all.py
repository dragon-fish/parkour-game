import sys, collections, re
sys.stdout.reconfigure(encoding='utf-8')
from ue3parse import Package

pkg = Package(sys.argv[1])
pat = re.compile(sys.argv[2], re.I) if len(sys.argv) > 2 else None

hist = collections.Counter(pkg.class_of(e) for e in pkg.exports)
print("总类型数: %d" % len(hist))
if pat:
    print("\n匹配 %r 的类型:" % sys.argv[2])
    for cls, n in sorted(hist.items()):
        if pat.search(cls):
            print("  %-42s %d" % (cls, n))
    print("\n匹配 %r 的导出对象（前 15）:" % sys.argv[2])
    shown = 0
    for i, e in enumerate(pkg.exports):
        c = pkg.class_of(e)
        if pat.search(c) or pat.search(e['name']):
            print("  #%-6d %-38s class=%-26s size=%d" % (i + 1, e['name'], c, e['size']))
            shown += 1
            if shown >= 15:
                break
else:
    for cls, n in hist.most_common():
        print("  %-42s %d" % (cls, n))
