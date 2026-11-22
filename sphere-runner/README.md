# Sphere Runner — concept prototype (Godot 4)

Endless runner on a rotating globe. Plain cubes only — this is for testing the feel, not the look.

## Run it
1. Install **Godot 4.3 or newer** (standard build, not .NET): https://godotengine.org/download
2. Godot → **Import** → select `sphere-runner/project.godot` → **Run (F5)**.
3. Desktop controls: arrows / WASD, Space = jump/start. Mouse drag works as a swipe.

## Run it on a phone
- **Android:** Editor → *Manage Export Templates* → download. Set the Android SDK path in Editor Settings, add an Android export preset, plug in the phone (USB debugging on) and use the one-click **Remote Deploy** button.
- **iPhone:** add an iOS export preset, export an Xcode project on a Mac, open it in Xcode, select your phone and run (needs an Apple ID / Developer account for signing).

## Controls (touch)
| Swipe | Action |
|---|---|
| left / right | switch lane |
| up | jump |
| down | slide (or slam down while in the air) |
| tap | start / restart |

## Obstacles
| Colour | Shape | How to pass |
|---|---|---|
| Orange | low block | jump |
| Purple | floating bar | slide under |
| Red | tall wall | switch lane |
| Yellow | small cube | coin — collect |

## How it works
The player never moves forward. The globe rotates toward the camera, so obstacles rise over the horizon. Rows are spawned just past the horizon and deleted once they're behind you, so the run is endless. One lap = one full turn of the globe (~188 m); each lap adds speed.

## Tuning
All feel parameters are constants at the top of `main.gd`: globe size (`TRACK_R`), speed curve, jump height, gravity, gap between rows, spawn distance, swipe threshold.
