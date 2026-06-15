import sys
import re

text = sys.stdin.read()
text = re.sub(r'[▎│]\s*', '', text)

lines = text.splitlines()
output = []
current = []

def is_special(line):
    s = line.strip()
    return (s.startswith('- ') or s.startswith('* ') or
            s.startswith('#') or re.match(r'^\d+\.', s) or s == '')

for line in lines:
    stripped = line.strip()
    if stripped == '':
        if current:
            output.append(' '.join(current))
            current = []
        output.append('')
    elif is_special(stripped):
        if current:
            output.append(' '.join(current))
            current = []
        output.append(stripped)
    else:
        current.append(stripped)

if current:
    output.append(' '.join(current))

print(re.sub(r'\n{3,}', '\n\n', '\n'.join(output)))
