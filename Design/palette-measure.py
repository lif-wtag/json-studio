#!/usr/bin/env python3
"""Measure the JSON Studio palette — the Claude Design "Run 1" system, as adopted.

The palette comes from the approved Claude Design project (the visual source of truth per
the project contract). Its own ratio table was verified correct to 2dp against the bare editor
background. Six values are DELIBERATELY changed from the design, and this script is why:
the design's own current-line and selection washes drop four text tokens below 4.5:1, and
a wash sits under text. Each fix holds the design's hue to within 1.6 degrees.

Three claims in the design's spec page are wrong and are NOT reproduced in tokens.md:
  1. "Every text token clears 4.5:1 in both modes" — true on the bare ground, false on the
     design's own washes (punctuation reached 3.39 dark). Fixed here; see FIXED_FROM_DESIGN.
  2. "Max saturation is 68% (boolean, light)" — number light #9A4E00 is 100% HLS. The real
     maximum by perceptual chroma is the blurple object key at C* 79.
  3. "Keys and strings sit 150 degrees apart" — measured 84 (light) / 91 (dark). Still a
     genuine hue separation, so the design intent holds; the figure was overstated.

Method notes:
  - The saturation gate is CIELAB C*, not HLS. HLS inflates badly for dark and light
    colours. Gate C* <= 80, set by the design's own object key (79).
  - Washes are not held to >=3:1. A wash must be subtle; the real requirement is that text
    ON it clears 4.5:1, which is what the "worst" column measures.
  - Diagnostic colours are exempt from the chroma gate: a desaturated error marker is a
    worse error marker.
"""

import colorsys

# ---------- colour maths ----------

def hex_to_rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) / 255 for i in (0, 2, 4))

def rgb_to_hex(rgb):
    return '#%02X%02X%02X' % tuple(max(0, min(255, round(c * 255))) for c in rgb)

def to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def to_srgb(c):
    c = max(0.0, min(1.0, c))
    return c * 12.92 if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055

def rel_luminance(rgb):
    r, g, b = (to_linear(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def contrast(a, b):
    la, lb = rel_luminance(hex_to_rgb(a)), rel_luminance(hex_to_rgb(b))
    lo, hi = sorted((la, lb))
    return (hi + 0.05) / (lo + 0.05)

def composite(rgba, over):
    """Flatten an rgba(r,g,b,a) fill onto an opaque ground. The design specifies its
    search-match fills as alpha; the harness needs the solid a reader actually sees."""
    r, g, b, a = rgba
    base = hex_to_rgb(over)
    return rgb_to_hex([(a * (c / 255) + (1 - a) * base[i]) for i, c in enumerate((r, g, b))])

def to_lab(h):
    r, g, b = (to_linear(c) for c in hex_to_rgb(h))
    x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
    y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b)
    z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
    f = lambda t: t ** (1 / 3) if t > 0.008856 else (7.787 * t) + (16 / 116)
    fx, fy, fz = f(x), f(y), f(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))

def chroma(h):
    _, a, b = to_lab(h)
    return (a * a + b * b) ** 0.5

def hls_sat_pct(h):
    r, g, b = hex_to_rgb(h)
    return colorsys.rgb_to_hls(r, g, b)[2] * 100

def hue_deg(h):
    r, g, b = hex_to_rgb(h)
    return colorsys.rgb_to_hls(r, g, b)[0] * 360

CVD = {
    'deuteranopia': ((0.367322, 0.860646, -0.227968),
                     (0.280085, 0.672501, 0.047413),
                     (-0.011820, 0.042940, 0.968881)),
    'protanopia':   ((0.152286, 1.052583, -0.204868),
                     (0.114503, 0.786281, 0.099216),
                     (-0.003882, -0.048116, 1.051998)),
}

def simulate(h, kind):
    lin = [to_linear(c) for c in hex_to_rgb(h)]
    mx = CVD[kind]
    return rgb_to_hex([to_srgb(sum(mx[i][j] * lin[j] for j in range(3))) for i in range(3)])

# ---------- the adopted palette ----------

CHROMA_MAX = 80.0

# Grounds are the design's: a 4%-chroma blue-grey dark, not black; an off-white light.
BG = {'light': '#f7f7fa', 'dark': '#161826'}

# Six values changed from the design so text clears 4.5:1 on the design's own washes.
FIXED_FROM_DESIGN = {
    ('string', 'light'):      ('#0B6E58', '#0A6551'),
    ('number', 'light'):      ('#9A4E00', '#8C4700'),
    ('null', 'light'):        ('#5C6175', '#55596C'),
    ('punctuation', 'light'): ('#63687C', '#55596A'),
    ('null', 'dark'):         ('#98A0BA', '#9EA6BE'),
    ('punctuation', 'dark'):  ('#868CA6', '#A1A6BA'),
}

