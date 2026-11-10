"""효과음·배경음을 코드로 합성해 assets/sfx, assets/music 에 wav로 쓴다.
python3 tools/sound/gen.py   (외부 음원 없음, 표준 라이브러리만. 같은 결과가 나오게 난수 씨앗 고정)
"""
import array, math, os, random, wave

SR = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets')


def write(path, data, sr=SR, norm=0.9):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    peak = max(1e-6, max(abs(x) for x in data))
    g = norm / peak
    a = array.array('h', (int(max(-1.0, min(1.0, x * g)) * 32000) for x in data))
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(a.tobytes())


def osc(kind, ph):
    p = ph % 1.0
    if kind == 'sin':
        return math.sin(2 * math.pi * p)
    if kind == 'tri':
        return 4 * abs(p - 0.5) - 1
    if kind == 'sq':
        return 1.0 if p < 0.5 else -1.0
    if kind == 'pul':
        return 1.0 if p < 0.25 else -1.0
    if kind == 'saw':
        return 2 * p - 1
    return 0.0


def env(t, dur, a=0.005, r=0.05):
    if t < a:
        return t / a
    if t > dur - r:
        return max(0.0, (dur - t) / r)
    return 1.0


def tone(dur, f0, f1=None, kind='sq', vol=0.5, a=0.005, r=0.05, decay=0.0):
    n = int(dur * SR)
    f1 = f1 or f0
    out, ph = [], 0.0
    for i in range(n):
        t = i / SR
        f = f0 * (f1 / f0) ** (t / dur)
        ph += f / SR
        v = osc(kind, ph) * vol * env(t, dur, a, r)
        if decay:
            v *= math.exp(-decay * t)
        out.append(v)
    return out


def noise(dur, vol=0.5, lp=0.5, seed=1, a=0.005, r=0.05, decay=0.0):
    rnd = random.Random(seed)
    out, y = [], 0.0
    n = int(dur * SR)
    for i in range(n):
        t = i / SR
        y += (rnd.uniform(-1, 1) - y) * lp
        v = y * vol * env(t, dur, a, r)
        if decay:
            v *= math.exp(-decay * t)
        out.append(v)
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    out = [0.0] * n
    for p in parts:
        for i, x in enumerate(p):
            out[i] += x
    return out


def seq(*parts):
    out = []
    for p in parts:
        out += p
    return out


def silence(d):
    return [0.0] * int(d * SR)


def note_hz(n):
    """'C4' 같은 이름 → 주파수"""
    names = {'C': -9, 'D': -7, 'E': -5, 'F': -4, 'G': -2, 'A': 0, 'B': 2}
    k = names[n[0]]
    i = 1
    if n[i] == '#':
        k += 1; i += 1
    elif n[i] == 'b':
        k -= 1; i += 1
    octave = int(n[i:])
    return 440.0 * 2 ** ((k + (octave - 4) * 12) / 12)


# ───────────── 효과음 ─────────────

def engine():
    """떠 있는 보드의 부드러운 웅 소리 (이어 붙여 반복)"""
    f = 110.0
    cycles = 55
    n = int(round(cycles / f * SR))
    out = []
    for i in range(n):
        ph = i * cycles / n
        v = 0.55 * osc('sin', ph) + 0.25 * osc('tri', ph * 2) + 0.12 * osc('sin', ph * 3.0)
        v *= 0.85 + 0.15 * math.sin(2 * math.pi * i * 5 / n)
        out.append(v)
    return out


def skid():
    """슬라이드 중 쉬익 (이어 붙여 반복)"""
    n = int(1.2 * SR)
    rnd = random.Random(5)
    out, lo1, lo2 = [], 0.0, 0.0
    for i in range(n):
        x = rnd.uniform(-1, 1)
        lo1 += (x - lo1) * 0.35
        lo2 += (lo1 - lo2) * 0.08
        out.append((lo1 - lo2) * (0.8 + 0.2 * math.sin(2 * math.pi * i * 3 / n)))
    m = int(0.08 * SR)
    for i in range(m):
        k = i / m
        out[i] = out[i] * k + out[n - m + i] * (1 - k)
    return out[: n - m]


