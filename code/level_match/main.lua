-- Level Match -- Crystal Clear style badge-count enemy scaling for Gen 2.
--
-- Crystal Clear's whole design rests on one rule: every trainer scales to the
-- player's badge count, so all 16 gyms can be faced in any order.  This mod
-- reproduces that rule on vanilla Gold/Silver/Crystal through the engine's
-- `trainer.party` hook, which hands a mod the composed enemy roster and keeps
-- whatever it hands back (src/battle/gen2/Battle.lua).
--
-- The numbers come from the official Crystal Clear docs (ShockSlayer/ccdocs):
--   * gym teams run ~Lv7 at 0 badges to ~Lv75 at 15
--   * overworld trainers scale as well, "but not as harshly as Gym trainers"
--   * certain sidequest trainers (Eusine, Sprout Tower) never scale
--   * wild encounters never scale -- an intentional design choice
--
-- Wild scaling is the one place this mod deliberately DEPARTS from Crystal
-- Clear: CC freezes wild levels on purpose and we scale them anyway, on
-- request.  It is opt-out via the `scale_wilds` option.
--
-- CC's gym teams are hand-authored per badge count and it publishes no
-- formula, so the per-badge coefficients are options rather than constants.

local MAX_LEVEL = 100
local MAX_BADGES = 16

-- Bosses take the hard curve: the 16 gym leaders, the Elite Four and champion,
-- both rivals, and Red.  These are the pokecrystal class constants the dataset
-- keys on (data/generated/trainers.lua, `classes`).
local BOSS_CLASSES = {
  -- Johto gyms
  FALKNER = true, BUGSY = true, WHITNEY = true, MORTY = true,
  CHUCK = true, JASMINE = true, PRYCE = true, CLAIR = true,
  -- Kanto gyms
  BROCK = true, MISTY = true, LT_SURGE = true, ERIKA = true,
  JANINE = true, SABRINA = true, BLAINE = true, BLUE = true,
  -- Elite Four, champion, the rivals, and the Mt. Silver fight
  WILL = true, KOGA = true, BRUNO = true, KAREN = true,
  CHAMPION = true, RED = true, RIVAL1 = true, RIVAL2 = true,
}

-- CC names its non-scaling trainers by quest; these are the vanilla Gen 2
-- classes those map onto.  SAGE is Sprout Tower, MYSTICALMAN is Eusine.
local EXEMPT_CLASSES = { SAGE = true, MYSTICALMAN = true }

