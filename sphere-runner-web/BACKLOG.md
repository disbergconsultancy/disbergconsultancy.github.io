# Sphere Runner backlog

Status of ideas. Built items are listed briefly for context; the rest has design notes so it is ready to build.
The Godot project (`sphere-runner/`) is the main version; the web prototype stays as a quick test bed.

## Built
- Core run, obstacle patterns, waves, power-ups, three characters with abilities, sound.
- Four planets, planet hop, boss chase (boss on the horizon throws onto red markers; pass under it to win), boss test.
- Progression: XP and levels 1-20 per character (13 skill points), skill trees v2 (boss and XP nodes,
  capstones), core shop with coin wallet (Luck, Power-up duration, Stumble guard capped at 2), balance stats.
  See docs/progression.html.

---

## Next (in priority order)

### 1. Boss system: unique bosses with signature moves (IN PROGRESS)
**Built (Godot):** data model per boss (archetype, base throws, signature moves, rate), phases (base / signature
unlocked at 30% / enraged at 80%), threat budget (move costs), and all eight signature moves:
Stone Golem: Vine sweep; Sand Colossus: Rolling boulder, Meteor shower; Ice Titan: Ice lane, Quake rhythm, Decoy;
Magma Giant: Lava trail, Quake rhythm, Decoy, Gate slam (at the final pass). Fairness check with a bot (10 chases per
boss; all bosses 10/10). The check found and fixed an impossible attack (a 2-lane wall with the middle lane open
covered all three lanes, also fixed in the web prototype) and a quake rhythm overlapping the next throw; combos keep
the first throw's safe lane open, and a multi-part move blocks other attacks until it is over.
**Still to do:** the other archetypes, the boss forge for endless play.

Goal: every boss feels different, and we can make many more without hand-building each one.
A boss is **composed from parts**, all data-driven:

| Part | What it decides | Examples |
|---|---|---|
| **Archetype** | silhouette, how it moves, how you pass it | *Gate-walker* (today: straddles the track, run under it), *Roller* (rolls ahead, you overtake when it slows), *Flyer* (hovers above the track, drops things), *Burrower* (dives and pops up ahead), *Twins* (two smaller bosses on both sides) |
| **Base throws** | the common attacks and their weights | boulder (switch lane), 2-lane wall, log (jump), bar (slide), stomp wave (jump) |
| **Signature moves** | 1-2 moves only this boss does, themed to its planet | see library below |
| **Phases** | how it escalates during the chase | phase 1: base throws; phase 2: signature move unlocked; phase 3 (last stretch): enraged, combos |
| **Threat budget** | difficulty, set by planet and boss tier | each move has a cost; the budget sets how much threat per second the boss may spend |
| **Look** | colours, eyes, name | palette from the planet; name from a generator ("Moss Golem", "Cinder Colossus") |

**Signature move library** (each has a clear warning and an answer with the moves players already know):
- *Rolling boulder* (Dunes): a boulder rolls toward you down one lane and switches lane once (telegraphed). Answer: switch lane at the right moment.
- *Vine sweep* (Meadow): vines grow across two lanes at slide height. Answer: slide, or take the third lane.
- *Ice lane* (Glacier): one lane freezes for 16 m with a boulder at its end; no lane changes while on the ice. Answer: leave that lane before the ice.
- *Lava trail* (Ember): the boss leaves a glowing floor strip along a lane for ~20 m. Answer: stay out of it or jump across.
- *Meteor shower* (Dunes): four small meteors thrown one after another, never twice in the same lane. Answer: weave.
- *Quake rhythm*: three stomp waves in a beat. Answer: jump in rhythm.
- *Decoy marker* (late bosses): a marker shifts to another lane just before the throw lands. Answer: watch the throw, not only the marker.
- *Gate slam* (Gate-walker): at the final pass the legs slam onto the track leaving one gap (green marker); the gap moves once. Answer: follow the gap.

**Fair-play rules** (checked automatically in the self-test):
- At least ~1 s of warning at the current speed; markers always land between you and the boss.
- There is always an answer: a free lane, a jump or a slide. Never two answers needed at the same moment.
- Counters only use existing moves (lanes, jump, slide, slam, float).
- A simulated "perfect bot" must be able to clear every move and combination; if not, the generator rejects it.

**Generation:**
- The four current bosses become hand-tuned definitions using this system.
- After the fourth planet (endless play), a **boss forge** builds new bosses: archetype + planet signature moves
  + a rising threat budget + generated name and palette. That gives endless, unique bosses.
- Rewards: boss XP as now, a bonus for the first kill of each boss, boss missions (see 2).

### 2. Missions
- Three active missions at a time, shown on the menu and the crash screen.
- Types: counts ("collect 300 coins", "20 close calls", "smash 15 blocks", "jump 40 times"),
  feats ("beat the Golem without a stumble", "reach Glacier", "a 2 km run"),
  character missions ("10 close calls with the Runner") to encourage playing all three.
- Reward per mission: XP and coins. Completing all three: a set bonus and a new set.
  Option to discuss: a permanent score multiplier per completed set (Subway Surfers style), capped.

### 3. Daily rewards and first-run bonus
- Daily login streak (7-day cycle) with growing coin rewards; missing a day resets the streak.
- First runs of the day give double XP (e.g. the first 3 runs).
- Shown on the menu: "Day 4 of 7" and "2 double-XP runs left".

### 4. Daily challenge
- One fixed run per day, the same for everyone: a set seed, planet, boss and character, possibly a modifier
  ("only glowing floors", "double speed").
- Played with base stats (no skill tree), so it is a level playing field and a counterweight to RPG power.
- Unlimited attempts; best result of the day counts. A reward for finishing; a leaderboard later (see Later).

---

## Later
- **Cosmetics**: skins per character (colours, helmets, backpacks), trails; bought with coins. No effect on balance.
- **Planet Tour**: every few weeks one planet is featured with its own missions, an event reward and a limited skin
  (like Subway Surfers' World Tour). Freshness without new mechanics.
- **Leaderboards**: Game Center / Google Play Games. Separate boards per level bracket, and one for the daily
  challenge.
- **Boss earlier in a world**: let a boss appear in the distance before the final lap to set the stage.
- **Real models**: rigged character and boss models replacing the block figures (same poses and skeleton).

## Parked
- **Monetisation**: premium, ads or cosmetics only. To decide before building the cosmetics economy.

## Skipped (decided)
- Head starts, pay-to-continue, mystery boxes: they conflict with "skill decides".
- Core shop: Head start, Reflexes, Quick recovery.