def slide():
    return mix(noise(0.35, 0.5, 0.3, 7, 0.01, 0.25), tone(0.35, 700, 400, 'tri', 0.12, 0.01, 0.25))


def jump():
    return mix(tone(0.22, 260, 820, 'sq', 0.28, 0.003, 0.1), tone(0.22, 520, 1640, 'sin', 0.12, 0.003, 0.1))


def land():
    return mix(noise(0.18, 0.7, 0.12, 9, 0.002, 0.14, decay=14), tone(0.16, 140, 60, 'sin', 0.5, 0.002, 0.12))


def whoosh():
    rnd = random.Random(13)
    dur = 0.4
    n = int(dur * SR)
    out, lo = [], 0.0
    for i in range(n):
        t = i / SR
        cut = 0.05 + 0.5 * math.sin(math.pi * t / dur)
        lo += (rnd.uniform(-1, 1) - lo) * cut
        out.append(lo * math.sin(math.pi * t / dur))
    return out


def judge0():   # GOOD
    return seq(tone(0.08, note_hz('E5'), kind='pul', vol=0.3), tone(0.2, note_hz('A5'), kind='pul', vol=0.3, r=0.15))


def judge1():   # NICE
    return seq(*[tone(0.07, note_hz(n), kind='sq', vol=0.28, r=0.04) for n in ['C5', 'E5', 'G5']], tone(0.25, note_hz('C6'), kind='sq', vol=0.28, r=0.2))


def judge2():   # EXCELLENT
    notes = ['C6', 'E6', 'G6', 'C7', 'G6', 'C7', 'E7']
    mel = seq(*[tone(0.055, note_hz(n), kind='pul', vol=0.26, r=0.03) for n in notes], tone(0.4, note_hz('G7') / 2, kind='pul', vol=0.24, r=0.3))
    sparkle = seq(silence(0.1), *[tone(0.04, note_hz(n) * 2, kind='sin', vol=0.12, r=0.03) for n in ['E6', 'G6', 'C7', 'E7', 'G7', 'C7']])
    return mix(mel, sparkle)


def miss():
    return seq(tone(0.16, note_hz('E4'), note_hz('D4'), kind='sq', vol=0.3), tone(0.4, note_hz('C4'), note_hz('A3'), kind='sq', vol=0.3, r=0.25))


def fall():
    return tone(0.9, 1400, 180, 'tri', 0.35, 0.01, 0.3)


def dash():
    return mix(tone(0.3, 500, 1500, 'sq', 0.22, 0.005, 0.15), noise(0.3, 0.3, 0.5, 4, 0.005, 0.18))


def boost():
    return mix(noise(0.9, 0.7, 0.25, 3, 0.02, 0.4), tone(0.9, 180, 640, 'saw', 0.25, 0.01, 0.4))


def gain():
    return seq(tone(0.09, note_hz('E5'), kind='pul', vol=0.35), tone(0.18, note_hz('B5'), kind='pul', vol=0.35, r=0.12))


def beep():
    return tone(0.22, note_hz('A4'), kind='sq', vol=0.4, r=0.08)


def go():
    return tone(0.6, note_hz('A5'), kind='sq', vol=0.4, r=0.3)


def coin():
    return seq(tone(0.06, note_hz('B5'), kind='sq', vol=0.3), tone(0.16, note_hz('E6'), kind='sq', vol=0.3, r=0.12))


def bump():
    return mix(noise(0.2, 0.9, 0.08, 9, 0.002, 0.16, decay=12), tone(0.16, 150, 60, 'sin', 0.6, 0.002, 0.12))


def lap():
    return seq(*[tone(0.1, note_hz(n), kind='pul', vol=0.3, r=0.06) for n in ['D5', 'F#5', 'A5']], tone(0.25, note_hz('D6'), kind='pul', vol=0.3, r=0.2))


def finish():
    notes = [('A4', 0.12), ('D5', 0.12), ('F#5', 0.12), ('A5', 0.3), ('F#5', 0.12), ('A5', 0.6)]
    mel = seq(*[tone(d, note_hz(n), kind='pul', vol=0.3, r=0.05) for n, d in notes])
    bass = seq(*[tone(d, note_hz(n) / 4, kind='tri', vol=0.4, r=0.05) for n, d in notes])
    return mix(mel, bass)


