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
| Gym trainers | their own curve, between the leader and the routes | CC docs, "Overworld Trainers" |
| Overworld trainers | scale too, "but not as harshly" | CC docs, "Overworld Trainers" |
| Sidequest trainers (`SAGE`, `MYSTICALMAN`) | scale by default; `exempt_sidequest` restores CC's freeze | CC names Sprout Tower, Eusine |
| Wild encounters | scale — **a departure from CC** | below |
| Roaming beasts | scale (`scale_roamers`, writes to the save) | below |
| Scripted statics | **not scaled** — see Known gaps | — |
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

**Gym trainers are their own tier.** CC's line is that trainers *outside* gyms
scale "but not as harshly as Gym trainers do", which makes the staff inside a
gym a tier of their own rather than route fodder. They sit between the leader
(4.5 a badge) and the routes (3.0) at 4.0.

Gym membership is read from the map data, not from class names, because the two
overlap: `LASS` members 1 and 2 stand in Goldenrod Gym, member 9 in Celadon, and
the other fourteen are scattered across the world. A sight trainer is an object
carrying `trainer = { class, member }`; the leader is an object whose script
holds a `loadtrainer` row.

```
at 2 badges   Whitney (leader)          ace L16
              LASS m1, Goldenrod Gym    L15
              LASS m4, not a gym        L13
```

**Levels.** Rather than assigning every mon the target level — which flattens a
team into a mono-level wall — the mod anchors the *strongest* mon to the curve and
shifts the rest by the same delta, preserving the authored spread.

That alone punishes a wide authored ramp: the Goldenrod Beauty's Sentrets are
L9/L13/L17, so anchoring her ace dragged the tail to L5. `spread_cap` puts a
floor under it, six levels below the team's target by default, which turns that
into L9/L11/L15.

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
      -> PIDGEOT  L50 HYPER_BEAM, SWIFT, WING_ATTACK, STEEL_WING
Whitney  CLEFAIRY L18 DOUBLESLAP, MIMIC, ENCORE, METRONOME
      -> CLEFABLE L50 STRENGTH, HEADBUTT, FIRE_BLAST, HYPER_BEAM
```

**Evolution.** A boss dragged to Lv50 was still fielding an unevolved Pidgey,
and the padded clones inherited it. Scaled mons now follow their species'
`EVOLVE_LEVEL` chain as far as the new level allows, so a scaled roster looks
like a team that got there rather than one that was stretched:

```
Falkner  PIDGEY L7 / PIDGEOTTO L9   -> PIDGEOT L73 / PIDGEOT L75
Bugsy    METAPOD / KAKUNA / SCYTHER -> BUTTERFREE / BEEDRILL / SCIZOR
```

`EVOLVE_LEVEL` and `EVOLVE_STAT` carry their own level and apply to everyone.
`EVOLVE_ITEM` and `EVOLVE_TRADE` carry none, so they are a judgement rather than
a rule: **leaders** take them from `stone_evo_level` (30) upward, route trainers
never. A scaled leader has bothered with a Moon Stone; a Lass has not.

```
Whitney  CLEFAIRY -> CLEFABLE     Bugsy  SCYTHER -> SCIZOR
Morty    GASTLY   -> GENGAR       Teacher's CLEFAIRY at Lv52 -> CLEFAIRY
```

Below the threshold nothing happens, so a 0-badge Whitney still fields a Lv5
Clefairy. `EVOLVE_HAPPINESS` is left out entirely — Golbat stays a Golbat.

Several species branch (Gloom to Vileplume or Bellossom, Poliwhirl to Poliwrath
or Politoed, Eevee three ways). The first listed branch wins: arbitrary, but
deterministic, so a given leader always fields the same team.

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

## Rewards, and why they need a cap

Scaling the enemy also scales what beating it pays, and the engine's own
formulas are the reason:

- experience is `baseExp × the defeated level ÷ 7`
- prize money is `baseMoney × the level of the LAST mon on the roster`
  (`Prize.reward`, `Prize.rewardLevel`) — the roster's *size* is not in it, so
  a six-mon trainer pays exactly what a two-mon one pays

Both terms are the level this mod just raised. Measured against the real Crystal
dataset:

```
                             vanilla        with scaling      money   exp
