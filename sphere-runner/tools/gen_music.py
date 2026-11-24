#!/usr/bin/env python3
"""Chiptune music for Sphere Runner, composed and rendered in code (no samples).

Each track: a chord progression, a triangle bass, pulse-wave arpeggios, a pulse lead
melody (motif + variation) and noise drums, in 8-bar loops that repeat seamlessly.
Output: assets/audio/music/<name>.ogg (needs numpy and ffmpeg).

    python3 tools/gen_music.py            # writes every track
"""
import os
import subprocess
import sys
import numpy as np

RATE = 32000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'audio', 'music')

SCALES = {
    'major': [0, 2, 4, 5, 7, 9, 11],
    'minor': [0, 2, 3, 5, 7, 8, 10],
    'harmonic': [0, 2, 3, 5, 7, 8, 11],
    'phrygian_dom': [0, 1, 4, 5, 7, 8, 10],
}

# name: key (midi root), scale, bpm, chords (scale degrees, 1 bar each), style
TRACKS = {
    'menu':    dict(root=60, scale='major', bpm=100, chords=[0, 5, 3, 4], drums='soft', lead=0.7, seed=1),
    'meadow':  dict(root=67, scale='major', bpm=140, chords=[0, 4, 5, 3], drums='pop', lead=1.0, seed=2),
    'dunes':   dict(root=62, scale='phrygian_dom', bpm=132, chords=[0, 1, 0, 6], drums='pop', lead=1.0, seed=3),
    'glacier': dict(root=69, scale='minor', bpm=118, chords=[0, 5, 2, 6], drums='soft', lead=0.85, seed=4),
    'ember':   dict(root=64, scale='minor', bpm=152, chords=[0, 5, 6, 0], drums='drive', lead=1.0, seed=5),
    'boss':    dict(root=60, scale='harmonic', bpm=166, chords=[0, 5, 6, 4], drums='drive', lead=1.0, seed=6),
}


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12.0)


def env(n, attack=0.004, release=0.05, sustain=1.0):
    t = np.arange(n) / RATE
    e = np.ones(n) * sustain
    a = int(attack * RATE)
    r = int(min(release, n / RATE / 2) * RATE)
    if a > 0:
        e[:a] *= np.linspace(0, 1, a)
    if r > 0:
        e[-r:] *= np.linspace(1, 0, r)
    return e


def pulse(f, n, duty=0.5, vib=0.0):
    t = np.arange(n) / RATE
    ph = np.cumsum(np.full(n, f) * (1 + vib * np.sin(2 * np.pi * 5.5 * t)) / RATE)
    return np.where((ph % 1.0) < duty, 1.0, -1.0)


def tri(f, n):
    ph = (np.arange(n) * f / RATE) % 1.0
    return 1.0 - 4.0 * np.abs(ph - 0.5)


def noise(n, rng, rate=1.0):
    hold = max(1, int(rate))
    v = rng.uniform(-1, 1, n // hold + 1)
    return np.repeat(v, hold)[:n]


def lowpass(x, a):
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):          # one-pole smoothing: takes the edge off square waves
        acc += a * (x[i] - acc)
        y[i] = acc
    return y


