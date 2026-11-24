#!/usr/bin/env python3
"""Picks the sound effects from Kenney's CC0 packs (Digital Audio, Impact Sounds, Interface Sounds,
Music Jingles; kenney.nl), levels them and writes assets/audio/sfx/<event>.ogg.

    python3 tools/pick_sfx.py <folder with the unzipped packs> assets/audio/sfx
"""
import subprocess, numpy as np, glob, sys, os
P, D = sys.argv[1], sys.argv[2]
PICK = {
 'jump': 'digital-audio/*/phaseJump1.ogg', 'close': 'digital-audio/*/highUp.ogg', 'power': 'digital-audio/*/powerUp9.ogg',
 'ready': 'digital-audio/*/powerUp8.ogg', 'ability': 'digital-audio/*/phaserUp7.ogg', 'shield': 'digital-audio/*/highDown.ogg',
 'throw': 'digital-audio/*/laser5.ogg', 'stomp': 'digital-audio/*/lowDown.ogg',
 'smash': 'impact-sounds/*/impactPunch_heavy_000.ogg', 'crash': 'impact-sounds/*/impactPlate_heavy_000.ogg',
 'stumble': 'impact-sounds/*/impactSoft_heavy_000.ogg',
 'land_grass': 'impact-sounds/*/footstep_grass_000.ogg', 'land_carpet': 'impact-sounds/*/footstep_carpet_000.ogg',
 'land_snow': 'impact-sounds/*/footstep_snow_000.ogg', 'land_concrete': 'impact-sounds/*/footstep_concrete_000.ogg',
 'combo': 'interface-sounds/*/confirmation_004.ogg', 'lap': 'interface-sounds/*/confirmation_001.ogg',
 'click': 'interface-sounds/*/click_003.ogg', 'tip': 'interface-sounds/*/question_001.ogg',
 'hop': 'music-jingles/*/8-Bit jingles/jingles_NES12.ogg', 'defeat': 'music-jingles/*/8-Bit jingles/jingles_NES08.ogg',
 'gameover': 'music-jingles/*/8-Bit jingles/jingles_NES11.ogg',
}
TARGET = {'click': -24, 'land_grass': -20, 'land_carpet': -20, 'land_snow': -20, 'land_concrete': -20, 'jump': -21}
for name, pat in PICK.items():
    src = glob.glob(os.path.join(P, pat))[0]
    x = np.frombuffer(subprocess.run(['ffmpeg','-loglevel','error','-i',src,'-f','f32le','-ac','1','-'],capture_output=True).stdout, dtype=np.float32)
    act = x[np.abs(x) > np.abs(x).max() * 0.05]
    rms_db = 20*np.log10(np.sqrt((act**2).mean()) + 1e-9)
    gain = TARGET.get(name, -16) - rms_db
    gain = min(gain, -20*np.log10(np.abs(x).max()+1e-9) - 1.0)   # never clip
    dst = os.path.join(D, name + '.ogg')
    subprocess.run(['ffmpeg','-y','-loglevel','error','-i',src,'-ac','1','-af','volume=%.1fdB' % gain,'-c:a','libvorbis','-q:a','4',dst], check=True)
    print('%-14s %+5.1f dB  %s' % (name, gain, os.path.basename(src)))