def click():
    return tone(0.05, 900, 600, 'sq', 0.25, 0.001, 0.03)


def tick():
    return tone(0.03, 1500, kind='sin', vol=0.2, a=0.001, r=0.02)


def buy():
    return seq(coin(), tone(0.08, note_hz('G6'), kind='sq', vol=0.25), tone(0.3, note_hz('C7'), kind='sq', vol=0.25, r=0.25))


def nope():
    return seq(tone(0.1, 220, kind='sq', vol=0.3), tone(0.2, 165, kind='sq', vol=0.3, r=0.1))


def item():
    return seq(*[tone(0.05, note_hz(n), kind='pul', vol=0.28, r=0.03) for n in ['C6', 'E6', 'G6', 'C7']])


def throw():
    return mix(noise(0.3, 0.6, 0.35, 21, 0.01, 0.2), tone(0.3, 300, 900, 'tri', 0.2, 0.01, 0.2))


def hit():
    return seq(mix(noise(0.12, 0.8, 0.2, 23, 0.002, 0.1, decay=12), tone(0.12, 220, 110, 'sq', 0.35, 0.002, 0.08)),
               tone(0.5, 700, 180, 'tri', 0.25, 0.01, 0.3))


def shield():
    return mix(tone(0.45, 880, 1320, 'sin', 0.25, 0.01, 0.3), tone(0.45, 1320, 1760, 'sin', 0.15, 0.05, 0.3))


def lucky():
    """행운 상자 열기: 또르르 올라가다 짠"""
    up = seq(*[tone(0.045, note_hz(n), kind='pul', vol=0.22, r=0.02) for n in ['C5', 'D5', 'E5', 'F5', 'G5', 'A5', 'B5', 'C6']])
    ta = mix(tone(0.6, note_hz('C6'), kind='sq', vol=0.22, r=0.4), tone(0.6, note_hz('E6'), kind='sq', vol=0.16, r=0.4), tone(0.6, note_hz('G6'), kind='sq', vol=0.14, r=0.4))
    return seq(up, ta)


def levelup():
    notes = [('G5', 0.1), ('C6', 0.1), ('E6', 0.1), ('G6', 0.25), ('E6', 0.1), ('G6', 0.5)]
    return mix(seq(*[tone(d, note_hz(n), kind='pul', vol=0.28, r=0.05) for n, d in notes]),
               seq(*[tone(d, note_hz(n) / 2, kind='tri', vol=0.3, r=0.05) for n, d in notes]))


# ───────────── 배경음 (새로 지은 곡) ─────────────

def parse_mel(text):
    """'E5:.5 -:1 G5:1/3' → [(음 또는 None, 박)]"""
    out = []
    for tok in text.split():
        n, d = tok.split(':')
        if '/' in d:
            x, y = d.split('/')
            b = float(x or 1) / float(y)
        else:
            b = float(d)
        out.append((None if n == '-' else n, b))
    return out


