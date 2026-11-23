# Sphere Runner (Godot 4.7)

Native version of the Sphere Runner prototype. The web prototype in `../sphere-runner-web/` is the
design reference; this project ports it in phases.

## Open and run
1. Godot **4.7.2** (standard build). Import → select `sphere-runner/project.godot` → Run (F5).
2. Desktop controls: arrows / WASD (hold Up to float), E or Shift = ability, mouse drag works as a swipe (double-click = ability).
3. Phone: Android one-click deploy (Remote Deploy) or iOS export to Xcode on a Mac.

## Structure
Everything is built in code (no editor scenes besides `scenes/main.tscn`), so it stays readable.

| Script | What it does |
|---|---|
| `scripts/config.gd` | Autoload `Config`: all tuning (speeds, physics, difficulty, obstacle kinds, power-ups, characters, planets and bosses) |
| `scripts/main.gd` | Game state, run loop: movement, collisions, close calls, combo, score, camera, save |
| `scripts/planet.gd` | The rotating globe (low-poly terrain with colour patches and water), themed road, scenery kit per planet, placing items on the curve |
| `scripts/boss.gd` | Boss chase: the boss on the horizon, throws onto red markers, stomp waves, defeat when you run underneath |
| `scripts/spawner.gd` | Obstacle patterns (rows, ramps/roofs, corridor, zigzag, glowing floor, jump-slide, movers) and wave/calm pacing |
| `scripts/item.gd` | One obstacle/coin/surface: logical box for collisions + visual parts |
| `scripts/character.gd` | Block figure on a humanoid joint layout with blended poses (run, jump, float, slam, slide, land, crash) |
| `scripts/swipe_input.gd` | Swipes (vertical-friendly zones), taps, double-taps, hold |
| `scripts/hud.gd` | HUD, ability meter, power-up list, start menu (character, difficulty, sound), crash screen |
| `scripts/sfx.gd` | Synthesized sound effects, rendered once at startup (no audio files) |

## Self-test (headless)
```
godot --headless --path sphere-runner -- --autotest
```
Simulates a 2-minute invincible run (reports distance, laps, coins, close calls, obstacle kinds),
checks swipe directions, every power-up and each character's ability, a boss test on every planet
(chase, throws, defeat, hop to the next planet), running into a boss boulder, then a real run without input (must crash).

Screenshot at N seconds into a run: `godot --path sphere-runner -- --shot out.png 8` (add `menu` for the menu,
`char=smasher`, `power=orbit`, `ability` or `boss=N` for a boss test on planet N).

## Port status
- **Phase 1 (done):** core run: planet, lanes, jump/float/slam/slide/air dash/jump buffer, ramps and roofs,
  all obstacle patterns, glowing floors, movers, coins, close calls, combo, waves and calm stretches,
  difficulty, laps, block character, HUD, menu, best score.
- **Phase 2 (done):** power-ups (magnet, shield, orbit, x2), the three characters with their bodies, stats and
  abilities (Focus, Smash up to 5 s with debris, Super jump), ability meter and double-tap, character select,
  best score per character and difficulty, synthesized sound with an on/off toggle.
- **Phase 3 (done):** the four planets (Meadow, Dunes, Glacier, Ember) with low-poly terrain, themed road and
  scenery kits; laps per world, the boss chase (boss on the horizon from the final lap, throws onto red markers,
  stomp waves, per-boss tuning, run underneath to win), planet hop with flip and white flash, boss test buttons.
- **Phase 4:** XP, levels and skill trees, core shop, settings, balance stats.
