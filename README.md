# Double Click — Beta 0.1

A 3D team arena fighter for Roblox. This first beta build contains:

- **Movement**: weighty acceleration, turning and stopping, unlimited sprint, dodge (Shift tap) that flows into a sprint (Shift hold), jumps, and wall slides and wall jumps off walls and trees
- **M1s**: standing string, forward M1 and air M1. The last hit of the string knocks back, and getting knocked into a wall causes a wall stun
- **Blocking with close blocks**: F to block, a hidden block meter, block breaks, and close blocks (Perfect / Great / Good) with a colored flash on both screens and a punish window
- **Speerrow**: Stacks, Uncapped Speed, Parry (E), Zap (R), Rush (Q) and Full Counter (G)
- **Debug mode**: placeholder animations, hitbox view, timing feedback, live overlay, slow motion and frame step, and a configurable training dummy

Every number is a placeholder for playtesting, just like the design doc.

## Play it

**Easiest:** open the latest run on the repo's **Actions** tab, download the `DoubleClick-beta-place` artifact, open `DoubleClick.rbxl` in Roblox Studio and press **Play**.

**From source (Rojo):**

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in this folder. It installs the pinned tools from `rokit.toml`.
2. Either build a place file and open it in Studio:
   ```
   rojo build default.project.json -o DoubleClick.rbxl
   ```
   or live-sync into Studio with `rojo serve` and the Rojo Studio plugin.

The test arena is built by script when the server starts. To use your own map instead, put a `Folder` named `Arena` in Workspace, with the solid parts inside `Arena/Solid`.

## Controls

| Key | Action |
|---|---|
| WASD | Move |
| Space | Jump / wall jump |
| M1 | Basic attack (standing, forward while running forward, air while airborne) |
| F | Block (hold) |
| Shift (tap) | Dodge (no invincibility) |
| Shift (hold) | Sprint (flows out of the dodge) |
| E | Parry |
| R | Zap |
| Q | Rush (tap again mid-flight to pull back) |
| G | Full Counter (needs full ult) |
| Middle mouse | Lock-on |

All bindings live in `src/shared/Config/Keybinds.luau`, so they can be remapped later.

## Debug mode

Debug mode is available only in **Studio, private servers and test places** (listed in `GameConfig.Debug.TestPlaceIds`), never in ranked.