BUG_CATCHER   8 badges   2 mons L3  ¥12    2 mons L31 ¥124    x10.3   x32.2
FISHER        6 badges   4 mons L5  ¥50    4 mons L19 ¥190    x3.8    x11.0
COOLTRAINERM 12 badges   3 mons L26 ¥312   3 mons L43 ¥516    x1.7    x5.3
WHITNEY (gym) 3 badges   2 mons L20 ¥500   6 mons L21 ¥525    x1.1    x2.6
```

**That inflation makes the game easier, not harder.** Enemies follow the badge
count and nothing follows the player, so experience that outruns the curve buys
a party the curve can no longer threaten — and a Lv31 Bug Catcher paying 32× is
a very fast way to outrun it.

`lean_rewards` puts the player on a curve too. It is **off by default**: it
changes how a whole run paces, and it is not what earlier versions did.

**A soft level cap, not a flat tax.** Below the cap a mon earns at the full
(inflated) rate, so climbing back up after a badge is quick. At or above it the
mon keeps only `exp_over_cap` — 10% by default, so a capped party creeps rather
than freezing. The cap is one of the mod's own curves, read live from the badge
count: `boss` by default, which is the level of the gym leader your badge count
says you can face, so a capped party meets a leader level for level.

The cap is per **mon**, because `exp.gain` fires once per recipient per KO. A
fresh Lv5 catch still earns at full rate while the rest of a capped team creeps.

**Prize money has no hook.** `Prize.award` reads its reward through the module
table — `local quarter = Prize.reward(opts.baseMoney, opts.level)` — and
`Prize.reward` is a pure function with exactly that one caller, so the mod wraps
it behind `engine_internals`. That scales the payout and the "got ¥1234 for
winning" line that quotes it, and nothing else. The vanilla function is parked on
the table, so reloading the mod wraps the original rather than stacking a second
multiplier; the wrapper reads the options on every call, so switching the mod off
restores vanilla payouts without unwrapping anything.

**The Battle Tower is exempt here too**, for the reason it is exempt from
scaling: it is a level-normalised format the curve never touched, so starving its
experience would tax a mode this mod does not otherwise affect.

## Options

| Key | Default | Meaning |
|---|---|---|
| `enabled` | on | master switch |
| `boss_base` | 7 | gym level at 0 badges |
| `boss_per_badge` | 45 | tenths of a level per badge (4.5) |
| `postgame_base` | 21 | Red's level at 0 badges |
| `postgame_per_badge` | 40 | tenths of a level per badge (4.0) |
| `gym_base` | 7 | gym trainer level at 0 badges |
| `gym_per_badge` | 40 | tenths of a level per badge (4.0) |
| `overworld_base` | 7 | overworld level at 0 badges |
| `overworld_per_badge` | 30 | tenths of a level per badge (3.0) |
| `scale_overworld` | on | scale route trainers (off = bosses only) |
| `exempt_sidequest` | **off** | freeze the sidequest classes, as CC does |
| `scale_movesets` | on | rebuild movesets for the new level |
| `boss_best_moves` | on | bosses also draw from their TM pool |
| `spread_cap` | 6 | no mon lands more than this far below its team's ace |
| `evolve_scaled` | on | evolve scaled mons to the form their level allows |
| `boss_stone_evos` | on | leaders also take stone and trade evolutions |
| `stone_evo_level` | 30 | the level from which a stone or trade is assumed |
| `pad_boss_teams` | on | grow thin boss teams |
| `boss_full_team` | 6 | boss team size at 16 badges |
| `scale_wilds` | on | scale wild encounters (off = CC-exact) |
| `wild_mode` | raise_only | `raise_only` floors levels, `replace` flattens |
| `wild_base` | 5 | wild level at 0 badges |
| `wild_per_badge` | 30 | tenths of a level per badge (3.0) |
| `scale_roamers` | on | scale Raikou/Entei/Suicune (writes to the save) |
| `lean_rewards` | **off** | master switch for the experience cap and money cut |
| `exp_cap_tier` | boss | which curve caps the player: `boss`, `gym`, `overworld`, `off` |
| `exp_over_cap` | 10 | % of experience a mon at or above the cap still earns |
| `exp_rate` | 100 | % of experience below the cap |
| `money_rate` | 50 | % of prize money |
| `debug_badges` | -1 | pretend this many badges; -1 reads the save |

`debug_badges` exists because a fresh file has zero badges, where the curve is
unobservable.

## Verified behaviour

Driven through the engine's own `POKEPORT_DRIVER` seam against the real Crystal
dataset:

```
 0 badges  FALKNER            L7/L9   -> L5/L7      (2 mons)
15 badges  FALKNER            L7/L9   -> L73/L75    (6 PIDGEOT, hp 215 and 221)
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

With `lean_rewards` on at its defaults, and a party sitting exactly at the cap:

