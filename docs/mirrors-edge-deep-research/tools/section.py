import sys, re
sys.stdout.reconfigure(encoding='utf-8')
path, names = sys.argv[1], sys.argv[2:]
txt = open(path, encoding='utf-8').read()
blocks = re.split(r'(?m)^## ', txt)
for b in blocks[1:]:
    head = b.split('\n', 1)[0]
    cls = head.split()[0]
    if cls in names:
        print('## ' + b.rstrip() + '\n')