| Key | Debug action |
|---|---|
| `` ` `` | Cycle: panel + overlay (mouse free) → overlay only → off |
| H | Hitbox view: hurtboxes in green; attack hitboxes in yellow (wind-up), red (active) and blue (recovery) |
| `[` / `]` | Slower / faster (1x, 0.5x, 0.25x, 0.1x) |
| P | Pause / resume |
| . | Step one frame (1/60s) while paused |

- **Timing feedback**: every block, close block, parry and Full Counter prints its exact timing to the log box and the Output window. For example: `Close block: Great, 0.17s (10 frames) before impact.`
- **Live overlay**: shows your state and phase, speed, HP, block meter, stacks and when they drop, ult, stun chain and immunity, and cooldowns. The same readout is shown for your target (lock-on target or nearest enemy).
- **Training dummy**: pick its behavior (Idle / Attack / Block / Block + Attack), attack (Jab, 3-hit String, Heavy, Arrow, Explosion, Grab, and the ult versions Strike, Blast and Grab), attack interval and wind-up. You can also toggle infinite HP, spawn more dummies, reset them or clear them.
- **Quick cheats**: fill ult, reset cooldowns, max stacks, reset HP and state.

Frame step advances the game clock (move timelines, hitboxes, cooldowns, animations) by exactly one frame. Character physics stay frozen while paused.

## Where the numbers live

| File | What |
|---|---|
| `src/shared/Config/GameConfig.luau` | Health table, stat formulas, movement, close-block windows, stun rule, block meter, camera, debug |
| `src/shared/Characters/Speerrow.luau` | Speerrow's stats, M1 frame data, dodge, cooldowns |
| `src/shared/Characters/SpeerrowKit.luau` | Stacks, Uncapped Speed, parry tiers, Zap, Rush, Full Counter |
| `src/shared/Config/DummyAttacks.luau` | The training dummy's practice attacks |

Combos aren't scripted. A follow-up connects only if it comes out faster than the enemy's hitstun, so the frame data decides what combos. The unit tests check that Speerrow's string combos and that every close-block level leaves room for an M1 punish.

## Rulings made while building (to confirm)

The doc didn't pin these down, so I picked something reasonable. Each is a single value or rule in the code and easy to change:

1. **Block direction**: a block covers the front 180° (`BlockArcDegrees`). Blocking faces where you aim.
2. **Close-block timer**: it starts from a fresh F press. A block that comes back on by itself (F held through blockstun, hitstun or an attack) is a normal block. So is a re-press within 0.15s of letting go, which stops mashing.
3. **Punish window**: on a close block the attacker's string breaks and their recovery is extended by +0.28s / +0.22s / +0.12s (Perfect / Great / Good). The defender's blockstun is scaled ×0 / ×0.35 / ×0.65. An M1 always fits, and so does Zap (almost no wind-up); slower abilities don't.
4. **M1 hitstun isn't a "stun"**, so it doesn't follow the repeated-stun rule. Stuns are: Zap, parry stun, wall stun, block break, Rush blocked and Full Counter.
5. **Stun chain**: the 4th stun still lands at 25%; the 2s immunity starts when it ends.
6. **Parry tier gaps**: the doc's small gaps (0.25–0.27s, 0.42–0.43s, 0.58–0.6s) fall into the next slower tier.
7. **Bonuses add**: stacks and Uncapped Speed add together (5 stacks + full sprint = ×2.5), not ×3.
8. **Parry reflect** uses Speerrow's stacks *after* the parry's stacks are added.
9. **Full Counter**: reflects 5× the attacker's damage (no stack bonus) and cancels their attack. The ult is spent on press. The map-wide 3s stun after countering an ult goes through the repeated-stun rule.
10. **Rush limits**: at most 12 bounces or 4s per Rush. He never relaunches back into the surface he just landed on, so he can't hit the same enemy twice in a row without bouncing off something else.
11. **Block break**: 1.0s stun (follows the stun rule), then the meter refills.
12. **Ult charge**: 1 per damage dealt plus 4 per landed ability, times the character's rate (Speerrow ×0.35). A Perfect parry within 0.08s adds a flat +50%.
13. **Damage / Defense stats** are multipliers: ±10% damage dealt and ∓5% damage taken per point away from 3.
14. **Forward M1** means moving toward where you aim at 40%+ of walk speed. A dodge with no movement input goes where you face. You get one air dodge per jump.
15. **Downed (beta only)**: rounds aren't in yet, so a fighter at 0 HP is down for 3s and then fully resets. Dummies have infinite HP by default.
16. **Debug time controls** are server-wide, and anyone in a private or test server can use them.
17. **Lag compensation**: block, parry and Full Counter presses are credited up to 0.2s back from when the server receives them.

## Not in this beta yet

Rounds, bans and picks, teams UI, the other 19 characters, the minimap (M), controller layout and aim assist, the keybind remapping UI, and real animations. Movement is client-owned (standard for Roblox), and combat is server-authoritative with only basic validation.

## Status

This build passes static type checking against the Roblox API (both Luau solvers), linting, formatting and 53 unit tests, and it builds to a place file. It hasn't been playtested inside Roblox Studio yet, so expect tuning work and possibly a few small bugs on the first run. Please send tester notes.

## Project layout

```
src/shared/     config, character data, pure combat rules (timing, stuns, stacks, block meter,
                hit resolution, damage), movement math, game clock
src/server/     fighters, move timelines and hitboxes, hit resolution, Speerrow's kit,
                training dummy, debug commands, test arena
src/client/     input, camera, movement, combat input, Rush flight, placeholder animations,
                HUD, overhead bars, effects, debug panel/overlay/hitbox view
tests/          Lune unit tests for the pure rules and frame data
```

## Development

```
stylua --check src tests                      # format
selene src                                    # lint
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json src/   # types
lune run tests/run.luau                       # unit tests
```

CI runs all of these on every push and uploads the built place.

## Before any public release

Speerrow and the name "Double Click" come from the webtoon. Their names, look and branding need original replacements before the game is released publicly.
