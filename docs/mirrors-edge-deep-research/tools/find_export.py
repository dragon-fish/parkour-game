import sys
sys.stdout.reconfigure(encoding='utf-8')
from ue3parse import Package
pkg = Package(sys.argv[1])
pat = sys.argv[2].lower()
for i, e in enumerate(pkg.exports):
    if pat in e['name'].lower():
        print("#%-6d %-40s class=%-24s outer=%s" %
              (i + 1, pkg.full_name(i + 1), pkg.class_of(e), pkg.resolve(e['outer_idx'])))