def song(bpm, sections, lead='pul', lead_vol=0.17, bass_vol=0.3, seed=1):
    """구역마다 {bars, melody, chords(마디마다 'E2 E3 G3 B3'), drums(16칸: k 큰북, K 큰북+심벌, s 작은북, h 하이햇), arp, pump}
    pump=True면 베이스가 8분으로 근음·옥타브를 번갈아 친다(달리는 느낌)."""
    beat = 60.0 / bpm
    total_beats = sum(sec['bars'] * 4 for sec in sections)
    total = int(total_beats * beat * SR) + SR
    out = [0.0] * total
    rnd = random.Random(seed)

    def add(start_beat, part, gain=1.0):
        s0 = int(start_beat * beat * SR)
        for i, x in enumerate(part):
            j = s0 + i
            if j < total:
                out[j] += x * gain

    pos = 0.0
    for sec in sections:
        bars = sec['bars']
        chords = [c.split() for c in sec['chords']]
        for b in range(bars):
            ch = chords[b % len(chords)]
            root = note_hz(ch[0])
            bar0 = pos + b * 4
            # 베이스
            if sec.get('pump', True):
                for e in range(8):
                    f = root * (2 if e % 2 else 1)
                    add(bar0 + e * 0.5, tone(beat * 0.42, f, kind='sq' if e % 2 else 'tri', vol=bass_vol * (0.55 if e % 2 else 1.0), r=0.02))
            else:
                for e in range(4):
                    add(bar0 + e, tone(beat * 0.9, root, kind='tri', vol=bass_vol, r=0.05))
            # 화음 (뒷박 짧게)
            ups = [note_hz(n) for n in ch[1:]]
            for e in range(4):
                for f in ups:
                    add(bar0 + e + 0.5, tone(beat * 0.22, f, kind='sq', vol=0.035, r=0.03))
            # 아르페지오 (16분)
            if sec.get('arp'):
                tones = ups + [u * 2 for u in ups]
                for q in range(16):
                    add(bar0 + q * 0.25, tone(beat * 0.2, tones[q % len(tones)] * 2, kind='pul', vol=0.045, r=0.02))
            # 북 (16칸)
            pat = sec.get('drums', '')
            for q, c in enumerate(pat[:16]):
                t = bar0 + q * 0.25
                if c in 'kK':
                    add(t, tone(0.11, 150, 42, 'sin', 0.55, 0.001, 0.07))
                if c == 'K':
                    add(t, noise(0.5, 0.2, 0.9, rnd.randint(0, 9999), 0.001, 0.4, decay=5))
                if c == 's':
                    add(t, mix(noise(0.13, 0.38, 0.75, rnd.randint(0, 9999), 0.001, 0.09, decay=18), tone(0.08, 190, 150, 'tri', 0.18, 0.001, 0.06)))
                if c in 'hks.' and q % 2 == 0:
                    add(t, noise(0.025, 0.05, 0.95, rnd.randint(0, 9999), 0.001, 0.02))
                if c == 'h':
                    add(t, noise(0.04, 0.09, 0.95, rnd.randint(0, 9999), 0.001, 0.03))
        # 멜로디
        t = pos
        for n, d in parse_mel(sec['melody']):
            if n:
                add(t, tone(d * beat * 0.9, note_hz(n), kind=lead, vol=lead_vol, a=0.006, r=0.03))
                # 살짝 늦은 메아리
                add(t + 0.75, tone(d * beat * 0.8, note_hz(n), kind=lead, vol=lead_vol * 0.22, a=0.006, r=0.03))
            t += d
        pos += bars * 4
    return out[: int(total_beats * beat * SR)]



def title_music():
    """처음 화면: 밝은 F장조 팝, 118 BPM"""
    F, C, Dm, Bb, Am, Gm = 'F2 A4 C5 F5', 'C3 G4 C5 E5', 'D3 A4 D5 F5', 'A#2 A#4 D5 F5', 'A2 A4 C5 E5', 'G2 A#4 D5 G5'
    secs = [
        {'bars': 8, 'chords': [F, C, Dm, Bb, F, C, Bb, C], 'drums': 'k...s.k.k...s...', 'pump': False,
         'melody': 'C6:1 A5:.5 C6:.5 D6:1 C6:1 G5:1.5 A5:.5 G5:1 E5:1 F5:.5 G5:.5 A5:1 D6:1 C6:.5 A#5:.5 A5:1 F5:.5 G5:.5 A5:1 C6:1 '
                   'C6:1 A5:.5 C6:.5 F6:1 E6:1 D6:1 C6:.5 A#5:.5 A5:1 G5:1 A#5:.5 A5:.5 G5:.5 F5:.5 D5:1 F5:1 G5:.5 A5:.5 G5:1 E5:1 C5:1'},
        {'bars': 8, 'chords': [Dm, Bb, F, C, Dm, Bb, Gm, C], 'drums': 'k.h.s.h.k.k.s.h.', 'arp': True,
         'melody': 'D6:.5 E6:.5 F6:1 E6:.5 D6:.5 C6:1 A#5:.5 C6:.5 D6:1 A5:1 F5:1 A5:.5 C6:.5 F6:1 E6:1 G6:1 E6:.5 C6:.5 E6:1 '
                   'D6:.5 E6:.5 F6:1 A6:1 G6:.5 F6:.5 F6:1 D6:1 A#5:1 C6:.5 D6:.5 A#5:.5 G5:.5 A#5:.5 C6:.5 C6:2 E6:2'},
    ]
    return song(118, secs, lead='tri', lead_vol=0.19, seed=2)