SYNTAX = {
    'objectKey':   ('#5B44C8', '#B3A8F0'),   # blurple — the structure axis
    'string':      ('#0A6551', '#6ED3AE'),   # green-teal   (light fixed)
    'number':      ('#8C4700', '#EFB275'),   # amber        (light fixed)
    'boolean':     ('#9C2F72', '#E79AC9'),   # magenta
    'null':        ('#55596C', '#9EA6BE'),   # chroma-free grey (both fixed)
    'bracket':     ('#3A3D4D', '#CBCFE0'),
    'punctuation': ('#55596A', '#A1A6BA'),   # both fixed
}

# Washes that can sit under ANY syntax token.
WASHES = {
    'currentLineBg': ('#EFEFF5', '#1D2033'),
    'selectionBg':   ('#CBD3F0', '#2E3768'),
    # Search fills. The design gives these as alpha over the ground; flattened here.
    # Alphas are REDUCED from the design (light .38/.55, dark .34/.42 -> .37/.51, .20/.24).
    # At the design's values the matched key text fell to 2.87:1 on the dark active fill:
    # in dark mode a LIGHTER fill fights light text, so a dark saturated fill plus the
    # bright activeMatchRing is the correct dark treatment, not a compromise. Active stays
    # the heavier of the two tiers and additionally carries the ring.
    'searchMatchBg': (composite((232, 195, 60, 0.37), '#f7f7fa'),
                      composite((201, 162, 46, 0.20), '#161826')),
    'activeMatchBg': (composite((240, 168, 42, 0.51), '#f7f7fa'),
                      composite((240, 194, 74, 0.24), '#161826')),
}
# Which tokens each wash can actually sit under. currentLine and selection span whole
# lines, so every token must clear them. A search fill lands on the matched span only.
UNIVERSAL_WASHES = ['currentLineBg', 'selectionBg']
SEARCH_WASHES = ['searchMatchBg', 'activeMatchBg']
SEARCHABLE_TOKENS = ['objectKey', 'string']

# 1px edges and rings. These are borders, not fills — they never sit under text, so they
# are non-text indicators held to >=3:1.
EDGES = {
    'currentLineEdge': ('#DEDEE8', '#2A2E45', 'edge'),
    'matchedBracketRing': ('#6E5FD8', '#8C86D6', 'ui'),
    'activeMatchRing': ('#A85A00', '#F0C24A', 'ui'),
    'errorUnderline': ('#C22E2E', '#F2705E', 'diagnostic'),
    'foldMarker': ('#8A8FA3', '#8B92AC', 'ui'),
}

# The design reuses syntax hues for the diff set: modified is the number amber,
# type-changed the object-key blurple, added/removed the valid/invalid pair.
SEMANTICS = {
    'valid':           ('#1C7A4B', '#5FD39B'),
    'invalid':         ('#C22E2E', '#F2705E'),
    'diffAdded':       ('#1C7A4B', '#5FD39B'),
    'diffRemoved':     ('#C22E2E', '#F2705E'),
    'diffModified':    ('#8C4700', '#EFB275'),
    'diffTypeChanged': ('#5B44C8', '#B3A8F0'),
}

fails = []
flag = lambda ok: 'PASS' if ok else '**FAIL**'

