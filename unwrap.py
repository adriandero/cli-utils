import sys
import re

CLAUDE_MARKER = r'▎'

BOX_DRAWING = re.compile(r'[─│┌┐└┘├┤┬┴┼╴╵╶╷╭╮╯╰╱╲╳]')


def is_table_line(line):
    return bool(BOX_DRAWING.search(line))


def is_special(line):
    s = line.strip()
    return (
        s.startswith('- ') or
        s.startswith('* ') or
        s.startswith('#') or
        re.match(r'^\d+\.', s) or
        s.startswith('```') or
        s == ''
    )


text = sys.stdin.read()
text = re.sub(CLAUDE_MARKER + r'\s?', '', text)

lines = text.splitlines()
output = []
current = []
in_code_block = False

for line in lines:
    stripped = line.strip()

    if stripped.startswith('```'):
        if current:
            output.append(' '.join(current))
            current = []
        in_code_block = not in_code_block
        output.append(stripped)
        continue

    if in_code_block:
        output.append(line.rstrip())
        continue

    if is_table_line(line):
        if current:
            output.append(' '.join(current))
            current = []
        output.append(line.rstrip())
        continue

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