def race_music():
    """경주: 통통 튀는 D장조, 156 BPM"""
    D, A, Bm, G, Em, Fs = 'D3 F#4 A4 D5', 'A2 E4 A4 C#5', 'B2 F#4 B4 D5', 'G2 G4 B4 D5', 'E3 G4 B4 E5', 'F#2 F#4 A#4 C#5'
    secs = [
        {'bars': 4, 'chords': [D, A, Bm, G], 'drums': 'k.h.s.h.k.h.s.hs', 'pump': True,
         'melody': 'A5:.5 D6:.5 -:.5 D6:.5 C#6:.5 D6:.5 E6:1 F#6:.5 E6:.5 D6:.5 C#6:.5 A5:1 -:1 B5:.5 D6:.5 F#6:.5 D6:.5 B5:1 A5:1 G5:.5 B5:.5 D6:.5 E6:.5 F#6:2'},
        {'bars': 8, 'chords': [D, A, Bm, G, Em, A, D, A], 'drums': 'k.h.s.hkk.h.s.h.',
         'melody': 'F#6:.5 E6:.5 D6:.5 E6:.5 F#6:1 A6:1 E6:.5 C#6:.5 A5:.5 C#6:.5 E6:2 D6:.5 B5:.5 F#5:.5 B5:.5 D6:1 F#6:1 G6:.5 F#6:.5 E6:.5 D6:.5 B5:2 '
                   'G5:.5 B5:.5 E6:.5 B5:.5 G6:1 F#6:.5 E6:.5 E6:.5 C#6:.5 A5:.5 C#6:.5 E6:1 G6:1 F#6:.5 D6:.5 A5:.5 D6:.5 F#6:1 A6:1 G6:1 F#6:.5 E6:.5 C#6:2'},
        {'bars': 8, 'chords': [G, A, Fs, Bm, G, A, Bm, A], 'drums': 'kshskshskshsKshs', 'arp': True,
         'melody': 'B5:1 D6:.5 G6:.5 F#6:1 E6:1 C#6:1 E6:.5 A6:.5 G6:1 F#6:1 A#5:1 C#6:.5 F#6:.5 E6:1 C#6:1 D6:.5 E6:.5 F#6:.5 D6:.5 B5:2 '
                   'B5:.5 D6:.5 G6:1 B6:1 A6:.5 G6:.5 A6:.5 G6:.5 F#6:.5 E6:.5 C#6:1 A5:1 D6:.5 C#6:.5 B5:.5 D6:.5 F#6:1 B6:1 A6:2 E6:2'},
    ]
    return song(156, secs, lead='pul', seed=5)


def sky_music():
    """구름 섬: 둥실둥실 G장조, 138 BPM"""
    G, D, Em, C, Am, B = 'G2 B4 D5 G5', 'D3 A4 D5 F#5', 'E3 B4 E5 G5', 'C3 C5 E5 G5', 'A2 C5 E5 A5', 'B2 B4 D#5 F#5'
    secs = [
        {'bars': 8, 'chords': [G, D, Em, C, G, D, C, D], 'drums': 'k...s..hk.h.s...', 'arp': True, 'pump': False,
         'melody': 'D6:1.5 B5:.5 G5:1 B5:1 A5:1.5 F#5:.5 D5:2 E5:1 G5:1 B5:1 E6:1 E6:1 D6:.5 C6:.5 G5:2 '
                   'D6:1.5 B5:.5 G6:1 F#6:1 E6:1 D6:1 A5:2 C6:1 B5:.5 A5:.5 G5:1 E5:1 F#5:2 A5:2'},
        {'bars': 8, 'chords': [C, D, Em, B, C, D, G, D], 'drums': 'k.h.s.hkk.h.s.h.', 'arp': True,
         'melody': 'E6:.5 G6:.5 E6:1 C6:1 G5:1 F#6:.5 A6:.5 F#6:1 D6:1 A5:1 G6:.5 F#6:.5 E6:.5 D6:.5 B5:1 G5:1 F#5:.5 A5:.5 D#6:1 B5:2 '
                   'E6:.5 G6:.5 C7:1 B6:1 G6:1 A6:.5 F#6:.5 D6:1 A5:1 F#6:1 G6:2 D6:1 B5:1 A5:2 D6:2'},
    ]
    return song(138, secs, lead='tri', lead_vol=0.2, seed=8)


