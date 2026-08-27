# gen1recomp-levelmatch

Crystal Clear style badge-count enemy scaling for [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp), as a Gen 2 mod.

Crystal Clear's open world works because of one rule: every trainer scales to
your badge count, so all 16 gyms can be faced in any order. This mod brings that
rule to vanilla Gold/Silver/Crystal.

## Status

Working. Requires engine **0.2.x**; developed and verified against 0.2.26,
exercised against the real Crystal dataset through the engine's own
`POKEPORT_DRIVER` seam.

## How it works

The engine exposes a `trainer.party` hook (`src/battle/gen2/Battle.lua`) that
hands a mod the composed enemy roster and keeps whatever it hands back. The mod
wraps it, reads the badge count off the save, and rewrites levels.

`trainer.party` is engine-native, so this mod has no dependency on any other
mod.

### The curve

Numbers come from the official Crystal Clear docs (`ShockSlayer/ccdocs`):

| Tier | Behaviour | Source |
|---|---|---|
| Gyms, E4, champion, rivals, Red | ~Lv7 at 0 badges to ~Lv75 at 15 | CC docs, "Scaling Gyms" |
| Overworld trainers | scale too, "but not as harshly" | CC docs, "Overworld Trainers" |
| Sidequest trainers (`SAGE`, `MYSTICALMAN`) | never scale | CC docs names Sprout Tower, Eusine |
| Wild encounters | never scale | CC FAQ: "an intentional design choice" |

CC's gym teams are hand-authored per badge count and it publishes no formula, so
the per-badge coefficients are mod options rather than constants.

Rather than assigning every mon the target level — which would flatten a team
into a mono-level wall — the mod anchors the *strongest* mon to the curve and
shifts the rest by the same delta, preserving the authored spread.

### Team padding

Vanilla bosses carry teams as small as two (Falkner), which stay a pushover at
Lv75. Boss teams grow linearly from their authored size at 0 badges to a full
six at 16, cloning entries from the authored roster so padding stays on-type.

## Options

| Key | Default | Meaning |
|---|---|---|
| `enabled` | on | master switch |
| `boss_base` | 7 | gym level at 0 badges |
| `boss_per_badge` | 45 | tenths of a level per badge (4.5) |
| `overworld_base` | 7 | overworld level at 0 badges |
| `overworld_per_badge` | 30 | tenths of a level per badge (3.0) |
| `pad_boss_teams` | on | grow thin boss teams |
| `boss_full_team` | 6 | boss team size at 16 badges |
| `debug_badges` | -1 | pretend this many badges; -1 reads the save |

`debug_badges` exists because a fresh file has zero badges, where the curve is
unobservable.

## Verified behaviour

Driven through the engine's own `POKEPORT_DRIVER` seam against the real dataset:

```
 0 badges  FALKNER    L7/L9    -> L5/L7        (2 mons)
 8 badges  FALKNER    L7/L9    -> L41/L43      (4 mons)
15 badges  FALKNER    L7/L9    -> L73/L75      (6 mons, hp 153/153 and 191/191)
 0 badges  WHITNEY    L18/L20  -> L5/L7        (scaled DOWN -- fight her first)
15 badges  YOUNGSTER  L4       -> L52          (softer overworld curve)
 any       SAGE       L3 x3    -> unchanged    (exempt)
```

## Known gaps

- **Movesets do not scale.** A Lv75 Pidgey still knows Tackle and Mud-Slap,
  because vanilla rows carry an authored move list. CC gives its leaders custom
  movesets; that is the natural next increment and the single biggest remaining
  difficulty gap.
- **Padding repeats species.** Falkner at 15 badges is three Pidgey and three
  Pidgeotto. Intentional (padding stays on-type) but visibly repetitive.
- **Static legendaries are not scaled.** CC scales the birds, Snorlax, Lapras,
  Sudowoodo, Celebi and Red Gyarados as `Lv5 + 5 x badges` capped at 50. Those
  are wild-path encounters, not `trainer.party`, so they need a different seam.
- **Gen 1 is not targeted.** The manifest declares `gen2`, which the engine
  expands to gold/silver/crystal.

## Layout

- `code/level_match/` — the mod (`manifest.json`, `main.lua`)
- `install-levelmatch/` — installs to the local data dir, backing up saves first
- `docs/`, `research/`

## Install

```
./install-levelmatch/install-levelmatch.sh
```

Copies the mod into the engine's data directory, snapshotting `saves/` first.
macOS paths; adjust for other platforms.
