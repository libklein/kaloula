# Frog rig

`FrogRig` (`frog_rig.gd`) draws the frog in code (no textures) and animates it procedurally.
The frog faces up (−Y); rotate the node to aim it. One hop moves `FrogRig.HOP_STRIDE` (150) rig units,
so `scenes/frog/frog.gd` scales the rig to make one hop = one tile.

## Animations (`rig.animation`)
| Anim | Loop | Notes |
|---|---|---|
| `IDLE` | 4.0 s | breathe & blink (sitting pose) |
| `STRETCH` | 4.2 s | toe stretch, starts/ends sitting |
| `CATCH` | 4.8 s | catches a mosquito with its tongue, starts/ends sitting |
| `HOP` | 1.12 s | one hop forward, starts/ends sitting |
| `CRAWL` | 1.6 s | slow four-beat crawl, 36 units per loop |
| `BELLY_UP` | 3.2 s | on its back, struggling |
| `TURN` | 0.92 s per 90° | turn in place; use `rig.turn(degrees, then)` in game code |

- `rig.turn(90)` / `turn(-90)` / `turn(180)`: steps around on the spot, then updates the node's
  `rotation`, switches to `then` (default `IDLE`) and emits `turn_finished`.
- `cycle_finished(anim)` fires at the end of every loop (used to chain hops and to end fidgets).
- `get_travel()` / `travel_delta`: forward distance for root motion (feet stay planted).
- Switching between the standing animations blends the legs for `blend_time` (0.15 s).
  Belly up switches instantly.
- Set **Animation** in the Inspector to preview any loop in the editor.

## Colours
Expand **Palette** in the Inspector. `frog.tscn` uses the shared `palettes/mint.tres`;
right-click **Palette → Make Unique** to recolour one frog only. The button at the bottom of the
palette matches the eyelid, throat and belly-up colours to a new skin colour.
`tomato.tres` and `poison_dart.tres` are examples; save your own with **Save As…**.
