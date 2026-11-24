# Hero models

Made by the project owner with Tripo (generated, auto-rigged with Mixamo bone names, refined),
each with the same six in-place clips: Running, Jump, Running Slide, Stumble, Falling Back
Death, Victory. config.gd maps the game's moves to them (HERO_CLIPS); moves without a clip use
the block figure's poses (scripts/model_character.gd).

- `ninja.glb`: the Runner (about 5.8k triangles), recoloured grey and blue (tools/models/recolor.mjs).
- `bastion.glb`: the Smasher (about 6.1k triangles, broader, gold shoulder plates), black and red.
- `kestrel.glb`: the Jumper (about 6.0k triangles, taller, a ponytail out of the hood), recoloured
  white and green.

Licence: check Tripo's (and the clips' source) terms before release.
