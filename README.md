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
| Wild encounters | **scale (departure from CC)** | see below |

CC's gym teams are hand-authored per badge count and it publishes no formula, so
the per-badge coefficients are mod options rather than constants.

Rather than assigning every mon the target level — which would flatten a team
into a mono-level wall — the mod anchors the *strongest* mon to the curve and
shifts the rest by the same delta, preserving the authored spread.

### Wild encounters — a deliberate departure

Crystal Clear freezes wild levels on purpose ("Wild data does not scale. This is
an intentional design choice"). This mod scales them anyway, by request. Set
`scale_wilds` off to get CC's behaviour back.

Default mode is **raise only**: the curve acts as a floor, so each area keeps its
own character — Route 29 stays gentler than Victory Road — and only levels the
curve has outgrown get lifted. `replace` flattens every route to one level.

The Bug Catching Contest is excluded: it is scored on the levels it hands out, so
rescaling would rewrite the minigame rather than the world.

Grass/water/cave and fishing are separate hooks (`encounter.species` and
`encounter.fishing`); both are wrapped.

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
| `scale_wilds` | on | scale wild encounters (off = CC-exact) |
| `wild_mode` | raise_only | `raise_only` floors levels, `replace` flattens |
| `wild_base` | 5 | wild level at 0 badges |
| `wild_per_badge` | 30 | tenths of a level per badge (3.0) |
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

 0 badges  Route 29 SENTRET   L3  -> L5
 8 badges  Route 29 SENTRET   L3  -> L29
16 badges  Route 29 SENTRET   L3  -> L53
 8 badges  Victory Rd GOLBAT  L42 -> L42   (raise-only keeps area character)
16 badges  Victory Rd GOLBAT  L42 -> L53
 any       Bug Contest WEEDLE L9  -> L9    (excluded)
 8 badges  fishing MAGIKARP   L10 -> L29
```

## Known gaps

- **Movesets do not scale.** A Lv75 Pidgey still knows Tackle and Mud-Slap,
  because vanilla rows carry an authored move list. CC gives its leaders custom
  movesets; that is the natural next increment and the single biggest remaining
  difficulty gap.
- **Padding repeats species.** Falkner at 15 badges is three Pidgey and three
  Pidgeotto. Intentional (padding stays on-type) but visibly repetitive.
- **Static legendaries follow the general wild curve**, not CC's own
  `Lv5 + 5 x badges` capped at 50. Close in practice (base 5, 3.0/badge), but not
  CC's exact numbers, and uncapped.
- **Roaming legendaries are unverified.** Raikou/Entei/Suicune may reach battle
  by a path that does not pass through `encounter.species`.
- **Gen 1 is not targeted.** The manifest declares `gen2`, which the engine
  expands to gold/silver/crystal.

## Layout

- `code/level_match/` — the mod (`manifest.json`, `main.lua`)
- `install-levelmatch/` — installs to the local data dir, backing up saves first
- `docs/`, `research/`

## Install

Grab `level_match-vX.Y.Z.zip` from the
[latest release](https://github.com/aaronjenkins/gen1recomp-levelmatch/releases/latest)
and unzip it into your Gen1Recomp `mods/` directory:

| Install | mods/ location |
|---|---|
| macOS | `~/Library/Application Support/pokemon-love2d/mods/` |
| Portable (e.g. Steam Deck SD card) | `<portable folder>/mods/` |
| Linux | `~/.local/share/pokemon-love2d/mods/` |

The zip contains `level_match/` at its root, so it unzips straight in.

Requires engine **0.2.x** (verified on 0.2.26). On 0.1.x the manifest's `gen2`
target expands to Gold only and Crystal is not a known game at all.

### Development install (from a checkout)

```
./install-levelmatch/install-levelmatch.sh
```

Copies the mod into the engine's data directory, snapshotting `saves/` first.
macOS paths; adjust for other platforms.

## Releases

Tagging `vX.Y.Z` builds and publishes a release automatically
(`.github/workflows/release.yml`). The workflow refuses the tag if it disagrees
with the `version` in `manifest.json`, since the mod manager shows the manifest
version rather than the tag.