def chord_notes(root, scale, degree):
    sc = SCALES[scale]
    out = []
    for k in (0, 2, 4):
        d = degree + k
        out.append(root + sc[d % 7] + 12 * (d // 7))
    return out


def track(spec):
    rng = np.random.default_rng(spec['seed'])
    beat = 60.0 / spec['bpm']
    bar = 4 * beat
    bars = 8
    n = int(bars * bar * RATE)
    mix = {k: np.zeros(n) for k in ('bass', 'arp', 'lead', 'drums')}
    sc = SCALES[spec['scale']]
    root = spec['root']

    def add(ch, start_s, sig, gain):
        s = int(start_s * RATE)
        e = min(n, s + len(sig))
        mix[ch][s:e] += sig[:e - s] * gain

    progression = spec['chords'] * 2
    # Bass: root on eighths (driving) or quarters (soft), an octave jump on the off-beats
    for b, deg in enumerate(progression):
        notes = chord_notes(root - 24, spec['scale'], deg)
        step = beat / 2 if spec['drums'] != 'soft' else beat
        k = 0
        t = 0.0
        while t < bar - 1e-6:
            m = notes[0] + (12 if (k % 2 == 1 and spec['drums'] == 'drive') else 0)
            if spec['drums'] == 'pop' and k % 4 == 3:
                m = notes[2] - 12
            ln = int(step * 0.9 * RATE)
            add('bass', b * bar + t, tri(hz(m), ln) * env(ln, 0.002, 0.03), 0.42)
            t += step
            k += 1
    # Arpeggio: chord tones in sixteenths, one octave above middle
    for b, deg in enumerate(progression):
        notes = chord_notes(root, spec['scale'], deg)
        pattern = [0, 1, 2, 1] if spec['drums'] != 'drive' else [0, 1, 2, 3]
        notes = notes + [notes[0] + 12]
        for k in range(16):
            m = notes[pattern[k % 4] % len(notes)]
            ln = int(beat / 4 * 0.8 * RATE)
            add('arp', b * bar + k * beat / 4, pulse(hz(m), ln, 0.125) * env(ln, 0.001, 0.02), 0.10)
    # Lead: a 2-bar motif from chord tones and steps, repeated with a variation, ending home
    rhythms = [[1, 0.5, 0.5, 1, 1], [0.5, 0.5, 1, 0.5, 0.5, 1], [1.5, 0.5, 1, 1], [1, 1, 2]]
    motif = []
    deg_pos = 4   # scale index (relative), starts on the fifth
    for b in range(2):
        for dur in rhythms[rng.integers(0, len(rhythms))]:
            motif.append((dur, deg_pos))
            deg_pos += int(rng.choice([-2, -1, -1, 1, 1, 2]))
            deg_pos = max(0, min(9, deg_pos))
    phrase = []
    for rep in range(4):
        for dur, d in motif:
            shift = [0, 0, 2, -1][rep]
            phrase.append((dur, max(0, d + shift)))
    t = 0.0
    total = bars * 4
    for dur, d in phrase:
        if t >= total:
            break
        b = int(t // 4)
        chord = chord_notes(root + 12, spec['scale'], progression[b])
        m = root + 12 + sc[d % 7] + 12 * (d // 7)
        if abs(t - round(t)) < 1e-6 and int(t) % 4 == 0:      # bar starts: land on a chord tone
            m = min(chord, key=lambda c: abs(c - m))
        if t + dur >= total - 1e-6:                           # last note: home
            m = root + 12
        ln = int(min(dur, total - t) * beat * 0.92 * RATE)
        sig = pulse(hz(m), ln, 0.25, vib=0.004 if dur >= 1 else 0.0)
        add('lead', t * beat, sig * env(ln, 0.004, 0.06, 0.9), 0.16 * spec['lead'])
        t += dur
    # Drums
    style = spec['drums']
    for b in range(bars):
        for k in range(8):                     # eighth-note grid
            at = b * bar + k * beat / 2
            if k % 4 == 0 or (style == 'drive' and k % 2 == 0) or (style == 'pop' and k == 5):
                ln = int(0.18 * RATE)
                tt = np.arange(ln) / RATE
                kick = np.sin(2 * np.pi * np.cumsum(150 * np.exp(-tt * 28) + 45) / RATE) * np.exp(-tt * 18)
                add('drums', at, kick, 0.55 if style != 'soft' else 0.35)
            if style != 'soft' and k % 4 == 2:
                ln = int(0.16 * RATE)
                tt = np.arange(ln) / RATE
                sn = noise(ln, rng, 2) * np.exp(-tt * 22) + 0.4 * np.sin(2 * np.pi * 190 * tt) * np.exp(-tt * 30)
                add('drums', at, sn, 0.30)
            ln = int(0.04 * RATE)
            tt = np.arange(ln) / RATE
            hat = noise(ln, rng, 1) * np.exp(-tt * 90)
            add('drums', at, hat, 0.10 if k % 2 == 0 else 0.07)
    out = (lowpass(mix['bass'], 0.25) + lowpass(mix['arp'], 0.35) + lowpass(mix['lead'], 0.4) + lowpass(mix['drums'], 0.6))
    out /= max(1e-6, np.max(np.abs(out))) / 0.82
    return out


def main(names):
    os.makedirs(OUT, exist_ok=True)
    for name in names:
        x = track(TRACKS[name])
        pcm = (np.clip(x, -1, 1) * 32767).astype('<i2').tobytes()
        dst = os.path.join(OUT, name + '.ogg')
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 's16le', '-ar', str(RATE), '-ac', '1', '-i', '-',
                        '-c:a', 'libvorbis', '-q:a', '3', dst], input=pcm, check=True)
        print(name, '%.1f s' % (len(x) / RATE), os.path.getsize(dst) // 1024, 'KB')


if __name__ == '__main__':
    main(sys.argv[1:] or list(TRACKS))
