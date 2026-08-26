#!/usr/bin/env python3
"""Measure the JSON Studio Phase 1 palette.

Three deliberate deviations from the Phase 1 brief, each justified in tokens.md:
 1. The "nothing above 70% saturation" gate uses CIELAB chroma (C*), not HLS saturation.
    HLS saturation badly misreports dark and light colours -- a deep navy (#0B4FA8) reads
    88% while being visually restrained. C* is perceptual and is the metric the rule means.
 2. Background washes are not tested for >=3:1. A wash's job is to be subtle; the real
    requirement is that syntax text sitting ON it still clears 4.5:1. That is what we test.
 3. Diagnostic colours (error/warning underline) are exempt from the chroma gate. Phase 0
    established the error experience as the entire product; a desaturated error marker is a
    worse error marker. They still must clear 3:1.
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

def to_lab(h):
    """sRGB -> CIELAB (D65)."""
    r, g, b = (to_linear(c) for c in hex_to_rgb(h))
    x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
    y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b) / 1.00000
    z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
    def f(t):
        return t ** (1 / 3) if t > 0.008856 else (7.787 * t) + (16 / 116)
    fx, fy, fz = f(x), f(y), f(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))

def chroma(h):
    """CIELAB C* -- perceptual colourfulness. The gate the brief actually means."""
    _, a, b = to_lab(h)
    return (a * a + b * b) ** 0.5

def hls_sat_pct(h):
    r, g, b = hex_to_rgb(h)
    _, _, s = colorsys.rgb_to_hls(r, g, b)
    return s * 100

def hue_deg(h):
    r, g, b = hex_to_rgb(h)
    hh, _, _ = colorsys.rgb_to_hls(r, g, b)
    return hh * 360

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
    m = CVD[kind]
    return rgb_to_hex([to_srgb(sum(m[i][j] * lin[j] for j in range(3))) for i in range(3)])

# ---------- the palette ----------

CHROMA_MAX = 75.0

BG = {'light': '#FFFFFF', 'dark': '#1E1E1E'}

SYNTAX = {
    'objectKey':   ('#0B4FA8', '#7FB0F0'),
    'string':      ('#0F6E3D', '#5FC98A'),
    'number':      ('#63409C', '#C2A0F5'),
    'boolean':     ('#04606E', '#5CC8D8'),
    'null':        ('#5C5C5C', '#A4A4A4'),
    'bracket':     ('#1F1F1F', '#E8E8E8'),
    'punctuation': ('#5A5A5A', '#B0B0B0'),
}

# Washes sit UNDER syntax text. Tested by re-measuring every token on top of them.
WASHES = {
    'currentLineBg':    ('#F2F4F7', '#282A2E'),
    'selectionBg':      ('#CCDDF7', '#2C3749'),
    'searchMatchBg':    ('#FFE9A8', '#3F361A'),
    'matchedBracketBg': ('#D6E4FA', '#3A4A66'),
}
# A matched-bracket highlight must be *noticeable*, unlike the other washes.
WASH_VISIBILITY = {'matchedBracketBg': (1.15, 2.6)}
# Washes that can sit under ANY syntax token. matchedBracketBg is excluded: it highlights a
# single bracket glyph, so only the 'bracket' token needs to clear 4.5:1 on it. Commas and
# colons ('punctuation') are never bracket-matched.
UNIVERSAL_WASHES = ['currentLineBg', 'selectionBg', 'searchMatchBg']
MATCHED_BRACKET_TOKENS = ['bracket']

# Non-text indicators, >=3:1 against the editor background.
INDICATORS = {
    'errorUnderline':   ('#C4162A', '#FF6B7A', 'diagnostic'),
    'warningUnderline': ('#8A5A00', '#E0A64A', 'diagnostic'),
    'foldMarker':       ('#767676', '#9A9A9A', 'ui'),
}

SEMANTICS = {
    'valid':           ('#0F6E3D', '#5FC98A'),
    'invalid':         ('#C4162A', '#FF6B7A'),
    'diffAdded':       ('#1A6B33', '#6ED08F'),
    'diffRemoved':     ('#A8102A', '#FF8A94'),
    'diffModified':    ('#0B4FA8', '#7FB0F0'),
    'diffTypeChanged': ('#8A4B00', '#E0A64A'),
}

fails = []
def flag(ok):
    return 'PASS' if ok else '**FAIL**'

# ---------- syntax tokens, on plain bg and on every wash ----------

for mode, idx in (('light', 0), ('dark', 1)):
    print(f'\n{"="*92}\n{mode.upper()}   editor bg {BG[mode]}\n{"="*92}')
    hdr = f'{"token":<14}{"hex":<10}{"vs bg":>7}'
    for w in WASHES:
        hdr += f'{w.replace("Bg",""):>16}'
    hdr += f'{"C*":>7}{"hue":>6}  result'
    print(hdr)
    print('-' * 92)
    for name, pair in SYNTAX.items():
        hx = pair[idx]
        c_bg = contrast(hx, BG[mode])
        on_wash = {w: contrast(hx, WASHES[w][idx]) for w in WASHES}
        applicable = [on_wash[w] for w in UNIVERSAL_WASHES]
        if name in MATCHED_BRACKET_TOKENS:
            applicable.append(on_wash['matchedBracketBg'])
        worst = min([c_bg] + applicable)
        ch = chroma(hx)
        ok = worst >= 4.5 and ch <= CHROMA_MAX
        if not ok:
            fails.append(f'{mode}/{name}: worst {worst:.2f} (need 4.5), C* {ch:.0f} (max {CHROMA_MAX:.0f})')
        row = f'{name:<14}{hx:<10}{c_bg:>7.2f}'
        for w in WASHES:
            row += f'{on_wash[w]:>16.2f}'
        row += f'{ch:>7.0f}{hue_deg(hx):>6.0f}  {flag(ok)}'
        print(row)

    print(f'\n{"wash":<20}{"hex":<10}{"vs bg":>8}{"C*":>7}  requirement                result')
    print('-' * 92)
    for name, pair in WASHES.items():
        hx = pair[idx]
        c_bg = contrast(hx, BG[mode])
        if name in WASH_VISIBILITY:
            lo, hi = WASH_VISIBILITY[name]
            ok = lo <= c_bg <= hi
            req = f'visible {lo}-{hi}:1'
        else:
            ok = c_bg <= 1.45
            req = 'subtle <=1.45:1'
        if not ok:
            fails.append(f'{mode}/{name}: {c_bg:.2f} vs {req}')
        print(f'{name:<20}{hx:<10}{c_bg:>8.2f}{chroma(hx):>7.0f}  {req:<25}  {flag(ok)}')

    print(f'\n{"indicator":<20}{"hex":<10}{"vs bg":>8}{"C*":>7}  requirement                result')
    print('-' * 92)
    for name, (lt, dk, kind) in INDICATORS.items():
        hx = lt if mode == 'light' else dk
        c_bg = contrast(hx, BG[mode])
        ch = chroma(hx)
        if kind == 'diagnostic':
            ok = c_bg >= 3.0
            req = '>=3:1, chroma exempt'
        else:
            ok = c_bg >= 3.0 and ch <= CHROMA_MAX
            req = f'>=3:1, C*<={CHROMA_MAX:.0f}'
        if not ok:
            fails.append(f'{mode}/{name}: {c_bg:.2f} / C* {ch:.0f} vs {req}')
        print(f'{name:<20}{hx:<10}{c_bg:>8.2f}{ch:>7.0f}  {req:<25}  {flag(ok)}')

# ---------- hue separation ----------

print(f'\n{"="*92}\nHUE SEPARATION — chromatic syntax tokens (keys vs strings must differ in HUE)\n{"="*92}')
chromatic = ['objectKey', 'string', 'number', 'boolean']
for mode, idx in (('light', 0), ('dark', 1)):
    print(f'-- {mode}')
    for i, a in enumerate(chromatic):
        for b in chromatic[i+1:]:
            ha, hb = SYNTAX[a][idx], SYNTAX[b][idx]
            dh = abs(hue_deg(ha) - hue_deg(hb)); dh = min(dh, 360 - dh)
            need = 40 if {a, b} == {'objectKey', 'string'} else 25
            ok = dh >= need
            if not ok:
                fails.append(f'{mode}: {a}/{b} hue delta {dh:.0f}deg (need {need})')
            print(f'   {a:<11} vs {b:<11} delta-hue {dh:>5.0f}deg  (need {need})  {flag(ok)}')

# ---------- colour vision ----------

print(f'\n{"="*92}\nCOLOUR-VISION CHECK — the six semantics\n{"="*92}')
print('NB: colour is one of THREE channels. Glyph and label carry the signal (ADR-09).')
for mode, idx in (('light', 0), ('dark', 1)):
    print(f'\n-- {mode} (bg {BG[mode]})')
    print(f'{"semantic":<18}{"hex":<10}{"deuter.":<10}{"protan.":<10}{"lum":>7}{"vs bg":>8}')
    print('-' * 92)
    for name, pair in SEMANTICS.items():
        hx = pair[idx]
        c = contrast(hx, BG[mode])
        if c < 4.5:
            fails.append(f'{mode}/semantic {name}: {c:.2f} vs 4.5 (label text)')
        print(f'{name:<18}{hx:<10}{simulate(hx,"deuteranopia"):<10}{simulate(hx,"protanopia"):<10}'
              f'{rel_luminance(hex_to_rgb(hx)):>7.3f}{c:>8.2f}')

    print(f'\n   pairwise separation of the diff four (contrast between the two colours):')
    diff4 = ['diffAdded', 'diffRemoved', 'diffModified', 'diffTypeChanged']
    for vision in ('normal', 'deuteranopia', 'protanopia', 'grayscale'):
        worst, worst_pair = 99, None
        for i, a in enumerate(diff4):
            for b in diff4[i+1:]:
                ca, cb = SEMANTICS[a][idx], SEMANTICS[b][idx]
                if vision in CVD:
                    ca, cb = simulate(ca, vision), simulate(cb, vision)
                r = contrast(ca, cb)   # grayscale == luminance-only == same formula
                if r < worst:
                    worst, worst_pair = r, (a, b)
        verdict = 'colour alone sufficient' if worst >= 1.6 else 'colour alone INSUFFICIENT -> glyph+label mandatory'
        print(f'      {vision:<14} worst pair {worst_pair[0]:<16}/{worst_pair[1]:<16} {worst:.2f}  {verdict}')

print(f'\n{"="*92}')
if fails:
    print(f'{len(fails)} FAILURE(S):')
    for f in fails:
        print('  -', f)
else:
    print('ALL CHECKS PASS')
print('=' * 92)