```
                              vanilla        scaled          lean
BUG_CATCHER    8 badges  cap L43   ¥12  66     ¥124  2124    ¥62   212
FISHER         6 badges  cap L34   ¥50  126    ¥190  1389    ¥95   138
COOLTRAINERM  12 badges  cap L61   ¥312 1083   ¥516  5774    ¥258  576
WHITNEY (gym)  3 badges  cap L21   ¥500 1117   ¥525  2910    ¥262  289
CLAIR (gym)    8 badges  cap L43   ¥1000 5196  ¥1000 8705    ¥500  868
BLUE (gym)    15 badges  cap L75   ¥1450 14602 ¥1875 18975   ¥937  1894
```

and the cap itself, driven one award at a time at 8 badges (boss cap L43):

```
lean off              mon L40 vs a L31 BUTTERFREE  -> 1062
lean on   cap L43     mon L20 -> 1062   mon L42 -> 1062   (under the cap, full rate)
lean on   cap L43     mon L43 -> 106    mon L60 -> 106    (at or over it, 10%)
exp_rate 50           mon L20 -> 531
exp_over_cap 0        mon L60 -> 0
exp_cap_tier off      mon L60 -> 1062                     (uncapped again)
wild battles          mon L60 -> 70     mon L20 -> 708    (the cap covers wilds)
Prize.reward(25, 40)  1000 vanilla -> 500 at 50% -> 250 at 25% -> 1000 with the mod off
Battle Tower          mon L60 -> 1062                     (uncut mid-challenge)
```

The mod declares the `engine_internals` permission for two engine modules, not
other mods: since 0.3.3 it reads `src.battle.gen2.Mon` to keep a scaled mon's
`experience` consistent with its new level, and since 0.9.0 it wraps
`src.battle.gen2.Prize`'s `reward` to cut prize money, which has no hook.

## Known gaps

- **Padding repeats species, and evolution makes that worse on some teams.**
  Evolving collapses an evolutionary line into a single species, so a leader
  whose roster varied only by *stage* ends up entirely uniform:

  ```
  Morty    GASTLY / HAUNTER / GENGAR / HAUNTER  ->  6x GENGAR
  Falkner  PIDGEY / PIDGEOTTO                   ->  6x PIDGEOT
  Clair    DRAGONAIR x3 / KINGDRA               ->  5x DRAGONITE + KINGDRA
  Bugsy    METAPOD / KAKUNA / SCYTHER           ->  BUTTERFREE / BEEDRILL / SCIZOR
  ```

  Bugsy stays varied because his three mons are three separate lines. Falkner
  was three Pidgey and three Pidgeotto before evolution, which at least read as
  two Pokemon; now it is six of one. So evolution traded "unevolved and wrong"
  for "evolved and monotonous" on single-line teams, and every clone shares one
  moveset besides.

  Drawing padding from a type-matched pool of trainer-used species is the fix.
  The pools are uneven, though, and Morty is the worst case for it as well as
  for the current behaviour: Ghost has only four species across every trainer in
  the game (Gastly, Haunter, Gengar, Misdreavus).
- **Scripted static encounters are not scaled at all.** Sudowoodo, Snorlax, the
  legendary birds, Ho-Oh/Lugia and the Red Gyarados are placed by the
  `loadwildmon` script opcode, which sets the species and level straight from
  the script row and hands them to `startbattle` — so, like the roaming beasts,
  they never reach `rollEncounter` and never see `encounter.species`. Unlike the
  roamers there is no dedicated event for them, but `script.command` sees every
  `loadwildmon` row and is the obvious seam. CC scales these as
  `Lv5 + 5 × badges` capped at 50.
- **Pay Day is untouched.** It pays `2 × the user's level` on a separate path
  (`Prize.payDay`), and its level is the player's, which the cap already holds
  down.
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
on, and grass, cave and fishing rolls all scale. The reward cap was driven the
same way, one award at a time: the boundary lands where the curve says it does
(full rate at Lv42, cut at Lv43 on a Lv43 cap), the money wrapper scales the
payout and restores vanilla when the mod is switched off, and neither touches a
Battle Tower challenge. Each published zip is checked against the importer's
archive rules.

**Played once, not played through.** A scaled gym battle has been fought in the
real game and ran correctly — the padded team, the rebuilt movesets and the
levels all behaved, and it was genuinely harder. That is one battle, not a run:
there is still no full playthrough and no balance testing across one, so the
curve past the mid-game is still a projection. `lean_rewards` in particular has
been measured but never played: the numbers above say what it pays, not whether
a run under it is paced well. Treat the defaults as a starting point, and back
up your saves before installing.

## License

[MIT](LICENSE). The license ships inside the release zip, so an installed copy
carries its own terms.
