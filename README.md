# gen1recomp-levelmatch

Crystal Clear style badge-count enemy scaling for [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp), as a Gen 2 mod.

Crystal Clear's open world works because of one rule: every trainer scales to your
badge count, so all 16 gyms can be faced in any order. This mod brings that rule
to vanilla Gold/Silver/Crystal.

Requires engine **0.2.x** (developed against 0.2.26). On 0.1.x the `gen2` target
expands to Gold only and Crystal is not a known game at all.

## Install

Download `level_match-vX.Y.Z.zip` from the
[latest release](https://github.com/aaronjenkins/gen1recomp-levelmatch/releases/latest),
then import it as Gen1Recomp imports any mod: **drag the `.zip` onto the game
window**, or import it from the launcher's mod manager. The engine validates the
archive and installs it to `mods/level_match/`, taking the folder name from the
manifest id.

The manifest declares its `github` repository, so the mod manager's update check
finds new releases here. Only published release assets count — a GitHub source
archive has the wrong layout and is never used.

To install by hand instead, unzip it into your `mods/` directory (the archive has
`level_match/` at its root): `~/Library/Application Support/pokemon-love2d/mods/`
on macOS, `~/.local/share/pokemon-love2d/mods/` on Linux, `<portable folder>/mods/`
for a portable install.

Options live in-game under **START → MODS → Level Match → OPTIONS..**, and apply
to the next battle without a restart.

## What it does

The engine's `trainer.party` hook (`src/battle/gen2/Battle.lua`) hands a mod the
composed enemy roster and keeps whatever it hands back. The mod wraps that, reads
badge count off the save, and rewrites the team. It is engine-native, so the mod
depends on no other mod.

| Tier | Behaviour | Source |
|---|---|---|
| Gyms, E4, champion, rivals | ~Lv7 at 0 badges to ~Lv75 at 15 | CC docs, "Scaling Gyms" |
| Red | his own curve, ~Lv85 at 16 badges | see below |
| Overworld trainers | scale too, "but not as harshly" | CC docs, "Overworld Trainers" |
| Sidequest trainers (`SAGE`, `MYSTICALMAN`) | scale by default; `exempt_sidequest` restores CC's freeze | CC names Sprout Tower, Eusine |
| Wild encounters | scale — **a departure from CC** | below |
| Battle Tower | never scales | below |

CC hand-authors its gym teams per badge count and publishes no formula, so the
per-badge coefficients are options rather than constants.

**Sidequest trainers scale, unlike in CC.** CC exempts "certain sidequest
trainers (Eusine, Sprout Tower, etc.)", but that maps badly onto vanilla classes:
`SAGE` alone spans the Lv3–10 Sprout Tower sages CC names, a Lv16–22
Gastly/Haunter pair, and the **Lv32 Tin Tower sages** — so freezing the class left
a late-game encounter at Lv32 while gyms ran to Lv79. They all scale by default;
`exempt_sidequest` restores CC's behaviour.

**Red gets his own tier.** He is the one trainer vanilla authors above anything
the boss curve can reach: his ace is Lv81 against a boss ceiling of Lv79 at 16
badges, so putting him on the boss curve could only ever make the hardest fight
in the game *easier*. On his own curve he reaches ~Lv85 at 16 badges — above
vanilla, as he should be once every other tier has scaled up too — while still
scaling down if you somehow reach Mt. Silver early. Nothing else comes close to
the ceiling: the next highest boss tops out at Lv58, and the Elite Four have no
rematch rosters in vanilla, so this tier is Red alone.

**Levels.** Rather than assigning every mon the target level — which flattens a
team into a mono-level wall — the mod anchors the *strongest* mon to the curve and
shifts the rest by the same delta, preserving the authored spread.

**Movesets.** A mon dragged to Lv75 still knowing its Lv7 moves is the biggest
reason scaled bosses stay easy. Every scaled mon is rebuilt to what its species
knows at its new level; route trainers keep authored moves the species cannot
learn by level, since those are deliberate TM coverage. Bosses draw from their
**TM pool** too and keep the four best attacks they could learn, ranked by power ×
accuracy with ×1.5 STAB — discounting moves whose raw power lies about their
output: charging or recharging (Solarbeam, Hyper Beam, Fly), fainting the user
(Selfdestruct), and moves needing a condition the AI cannot arrange (Dream Eater
wants a sleeping target, Counter an incoming hit).

```
Falkner  PIDGEY   L7  TACKLE, MUD_SLAP
      -> PIDGEY   L50 SWIFT, WING_ATTACK, STEEL_WING, GUST
Whitney  CLEFAIRY L18 DOUBLESLAP, MIMIC, ENCORE, METRONOME
      -> CLEFAIRY L50 STRENGTH, HEADBUTT, FIRE_BLAST, PSYCHIC
```

**Evolution.** A boss dragged to Lv50 was still fielding an unevolved Pidgey,
and the padded clones inherited it. Scaled mons now follow their species'
`EVOLVE_LEVEL` chain as far as the new level allows, so a scaled roster looks
like a team that got there rather than one that was stretched:

```
Falkner  PIDGEY L7 / PIDGEOTTO L9   -> PIDGEOT L73 / PIDGEOT L75
Bugsy    METAPOD / KAKUNA / SCYTHER -> BUTTERFREE / BEEDRILL / SCYTHER
```

Only level evolutions. Stone and trade methods carry no level, so there is no
honest way to say whether this trainer would have used one — Whitney's Clefairy
stays a Clefairy rather than being handed a Moon Stone, Bugsy keeps his Scyther
rather than a traded Scizor, and Morty fields Haunters because Gengar is a trade
too.

**Team padding.** Vanilla bosses carry teams as small as two (Falkner), which stay
a pushover at Lv75, so boss teams grow linearly from their authored size at 0
badges to six at 16, cloning from the authored roster to stay on-type.

**Wild encounters — a deliberate departure.** CC freezes wild levels on purpose
("Wild data does not scale. This is an intentional design choice"); this mod
scales them anyway, by request. `scale_wilds` off restores CC's behaviour. Default
mode is **raise only**, so the curve acts as a floor and each area keeps its own
character — Route 29 stays gentler than Victory Road — while `replace` flattens
every route to one level. Grass/water/cave and fishing are separate hooks
(`encounter.species`, `encounter.fishing`); both are wrapped. The Bug Catching
Contest is excluded, being scored on the levels it hands out.

**The roaming beasts take a different route.** Raikou, Entei and Suicune never
reach `encounter.species`: the roamer check runs before `ChooseWildEncounter`,
builds the mon straight from its save slot and calls `startBattle` itself,
returning before `rollEncounter`. (The engine's own comment in
`src/core/gen2/Roamers.lua` says `encounter.species` "still runs downstream" for
them — it does not; that branch returns first.)

The seam is the `roamer.encountered` event, which fires from inside the roll that
picked the beast and whose payload carries the **live** save slot —
`Roamers.slot` returns `save.roamers[index]` itself, not a copy — so setting
`slot.level` there is what `Roamers.beginBattle` reads a moment later.

Because that level lives in the save, **scaling a roamer writes to the save and
persists**, even if this mod is later removed. `scale_roamers` exists so that is
a choice. Banked HP is left alone: it represents the beast's wound between
encounters, so a raised level simply makes the same banked value a smaller share
of a bigger bar.

**The Battle Tower is left alone.** The Tower is level-normalised: three mons, a
room whose cap is a flat multiple of ten, entry refused if any mon exceeds it, and
opponents authored down to their stats, PP and held items. The cart switches badge
stat and type boosts **off** inside it — it is the one mode designed so badge count
cannot matter. Scaling it would make a lottery of a tuned gauntlet: a 10-badge
player would meet Lv37 opponents in the Lv50 room, and the same Lv37 opponents in
the Lv10 room while capped at Lv10. Tower battles do reach `trainer.party` and the
hook cannot see the `battleTower` flag, so the mod reads
`save.battleTower.challenge` (`sBattleTowerChallengeState`, `2` while a challenge
runs) and skips scaling for its duration.

## Options

| Key | Default | Meaning |
|---|---|---|
| `enabled` | on | master switch |
| `boss_base` | 7 | gym level at 0 badges |
| `boss_per_badge` | 45 | tenths of a level per badge (4.5) |
| `postgame_base` | 21 | Red's level at 0 badges |
| `postgame_per_badge` | 40 | tenths of a level per badge (4.0) |
| `overworld_base` | 7 | overworld level at 0 badges |
| `overworld_per_badge` | 30 | tenths of a level per badge (3.0) |
| `scale_overworld` | on | scale route trainers (off = bosses only) |
| `exempt_sidequest` | **off** | freeze the sidequest classes, as CC does |
| `scale_movesets` | on | rebuild movesets for the new level |
| `boss_best_moves` | on | bosses also draw from their TM pool |
| `evolve_scaled` | on | evolve scaled mons to the form their level allows |
| `pad_boss_teams` | on | grow thin boss teams |
| `boss_full_team` | 6 | boss team size at 16 badges |
| `scale_wilds` | on | scale wild encounters (off = CC-exact) |
| `wild_mode` | raise_only | `raise_only` floors levels, `replace` flattens |
| `wild_base` | 5 | wild level at 0 badges |
| `wild_per_badge` | 30 | tenths of a level per badge (3.0) |
| `scale_roamers` | on | scale Raikou/Entei/Suicune (writes to the save) |
| `debug_badges` | -1 | pretend this many badges; -1 reads the save |

`debug_badges` exists because a fresh file has zero badges, where the curve is
unobservable.

## Verified behaviour

Driven through the engine's own `POKEPORT_DRIVER` seam against the real Crystal
dataset:

```
 0 badges  FALKNER            L7/L9   -> L5/L7      (2 mons)
15 badges  FALKNER            L7/L9   -> L73/L75    (6 mons, hp 153 and 191)
16 badges  RED                L81 ace -> L85 ace    (postgame tier; was L79 on the boss curve)
 8 badges  RED                L81 ace -> L53 ace    (scales down if reached early)
 0 badges  WHITNEY            L18/L20 -> L5/L7      (scaled DOWN — fight her first)
15 badges  YOUNGSTER          L4      -> L52        (softer overworld curve)
10 badges  SAGE CHOW          L3 x3   -> L37 x3     (Sprout Tower)
10 badges  SAGE KOJI          L32/L32 -> L37/L37    (Tin Tower)
 any       SAGE, exempt on    L3 x3   -> unchanged
 any       Battle Tower       L9/13/17-> unchanged  (challenge in progress)
 8 badges  Route 29 SENTRET   L3      -> L29
16 badges  Victory Rd GOLBAT  L42     -> L53        (raise-only keeps character)
 any       Bug Contest WEEDLE L9      -> L9         (excluded)
 8 badges  fishing MAGIKARP   L10     -> L29
16 badges  roaming RAIKOU     L40     -> L53        (hp 161/161, from the save slot)
 8 badges  roaming RAIKOU     L40     -> L40        (raise-only floor is below it)
```

The mod declares the `engine_internals` permission: since 0.3.3 it reads
`src.battle.gen2.Mon` to keep a scaled mon's `experience` consistent with its
new level. That is an engine module, not another mod.

## Known gaps

- **Padding still repeats species**, and every clone shares one moveset —
  Falkner at 15 badges is six Pidgeot. Evolution improves what gets repeated,
  not the repetition itself. Drawing padding from a type-matched pool of
  trainer-used species is the obvious next step; note the pools are uneven
  (Ghost has only four species across every trainer in the game).
- **Static legendaries follow the general wild curve**, not CC's own
  `Lv5 + 5 × badges` capped at 50. Close in practice, but uncapped.
- **Gen 1 is not targeted.** The manifest declares `gen2`, which the engine
  expands to gold/silver/crystal.

## Development

- `code/level_match/` — the mod (`manifest.json`, `main.lua`)
- `install-levelmatch/` — installs into the local data dir, snapshotting `saves/`
  first (macOS paths; adjust for other platforms)
- `.github/workflows/release.yml` — tagging `vX.Y.Z` builds and publishes a
  release. It refuses a tag disagreeing with `manifest.json`, since the mod
  manager shows the manifest version rather than the tag.

## How this was built

Written with [Claude](https://claude.ai) (Claude Code), directed by the repository
owner: the priorities, design decisions and scope calls are the owner's; the Lua,
the release workflow and this README were drafted by the model.

**The numbers are sourced, not invented** — tiers and levels come from Crystal
Clear's official documentation (`ShockSlayer/ccdocs`). Where CC publishes no
formula, the coefficients are exposed as options rather than silently guessed.

**What was verified.** The mod was exercised against the real Crystal dataset
inside the running engine through `POKEPORT_DRIVER`: the hook fires with real
trainer class ids, levels land on the documented endpoints, HP refills to the new
maximum instead of keeping the pre-scaling value, Battle Tower opponents stay
untouched mid-challenge, sidequest classes freeze only when `exempt_sidequest` is
on, and grass, cave and fishing rolls all scale. Each
published zip is checked against the importer's archive rules.

**Played once, not played through.** A scaled gym battle has been fought in the
real game and ran correctly — the padded team, the rebuilt movesets and the
levels all behaved, and it was genuinely harder. That is one battle, not a run:
there is still no full playthrough and no balance testing across one, so the
curve past the mid-game is still a projection. Treat the defaults as a starting
point, and back up your saves before installing.

## License

[MIT](LICENSE). The license ships inside the release zip, so an installed copy
carries its own terms.
