# Model tools (Tripo exports and other .glb heroes)

Run `npm install` here once. Targets for a hero: about 10k triangles, 512-1024 px textures,
a humanoid rig with Mixamo bone names (Tripo's auto-rig gives these).

- `node pieces.mjs in.glb` lists the separate pieces of the mesh (size, centre, main bones).
- `node cut_parts.mjs in.glb out.glb show` paints the parts that stick out from the body
  (blades, scabbards, floor shards) in flat colours and prints them as numbered clusters;
  `node cut_parts.mjs in.glb out.glb cut 0 4 5` removes every cluster except the listed ones
  (and the flat shards on the floor). Used for the ninja: kept the back katana and the scarf.
- `node shrink.mjs in.glb out.glb 10000` for an unrigged, very dense export (Tripo's 1-2 M
  triangles): bakes the texture colours into vertex colours, drops the UV layout (its seams
  block simplification) and simplifies to the target with smooth normals. 60 MB -> 0.4 MB.

In the game a rigged hero is a `ModelCharacter` (scripts/model_character.gd): set `"model"`
and `"model_h"` on the character in config.gd. It takes the block figure's poses on its bones.
- `node cut_steel.mjs in.glb out.glb show|cut [maxY]` removes light steel (blade) colours below
  the face and above the feet: leftover blade bits.
- `node cut_webs.mjs in.glb out.glb show|cut` removes triangles whose corners follow different
  limbs (a hand and a leg): auto-rig leftovers that stretch into slivers when the hero runs.