def rush_music():
    """긴박한 곡: B단조 질주, 172 BPM (마지막 바퀴·어려운 트랙)"""
    Bm, G, A, Fs, Em, D = 'B2 B4 D5 F#5', 'G2 B4 D5 G5', 'A2 A4 C#5 E5', 'F#2 A#4 C#5 F#5', 'E3 B4 E5 G5', 'D3 A4 D5 F#5'
    secs = [
        {'bars': 4, 'chords': [Bm, Bm, G, A], 'drums': 'k.k.s.kk.k.ks.ss', 'pump': True,
         'melody': 'B5:.25 B5:.25 -:.5 B5:.5 D6:.5 C#6:.5 B5:.5 F#5:1 B5:.5 C#6:.5 D6:.5 E6:.5 F#6:1 E6:1 D6:.5 B5:.5 G5:.5 B5:.5 D6:1 C#6:1 A5:.5 C#6:.5 E6:.5 G6:.5 F#6:2'},
        {'bars': 8, 'chords': [Bm, G, D, A, Bm, G, Em, Fs], 'drums': 'kshskshskshsKshs', 'arp': True,
         'melody': 'F#6:.5 D6:.5 B5:.5 D6:.5 F#6:1 B6:1 G6:.5 D6:.5 B5:.5 D6:.5 G6:1 F#6:1 F#6:.5 E6:.5 D6:.5 E6:.5 F#6:.5 A6:.5 F#6:1 E6:.5 C#6:.5 A5:.5 C#6:.5 E6:2 '
                   'F#6:.5 D6:.5 B5:.5 D6:.5 F#6:1 B6:1 B6:.5 A6:.5 G6:.5 F#6:.5 G6:1 D6:1 E6:.5 G6:.5 B6:.5 G6:.5 E6:1 G6:1 F#6:.5 E6:.5 C#6:.5 A#5:.5 F#5:2'},
        {'bars': 8, 'chords': [G, A, Fs, Bm, G, A, Fs, Fs], 'drums': 'k.h.s.hkk.h.s.hs',
         'melody': 'D6:1 B5:.5 D6:.5 G6:1 F#6:1 E6:1 C#6:.5 E6:.5 A6:1 G6:1 F#6:.5 E6:.5 C#6:.5 A#5:.5 F#5:1 A#5:1 B5:.5 C#6:.5 D6:.5 F#6:.5 B6:2 '
                   'D6:.5 D6:.5 G6:1 B6:1 A6:.5 G6:.5 E6:.5 E6:.5 A6:1 C#7:1 B6:.5 A6:.5 A#6:1 F#6:1 C#6:1 E6:1 F#6:2 A#6:2'},
    ]
    return song(172, secs, lead='pul', seed=4)


def main():
    sfx = {'engine': engine, 'skid': skid, 'slide': slide, 'jump': jump, 'land': land, 'whoosh': whoosh,
           'judge0': judge0, 'judge1': judge1, 'judge2': judge2, 'miss': miss, 'fall': fall, 'dash': dash,
           'boost': boost, 'gain': gain, 'beep': beep, 'go': go, 'coin': coin, 'bump': bump, 'lap': lap, 'finish': finish,
           'click': click, 'tick': tick, 'buy': buy, 'nope': nope, 'item': item, 'throw': throw, 'hit': hit, 'shield': shield,
           'lucky': lucky, 'levelup': levelup}
    for name, fn in sfx.items():
        write(os.path.join(ROOT, 'sfx', name + '.wav'), fn())
    for name, fn in [('title', title_music), ('race', race_music), ('sky', sky_music), ('rush', rush_music)]:
        write(os.path.join(ROOT, 'music', name + '.wav'), fn(), norm=0.7)
    print('소리 %d개 + 곡 4개' % len(sfx))


if __name__ == '__main__':
    main()
