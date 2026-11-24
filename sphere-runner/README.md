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
| `scripts/progress.gd` | Autoload `Progress`: XP and levels, skill trees and their effects, core shop, balance stats, settings; saved in `user://save.cfg` |
| `scripts/config.gd` | Autoload `Config`: all tuning (speeds, physics, difficulty, obstacle kinds, power-ups, characters, planets and bosses) |
| `scripts/main.gd` | Game state, run loop: movement, collisions, close calls, combo, score, camera, save |
| `scripts/planet.gd` | The rotating globe (low-poly terrain with colour patches and water), themed road, scenery kit per planet, placing items on the curve |
| `scripts/boss.gd` | Boss chase and boss move system: phases (base throws, signature moves, enraged), threat budget per boss, base throws onto red markers, stomp waves, eight signature moves, Gate slam at the final pass, defeat when you run underneath |
| `scripts/spawner.gd` | Obstacle patterns (rows, ramps/roofs, corridor, zigzag, glowing floor, jump-slide, movers) and wave/calm pacing |
| `scripts/item.gd` | One obstacle/coin/surface: logical box for collisions + visual parts |
| `scripts/character.gd` | Block figure on a humanoid joint layout, toon animation: poses on springs (overshoot, follow-through), squash and stretch, one-off moves (takeoff, air-jump flip, lane hop, slide dust, landing dust, stumble, crash flop, cheer), menu idle |
| `scripts/ui_kit.gd` | Block-pixel UI kit: Pixelify Sans, block buttons and panels (9-patch textures), 8x8 pixel icons, segmented bars |
| `assets/ui/` | UI textures generated from the agreed designs (buttons, panels, tiles, icons, hero portraits) |
| `assets/fonts/` | Pixelify Sans (SIL Open Font License 1.1) |
| `scripts/hero.gd` | Hero models (KayKit, CC0): Runner = Ranger, Smasher = Barbarian, Jumper = Rogue. Animation clips (run, jump, land, lane dodge, slide, death, upper-body cheer and flinch) in an AnimationTree, with the block figure's toon layer on top. Menu setting "Hero models" switches between heroes and block figures |
| `assets/kaykit/` | KayKit Adventurers characters and Character Animations (Rig_Medium), by Kay Lousberg (www.kaylousberg.com), CC0 |
| `scripts/kit.gd` | Shared look: soft (bevelled) blocks used for every block in the game, and loading, fitting and tinting KayKit models |
| `assets/kit/` | KayKit Forest Nature, Platformer and Block Bits pieces (CC0, Kay Lousberg): scenery, cones and flags, jump barriers, red wall blocks, ramps and platforms, power-up models, textured boss blocks |
| `assets/bosses/` | Boss models (Tripo, supplied by the project owner; see its README for the licence note), simplified for mobile: Minotaur, Sand Wyvern, Ice Titan (ice golem), Magma Giant (lava monster). Animated in code in `boss.gd` |
| `scripts/swipe_input.gd` | Swipes (vertical-friendly zones), taps, double-taps, hold |
| `scripts/hud.gd` | HUD, ability meter, power-up list, boss bar, menu (character, difficulty, sound, boss test, stats), skill tree, core shop, crash screen |
| `scripts/sfx.gd` | Synthesized sound effects, rendered once at startup (no audio files) |

## Self-test (headless)
```
godot --headless --path sphere-runner -- --autotest
```
Simulates a 2-minute invincible run (reports distance, laps, coins, close calls, obstacle kinds),
checks swipe directions, every power-up and each character's ability, a boss test on every planet
(chase, throws, defeat, hop to the next planet), running into a boss boulder, levels and skill points,
skill effects (double jump, Meteor, Vault, Aftershock, Wrecking Ball), Stumble guard, XP and coins at game over,
a fairness check (a bot with perfect information plays every boss chase 10 times; all must be beatable),
then a real run without input (must crash). Note: the self-test writes to this machine's save file.

Screenshot at N seconds into a run: `godot --path sphere-runner -- --shot out.png 8` (add `menu` for the menu,
`char=smasher`, `power=orbit`, `ability`, `boss=N` for a boss test on planet N, or `menu skills` / `menu shop` / `menu over`, `move=<signature move>` with `boss=N`, e.g. `move=vine_sweep`, `meteor_shower`, `ice_lane`, `quake_rhythm`, `decoy`, `rolling_boulder`, `lava_trail`).

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
- **Phase 4 (done):** XP and levels 1-20 per character (~250 runs; 13 skill points), skill trees v2 (3 branches x 4
  tiers, boss and XP nodes, capstones), core shop with a coin wallet (Luck, Power-up duration, Stumble guard),
  balance stats, saved settings. Test buttons: +1 level, +500 coins, reset.
- **Boss system (started):** bosses composed from archetype, base throws, signature moves, phases and a threat
  budget (all in `config.gd`). Signature moves: Minotaur (was Stone Golem): Vine sweep; Sand Wyvern (was Sand Colossus): Rolling boulder, Meteor shower;
  Ice Titan: Ice lane, Quake rhythm, Decoy; Magma Giant: Lava trail, Quake rhythm, Decoy, Gate slam.
