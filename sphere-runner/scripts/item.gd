class_name Item
extends RefCounted
## One obstacle, coin or surface on the planet. The logical box (phi, x, y0..y1, hw, hd)
## is what collisions use; `parts` are the visual pieces placed along the curve.

var kind := ""
var phi := 0.0          # globe-local angle along the track
var x := 0.0            # sideways offset (lane centre)
var cx := 0.0           # rest position for moving blocks
var y0 := 0.0
var y1 := 0.0
var hw := 0.0           # half width
var hd := 0.0           # half depth along the track
var alive := true
var passed := false
var min_clear := 99.0   # closest clearance while passing (for close calls)
var parts: Array = []   # [{ "node": Node3D, "dm": float, "y": float, "dx": float, "spin": bool }]
var move_amp := 0.0
var move_speed := 0.0
var move_phase := 0.0