for mode, idx in (('light', 0), ('dark', 1)):
    print(f'\n{"="*100}\n{mode.upper()}   editor ground {BG[mode]}\n{"="*100}')
    hdr = f'{"token":<14}{"hex":<10}{"bare":>7}'
    for w in WASHES:
        hdr += f'{w.replace("Bg",""):>15}'
    hdr += f'{"worst":>7}{"C*":>6}{"hue":>6}  result'
    print(hdr)
    print('-' * 100)
    for name, pair in SYNTAX.items():
        hx = pair[idx]
        bare = contrast(hx, BG[mode])
        on = {w: contrast(hx, WASHES[w][idx]) for w in WASHES}
        applicable = [on[w] for w in UNIVERSAL_WASHES]
        if name in SEARCHABLE_TOKENS:
            applicable += [on[w] for w in SEARCH_WASHES]
        wr = min([bare] + applicable)
        ch = chroma(hx)
        ok = wr >= 4.5 and ch <= CHROMA_MAX
        if not ok:
            fails.append(f'{mode}/{name}: worst {wr:.2f} (need 4.5), C* {ch:.0f} (max {CHROMA_MAX:.0f})')
        row = f'{name:<14}{hx:<10}{bare:>7.2f}' + ''.join(f'{on[w]:>15.2f}' for w in WASHES)
        note = ''
        if (name, mode) in FIXED_FROM_DESIGN:
            note = f'  (design {FIXED_FROM_DESIGN[(name, mode)][0]} -> fixed)'
        print(row + f'{wr:>7.2f}{ch:>6.0f}{hue_deg(hx):>6.0f}  {flag(ok)}{note}')

    print(f'\n{"wash":<20}{"hex":<10}{"vs ground":>10}  requirement            result')
    print('-' * 100)
    for name, pair in WASHES.items():
        hx = pair[idx]
        c = contrast(hx, BG[mode])
        if name in UNIVERSAL_WASHES:
            ok, req = c <= 1.75, 'subtle <=1.75:1'
        else:
            ok, req = True, 'highlight - see token rows'
        if not ok:
            fails.append(f'{mode}/{name}: {c:.2f} exceeds the 1.75 subtlety ceiling')
        print(f'{name:<20}{hx:<10}{c:>10.2f}  {req:<22} {flag(ok)}')

    print(f'\n{"edge / indicator":<20}{"hex":<10}{"vs ground":>10}{"C*":>6}  requirement            result')
    print('-' * 100)
    for name, (lt, dk, kind) in EDGES.items():
        hx = lt if mode == 'light' else dk
        c = contrast(hx, BG[mode])
        ch = chroma(hx)
        if kind == 'edge':
            ok, req = c <= 1.75, 'subtle <=1.75:1'
        elif kind == 'diagnostic':
            ok, req = c >= 3.0, '>=3:1, chroma exempt'
        else:
            ok, req = c >= 3.0 and ch <= CHROMA_MAX, f'>=3:1, C*<={CHROMA_MAX:.0f}'
        if not ok:
            fails.append(f'{mode}/{name}: {c:.2f} / C* {ch:.0f} vs {req}')
        marginal = '  <- exactly at the floor' if 2.995 <= c <= 3.02 else ''
        print(f'{name:<20}{hx:<10}{c:>10.2f}{ch:>6.0f}  {req:<22} {flag(ok)}{marginal}')

print(f'\n{"="*100}\nHUE SEPARATION — the design\'s type-grammar logic\n{"="*100}')
chromatic = ['objectKey', 'string', 'number', 'boolean']
for mode, idx in (('light', 0), ('dark', 1)):
    print(f'-- {mode}')
    for i, a in enumerate(chromatic):
        for b in chromatic[i + 1:]:
            ha, hb = SYNTAX[a][idx], SYNTAX[b][idx]
            dh = abs(hue_deg(ha) - hue_deg(hb))
            dh = min(dh, 360 - dh)
            need = 40 if {a, b} == {'objectKey', 'string'} else 25
            ok = dh >= need
            if not ok:
                fails.append(f'{mode}: {a}/{b} hue delta {dh:.0f} (need {need})')
            print(f'   {a:<11} vs {b:<11} {dh:>5.0f} deg  (need {need})  {flag(ok)}')

print(f'\n{"="*100}\nCOLOUR-VISION CHECK — the six semantics\n{"="*100}')
print('The design separates added/removed by glyph, by gutter sign (+/-), and by row-tint')
print('lightness as well as by hue. These numbers are why all three are load-bearing.')
for mode, idx in (('light', 0), ('dark', 1)):
    print(f'\n-- {mode} (ground {BG[mode]})')
    print(f'{"semantic":<18}{"hex":<10}{"deuter.":<10}{"protan.":<10}{"vs ground":>10}')
    print('-' * 100)
    for name, pair in SEMANTICS.items():
        hx = pair[idx]
        c = contrast(hx, BG[mode])
        if c < 4.5:
            fails.append(f'{mode}/semantic {name}: {c:.2f} vs 4.5 (label text)')
        print(f'{name:<18}{hx:<10}{simulate(hx,"deuteranopia"):<10}'
              f'{simulate(hx,"protanopia"):<10}{c:>10.2f}')
    diff4 = ['diffAdded', 'diffRemoved', 'diffModified', 'diffTypeChanged']
    print('   worst pairwise separation among the diff four:')
    for vision in ('normal', 'deuteranopia', 'protanopia', 'grayscale'):
        worst, pair = 99, None
        for i, a in enumerate(diff4):
            for b in diff4[i + 1:]:
                ca, cb = SEMANTICS[a][idx], SEMANTICS[b][idx]
                if vision in CVD:
                    ca, cb = simulate(ca, vision), simulate(cb, vision)
                r = contrast(ca, cb)
                if r < worst:
                    worst, pair = r, (a, b)
        verdict = 'colour alone sufficient' if worst >= 1.6 else 'colour alone INSUFFICIENT -> glyph + sign + label'
        print(f'      {vision:<14}{pair[0]:<16}/{pair[1]:<17}{worst:.2f}  {verdict}')

print(f'\n{"="*100}')
if fails:
    print(f'{len(fails)} FAILURE(S):')
    for f in fails:
        print('  -', f)
else:
    print('ALL CHECKS PASS')
print('=' * 100)
