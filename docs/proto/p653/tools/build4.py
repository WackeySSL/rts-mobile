import sys, os, json, time
sys.path.insert(0, '/tmp/p653/docs/proto/p653/tools')
from build3 import *
import io

# 1. contact sheet: 16 directions, both team colours, zoom 2 (1 screen px per art px), on grass
k = 1.0
cw, ch = 270, 170
sheet = Image.new('RGBA', (cw * 8, ch * 4), (0, 0, 0, 255))
bgt = ground_fill(cw * 8, ch * 4, 'grass', k)
sheet.alpha_composite(bgt)
for team_i, team in enumerate((SIGNAL[1], KOBOLT[1])):
    for d in range(16):
        col = d % 8; row = team_i * 2 + d // 8
        draw_tank(sheet, proto_tank(d, team), col * cw + cw / 2 - 5, row * ch + ch * 0.66, k)
d_ = ImageDraw.Draw(sheet)
for d in range(16):
    d_.text(((d % 8) * cw + 6, (d // 8) * ch + 4), f'd{d:02d} Signal', fill=(255, 255, 255, 255), font=FONT)
    d_.text(((d % 8) * cw + 6, (2 + d // 8) * ch + 4), f'd{d:02d} Kobolt', fill=(255, 255, 255, 255), font=FONT)
sheet.save(OUTD + 'tank_16dir_contact_sheet.png')

# 2. readability: 32 px long side, greyscale; today's SVG vs prototype, dirs 2 5 9 13
def trim_compose(layers, k_):
    c = Image.new('RGBA', (700, 500), (0, 0, 0, 0))
    draw_tank(c, layers[1:], 350, 330, k_)
    return c.crop(c.getbbox())
rows = []
for variant in ('svg', 'proto'):
    row = []
    for d in (2, 5, 9, 13):
        L = svg_tank(d, 'O') if variant == 'svg' else proto_tank(d, SIGNAL[1])
        t = trim_compose(L, 1.0)
        s = 32.0 / max(t.size)
        small = t.resize((max(1, round(t.width * s)), max(1, round(t.height * s))), Image.LANCZOS)
        bgc = Image.new('RGBA', small.size, (100, 110, 70, 255)); bgc.alpha_composite(small)
        g = bgc.convert('L')
        cell = Image.new('L', (40, 40), 100); cell.paste(g, ((40 - g.width) // 2, (40 - g.height) // 2))
        row.append(cell)
    rows.append(row)
sheet2 = Image.new('L', (4 * 40 * 6, 2 * 40 * 6 + 6), 0)
for r, row in enumerate(rows):
    for c_, cell in enumerate(row):
        sheet2.paste(cell.resize((240, 240), Image.NEAREST), (c_ * 240, r * 246))
sheet2.save(OUTD + 'readability_32px_grey.png')
print('top row: today SVG; bottom row: prototype; each unit 32 px on its long side, greyscale, shown x6')
