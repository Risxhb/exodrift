# Greybox Scale Guide

All gameplay dimensions use one Godot unit per meter. These values are provisional and must only change alongside `GAME_BIBLE.md`.

| Object | Length | Visual purpose |
|---|---:|---|
| Player carrier | 120 m | Dominant mobile base with readable side galleries |
| Frigate | 65 m | Escort/command hull, roughly half carrier length |
| Corvette | 42 m | Fast screen, visibly smaller than frigate |
| Fighter/drone | 8 m | Visible near carrier but subordinate at tactical scale |

The greybox battle spans roughly 12 km. Carrier and capital-ship speeds are intentionally compressed relative to literal orbital mechanics so continuous real-time travel remains playable. Fighter speed, missile speed, sensor range, and weapon range preserve the intended layered order: detection, missiles, interception, and close combat.

Port is negative carrier-local X; starboard is positive carrier-local X. Each wing must always recover through the bay that launched it.