return function(mod)
  mod.options:define {
    { key = "enabled", type = "toggle", label = "LEVEL MATCH", default = true },
    -- Per-badge coefficients are stored in tenths because the options menu
    -- steps integers; 45 is the 4.5 levels/badge that puts a gym at ~Lv75
    -- once 15 badges are in.
    { key = "boss_base", type = "number", label = "GYM BASE LV",
      default = 7, min = 2, max = 50 },
    { key = "boss_per_badge", type = "number", label = "GYM LV/BADGE x10",
      default = 45, min = 0, max = 99 },
    { key = "overworld_base", type = "number", label = "TRAINER BASE LV",
      default = 7, min = 2, max = 50 },
    { key = "overworld_per_badge", type = "number", label = "TRNR LV/BADGE x10",
      default = 30, min = 0, max = 99 },
    { key = "pad_boss_teams", type = "toggle", label = "PAD BOSS TEAMS",
      default = true },
    { key = "boss_full_team", type = "number", label = "BOSS TEAM AT 16",
      default = 6, min = 1, max = 6 },
    { key = "scale_wilds", type = "toggle", label = "SCALE WILDS",
      default = true },
    -- RAISE ONLY keeps each area's own character -- Route 29 stays gentler
    -- than Victory Road -- and only lifts anything the curve has outgrown.
    -- REPLACE flattens every route to one level.
    { key = "wild_mode", type = "choice", label = "WILD MODE",
      default = "raise_only",
      choices = { { "RAISE ONLY", "raise_only" }, { "REPLACE", "replace" } } },
    { key = "wild_base", type = "number", label = "WILD BASE LV",
      default = 5, min = 2, max = 50 },
    { key = "wild_per_badge", type = "number", label = "WILD LV/BADGE x10",
      default = 30, min = 0, max = 99 },
    -- -1 reads the save.  Any other value pretends that many badges, which is
    -- the only way to feel the curve on a fresh file.
    { key = "debug_badges", type = "number", label = "TEST BADGES (-1 OFF)",
      default = -1, min = -1, max = MAX_BADGES },
  }

  local function optionNumber(key, fallback)
    return tonumber(mod.options:get(key)) or fallback
  end

  local function badgeCount()
    local override = optionNumber("debug_badges", -1)
    if override >= 0 then return math.min(MAX_BADGES, override) end
    local game = mod.game
    local player = game and game.save and game.save.player
    if not player then return 0 end
    -- Both halves count, and both are id -> bool maps, exactly as
    -- src/core/gen2/Save.lua's own badge tally reads them.
    local n = 0
    for _, has in pairs(player.badges or {}) do if has then n = n + 1 end end
    for _, has in pairs(player.kantoBadges or {}) do if has then n = n + 1 end end
    return math.min(MAX_BADGES, n)
  end

  -- nil means "never scale this trainer".
  local function tierFor(classId)
    if type(classId) ~= "string" then return "overworld" end
    local id = classId:upper()
    if EXEMPT_CLASSES[id] then return nil end
    if BOSS_CLASSES[id] then return "boss" end
    return "overworld"
  end

  local function targetLevel(tier, badges)
    local base, perTenths
    if tier == "boss" then
      base = optionNumber("boss_base", 7)
      perTenths = optionNumber("boss_per_badge", 45)
    else
      base = optionNumber("overworld_base", 7)
      perTenths = optionNumber("overworld_per_badge", 30)
    end
    local level = base + (perTenths / 10) * badges
    return math.max(2, math.min(MAX_LEVEL, math.floor(level + 0.5)))
  end

  -- The wild curve is its own pair of coefficients: wilds sit a little under
  -- the overworld-trainer line so routes stay survivable.
  local function wildLevel(current, badges)
    local level = optionNumber("wild_base", 5)
      + (optionNumber("wild_per_badge", 30) / 10) * badges
    level = math.max(2, math.min(MAX_LEVEL, math.floor(level + 0.5)))
    if mod.options:get("wild_mode") == "replace" then return level end
    return math.max(tonumber(current) or 1, level)
  end

  -- Vanilla bosses carry authored teams as small as two (Falkner), which stay
  -- a pushover at Lv75 no matter the level.  Grow linearly from the authored
  -- size at 0 badges to a full team at 16.
  local function targetSize(tier, originalSize, badges)
    if tier ~= "boss" or not mod.options:get("pad_boss_teams") then
      return originalSize
    end
    local full = math.min(6, math.max(1, optionNumber("boss_full_team", 6)))
    if originalSize >= full then return originalSize end
    local grown = originalSize + (full - originalSize) * badges / MAX_BADGES
    return math.min(full, math.max(originalSize, math.floor(grown + 0.5)))
  end

  -- Battle mons are plain tables with no metatable (src/battle/gen2/Mon.lua),
  -- so a deep copy is itself a valid mon.
  local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = deepCopy(v) end
    return out
  end

  local function rescale(party, tier, badges)
    local size = #party
    if size == 0 then return party end

    -- Anchor the strongest mon to the curve and shift the rest by the same
    -- delta.  Assigning every mon the target instead would flatten the
    -- authored spread (Falkner's Lv7 Pidgey behind a Lv9 Pidgeotto) into a
    -- mono-level wall.
    local top = 0
    for _, mon in ipairs(party) do
      top = math.max(top, tonumber(mon.level) or 1)
    end
    local delta = targetLevel(tier, badges) - top

    local out = {}
    for i = 1, size do out[i] = party[i] end

    -- Pad before levelling so the clones take the same shift.  Copies cycle
    -- through the authored roster, which keeps the padding on-type for that
    -- trainer without inventing species its author never picked.
    local want = targetSize(tier, size, badges)
    for i = size + 1, want do
      out[i] = deepCopy(party[((i - 1) % size) + 1])
    end

    for _, mon in ipairs(out) do
      mon.level = math.max(1, math.min(MAX_LEVEL, (tonumber(mon.level) or 1) + delta))
      -- Mon.refreshStats only ever clamps hp DOWN to the new maximum, so a mon
      -- whose level went up would walk in on its old, much smaller hp.
      -- Clearing it makes the engine's refresh -- which runs immediately after
      -- this hook returns -- fill the mon to full.
      mon.hp = nil
    end
    return out
  end

  mod.hooks:wrap("trainer.party", function(nextFn, classId, _memberId, party)
    -- Let the rest of the chain compose the roster first; this mod only
    -- rescales whatever the trainer ended up with.
    local composed = nextFn() or party
    if not mod.options:get("enabled") then return composed end
    if type(composed) ~= "table" or #composed == 0 then return composed end

    local tier = tierFor(classId)
    if not tier then return composed end

    local badges = badgeCount()
    local ok, result = pcall(rescale, composed, tier, badges)
    if not ok then
      mod.log:error("rescale failed for %s: %s", tostring(classId), tostring(result))
      return composed
    end
    return result
  end)

  -- Grass, water and cave rolls.  The engine hands over { species, level } and
  -- keeps whatever comes back (src/world/gen2/World.lua rollEncounter).
  mod.hooks:wrap("encounter.species", function(nextFn, enc, ctx)
    local out = nextFn() or enc
    if not mod.options:get("enabled") then return out end
    if not mod.options:get("scale_wilds") then return out end
    if type(out) ~= "table" or out.level == nil then return out end
    -- The Bug Catching Contest is scored on the levels it hands out, so
    -- rescaling its mons would rewrite the minigame rather than the world.
    if ctx and ctx.kind == "contest" then return out end
    out.level = wildLevel(out.level, badgeCount())
    return out
  end)

  -- Fishing rolls come down a separate chain and are turned into a mon
  -- immediately after, so the level has to be right here.
  mod.hooks:wrap("encounter.fishing", function(nextFn, ...)
    local roll = nextFn()
    if not mod.options:get("enabled") then return roll end
    if not mod.options:get("scale_wilds") then return roll end
    if type(roll) ~= "table" or roll.species == nil or roll.level == nil then
      return roll
    end
    roll.level = wildLevel(roll.level, badgeCount())
    return roll
  end)

  mod.log:info("level_match ready -- trainer.party + wild encounter scaling")
end
