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

-- MakeTrainerPartyMon fixes trainer DVs at 9/8/8/8, which is why a trainer's
-- Rattata is always the same Rattata (src/world/gen2/Trainers.lua).  A mon
-- this mod builds has to match, or a filled slot would roll differently from
-- an authored one.
local TRAINER_DVS = { attack = 9, defense = 8, speed = 8, special = 8 }

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
  -- Elite Four, champion and the rivals
  WILL = true, KOGA = true, BRUNO = true, KAREN = true,
  CHAMPION = true, RIVAL1 = true, RIVAL2 = true,
}

-- Red is the one trainer vanilla authors ABOVE anything the boss curve can
-- reach: his ace is Lv81 against a boss ceiling of Lv79 at 16 badges, so the
-- boss curve could only ever make the hardest fight in the game easier. He gets
-- his own curve. Nothing else in Crystal comes within eight levels of the
-- ceiling -- the next highest boss tops out at Lv58 -- and the Elite Four have
-- no rematch rosters here, so this tier is Red alone.
local POSTGAME_CLASSES = { RED = true }

-- Crystal Clear exempts "certain sidequest trainers (Eusine, Sprout Tower,
-- etc.)".  Off by default here: the mapping onto vanilla classes is coarse, and
-- freezing a whole class is worse than scaling it.  SAGE alone spans three
-- groups -- the Lv3-10 Sprout Tower sages CC actually names, a Lv16-22
-- Gastly/Haunter pair, and the Lv32 Tin Tower sages -- so exempting the class
-- left a late-game encounter frozen at Lv32 while gyms ran to Lv79.
-- `exempt_sidequest` restores CC's behaviour for anyone who wants it.
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
    { key = "postgame_base", type = "number", label = "RED BASE LV",
      default = 21, min = 2, max = 60 },
    -- 21 + 4.0 x 16 = Lv85, four above vanilla's Lv81, so the superboss stays
    -- the hardest thing in the game once every other tier has scaled up too.
    { key = "postgame_per_badge", type = "number", label = "RED LV/BADGE x10",
      default = 40, min = 0, max = 99 },
    -- Crystal Clear says trainers OUTSIDE gyms scale "but not as harshly as
    -- Gym trainers do", which makes gym trainers their own tier rather than
    -- ordinary route fodder. They sit between the leader and the routes.
    { key = "gym_base", type = "number", label = "GYM TRNR BASE LV",
      default = 7, min = 2, max = 50 },
    { key = "gym_per_badge", type = "number", label = "GYM TRNR LV/BADGE x10",
      default = 40, min = 0, max = 99 },
    { key = "overworld_base", type = "number", label = "TRAINER BASE LV",
      default = 7, min = 2, max = 50 },
    { key = "overworld_per_badge", type = "number", label = "TRNR LV/BADGE x10",
      default = 30, min = 0, max = 99 },
    -- Bosses and route trainers scale independently: turning this off leaves
    -- the gyms, E4 and rivals on the curve while routes keep vanilla levels.
    { key = "scale_overworld", type = "toggle", label = "SCALE ROUTE TRNRS",
      default = true },
    { key = "exempt_sidequest", type = "toggle", label = "EXEMPT SIDEQUESTS",
      default = false },
    -- A mon dragged to Lv75 still knowing its Lv7 moves is the single
    -- biggest reason scaled bosses stay easy.
    { key = "scale_movesets", type = "toggle", label = "SCALE MOVESETS",
      default = true },
    -- Crystal Clear gives its leaders "fully custom movesets". Vanilla rosters
    -- have none, so bosses draw from their TM pool as well and keep the four
    -- strongest attacks they could actually learn.
    { key = "boss_best_moves", type = "toggle", label = "BOSS TM MOVES",
      default = true },
    -- Anchoring the ACE to the curve shifts the whole team by one delta, which
    -- on an authored ramp (Sentret L9/L13/L17) drags the tail far below it.
    -- No mon ends up more than this many levels under the team's target.
    { key = "spread_cap", type = "number", label = "MAX LV BELOW ACE",
      default = 6, min = 0, max = 40 },
    { key = "evolve_scaled", type = "toggle", label = "EVOLVE SCALED MONS",
      default = true },
    -- Bosses also get the evolutions that carry no level of their own -- stones
    -- and trades -- on the reasoning that a leader scaled into the seventies
    -- would have bothered. Route trainers do not.
    { key = "boss_stone_evos", type = "toggle", label = "LEADERS USE STONES",
      default = true },
    -- The level from which a stone or trade is assumed to have happened. Below
    -- it Whitney keeps a Clefairy, which is what a 0-badge Whitney should have.
    { key = "stone_evo_level", type = "number", label = "STONE EVO FROM LV",
      default = 30, min = 2, max = 100 },
    -- Gym rosters are the thin ones: Falkner fields two, Whitney two, and the
    -- trainers standing around them often one.  Of the 63 trainers across
    -- every gym, exactly one -- Blue, in Viridian -- already fields six.
    -- Leading a gym is a job, so a leader fields a full team at any badge
    -- count; the badge ramp below is for the bosses who are not gym staff.
    { key = "fill_gym_teams", type = "toggle", label = "FULL GYM TEAMS",
      default = true },
    { key = "gym_team_size", type = "number", label = "GYM TEAM SIZE",
      default = 6, min = 1, max = 6 },
    -- Off: only the leaders fill, and the gym's other trainers keep their
    -- authored rosters.
    { key = "fill_gym_trainers", type = "toggle", label = "FILL GYM TRAINERS",
      default = true },
    -- A thin pool widens to the gym's second type.  Ghost is only four species
    -- across every trainer in the game, which cannot fill one gym, let alone
    -- Ecruteak's five trainers.
    { key = "widen_thin_pools", type = "toggle", label = "WIDEN THIN POOLS",
      default = true },
    -- The badge ramp for bosses who are NOT gym staff: the Elite Four, the
    -- champion, both rivals and Red.
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
    -- Raikou, Entei and Suicune never reach encounter.species: the roamer
    -- check replaces the map's encounter and starts the battle itself. Their
    -- level lives in the save, so scaling them WRITES TO THE SAVE and sticks
    -- even if this mod is later removed. Its own switch for that reason.
    { key = "scale_roamers", type = "toggle", label = "SCALE ROAMERS",
      default = true },
    -- ------------------------------------------------------------------
    -- Rewards.  Scaling the enemy also scales what beating it pays.  Exp is
    -- baseExp x the defeated level / 7, so at 8 badges a Bug Catcher hands
    -- over 2124 exp where vanilla's Lv3 one handed over 66 -- 32x, on a curve
    -- that only steepens.  Prize money is baseMoney x the level of the LAST
    -- mon on the roster, which inflates the same way: 3-10x on routes.
    --
    -- That inflation makes the game EASIER.  Enemies follow the badge count
    -- and nothing follows the player, so exp that outruns the curve buys a
    -- party the curve can no longer threaten.  These rows put the player on a
    -- curve as well.
    --
    -- Off by default.  It changes how a whole run paces, and it is not what
    -- earlier versions of this mod did.
    { key = "lean_rewards", type = "toggle", label = "LEAN REWARDS",
      default = false },
    -- Which curve the player's own level cap follows.  BOSS is the level of
    -- the gym leader the badge count says you can face, so a capped party
    -- meets a leader level for level and has to win the fight on play.
    { key = "exp_cap_tier", type = "choice", label = "EXP CAP CURVE",
      default = "boss",
      choices = { { "BOSS", "boss" }, { "GYM TRNR", "gym" },
                  { "ROUTE TRNR", "overworld" }, { "OFF", "off" } } },
    -- A mon at or above the cap keeps this share, so a capped party creeps
    -- instead of freezing.  0 stops it dead.
    { key = "exp_over_cap", type = "number", label = "EXP OVER CAP %",
      default = 10, min = 0, max = 100 },
    { key = "exp_rate", type = "number", label = "EXP UNDER CAP %",
      default = 100, min = 5, max = 300 },
    { key = "money_rate", type = "number", label = "PRIZE MONEY %",
      default = 50, min = 0, max = 300 },
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

  -- sBattleTowerChallengeState: 0 normal, 2 tower (src/core/gen2/Save.lua
  -- battleTowerState). The Battle Tower is a level-normalised format whose
  -- whole point is that adventure progress does NOT follow you in -- the cart
  -- switches badge stat boosts and badge type boosts off inside it -- and its
  -- opponents are authored down to their stats, PP and held items. Scaling them
  -- to badge count replaces a tuned gauntlet with a lottery: in the Lv50 room
  -- a 10-badge player would face Lv37 opponents, and in the Lv10 room the same
  -- player would face Lv37 opponents while capped at Lv10 themselves.
  local TOWER_CHALLENGE_IN_PROGRESS = 2

  local function inTowerChallenge()
    local save = mod.game and mod.game.save
    local tower = save and save.battleTower
    return tower ~= nil
      and tonumber(tower.challenge) == TOWER_CHALLENGE_IN_PROGRESS
  end

  -- Which (class, member) pairs stand inside a gym. Read from the map data
  -- rather than from class names, because gym trainers share classes with
  -- route trainers -- the Lass in Goldenrod Gym and the Lass on Route 34 are
  -- both LASS, and only one of them is a gym trainer.
  --
  --   * a sight trainer is an object carrying `trainer = { class, member }`
  --   * the leader is an object whose script holds a `loadtrainer` row
  local gymsAnalysed, gymMember, classIndexOf = false, {}, {}
  -- classIndex -> { memberConstant -> roster index }
  local memberIndexOf = {}
  -- "classIndex:member" -> { pool = {species...}, sight = bool }
  local gymOf = {}
  -- how often the game gives each species to a trainer, anywhere
  local speciesUse = nil
  -- how many species carry each type, across the whole dex.  A type that is
  -- everywhere (NORMAL, FLYING) says less about a team than a rare one.
  local typeUse = nil

  local function isGymMap(id)
    if type(id) ~= "string" then return false end
    if id:find("SPEECH_HOUSE", 1, true) then return false end
    return id:find("_GYM", 1, true) ~= nil
  end

  -- How often each species appears on a trainer anywhere in the game.  Used
  -- both to BOUND a pool -- nothing the game never fields -- and to ORDER it.
  --
  -- The ordering is the whole trick.  Sorted alphabetically, Violet Gym drew
  -- Aerodactyl and Charizard, because a type pool contains every one-off
  -- carried by an end-game trainer.  How often the game itself hands a species
  -- to a trainer is a good proxy for how ordinary it is: Flying by frequency
  -- opens Golbat, Zubat, Pidgey and Butterfree, and Charizard never surfaces.
  local function trainerSpecies(trainers)
    local count = {}
    for _, class in pairs(trainers.classes or {}) do
      for _, row in ipairs((type(class) == "table" and class.trainers) or {}) do
        for _, mon in ipairs(row.party or {}) do
          if mon.species then count[mon.species] = (count[mon.species] or 0) + 1 end
        end
      end
    end
    return count
  end

  local function rosterOf(trainers, className, member)
    local class = trainers.classes and trainers.classes[className]
    local row = class and class.trainers and class.trainers[member]
    return (row and row.party) or {}
  end

  -- A roster's theme, taken from the roster itself.
  --
  -- Requiring the type EVERY mon shares is too strict outside a gym: Bruno
  -- carries an Onix among four fighters and Karen a Vileplume among three
  -- dark types, and a strict intersection calls both of them themeless.  A
  -- type qualifies here by covering at least half the roster.
  --
  -- Among the types that qualify, the RAREST across the dex wins, because
  -- coverage alone picks the wrong one twice over: NORMAL is on so much of
  -- the dex that it would theme half the game, and every one of Lance's six
  -- is part FLYING while only half are DRAGON.  Rarity is what "characteristic
  -- of this team" actually means.
  --
  -- nil means the roster has no theme -- a rival's mixed six -- and padding
  -- falls back to cloning rather than inventing one.
  local function typesOf(pokemon, roster)
    if not roster or #roster == 0 then return nil, nil end
    local count = {}
    for _, mon in ipairs(roster) do
      local def = pokemon[mon.species]
      local seen = {}
      for _, t in ipairs((def and def.types) or {}) do
        if not seen[t] then
          seen[t] = true
          count[t] = (count[t] or 0) + 1
        end
      end
    end
    local need = math.ceil(#roster / 2)
    local ranked = {}
    for t, c in pairs(count) do
      if c >= need then ranked[#ranked + 1] = t end
    end
    if #ranked == 0 then return nil, nil end
    local function rarest(a, b)
      local ua, ub = (typeUse and typeUse[a]) or 0, (typeUse and typeUse[b]) or 0
      if ua ~= ub then return ua < ub end
      return a < b
    end
    table.sort(ranked, rarest)
    local primary, secondary = ranked[1], ranked[2]
    -- A mono-type roster leaves nothing to widen into, and some pools cannot
    -- fill a team alone: every Dragon in the game evolves into Dragonite, so
    -- Clair's pool has one usable form in it.  Fall back to the commonest type
    -- that did NOT reach half the roster -- Kingdra's WATER, in her case.
    if not secondary then
      local best = nil
      for t, c in pairs(count) do
        if t ~= primary and (not best or c > count[best]
            or (c == count[best] and rarest(t, best))) then
          best = t
        end
      end
      secondary = best
    end
    return primary, secondary
  end

  local function poolFor(pokemon, usable, primary, secondary)
    local out, seen = {}, {}
    local function add(want)
      if not want then return end
      local names = {}
      for species in pairs(usable) do names[#names + 1] = species end
      -- commonest first, alphabetical to break ties: deterministic, so the
      -- same trainer always fields the same team
      table.sort(names, function(a, b)
        local ca, cb = usable[a] or 0, usable[b] or 0
        if ca ~= cb then return ca > cb end
        return a < b
      end)
      for _, species in ipairs(names) do
        local def = pokemon[species]
        for _, t in ipairs((def and def.types) or {}) do
          if t == want and not seen[species] then
            seen[species] = true
            out[#out + 1] = species
          end
        end
      end
    end
    add(primary)
    if secondary and mod.options:get("widen_thin_pools") then add(secondary) end
    return out
  end

  local function analyseGyms(data)
    local trainers = data and data.trainers
    local maps = data and data.gen2Maps
    local scripts = data and data.gen2Scripts
    if not (trainers and trainers.classes and maps and scripts) then return false end
    for name, class in pairs(trainers.classes) do
      if type(class) == "table" and class.index then
        classIndexOf[name] = class.index
        -- The hook is handed the member CONSTANT (CARRIE), never the index:
        -- Battle.lua sends `trainer.memberId`, which Trainers.lookup fills
        -- from the roster row's `id`. Map objects store the numeric index, so
        -- the two have to be reconciled. `id` is unique inside a class -- the
        -- cart disambiguates its own repeats (CONNIE1, CONNIE2, CONNIE3).
        local byId = {}
        for i, row in ipairs(class.trainers or {}) do
          if type(row) == "table" and row.id then byId[row.id] = i end
        end
        memberIndexOf[class.index] = byId
      end
    end
    local pokemon = data and data.pokemon
    local nameOfIndex = {}
    for name, class in pairs(trainers.classes) do
      if type(class) == "table" and class.index then
        nameOfIndex[class.index] = name
      end
    end
    speciesUse = trainerSpecies(trainers)
    typeUse = {}
    for _, def in pairs(pokemon or {}) do
      for _, t in ipairs((type(def) == "table" and def.types) or {}) do
        typeUse[t] = (typeUse[t] or 0) + 1
      end
    end

    for mapId, map in pairs(maps) do
      if isGymMap(mapId) and type(map) == "table" then
        -- Two kinds of gym occupant: a sight trainer carries
        -- `trainer = { class, member }`, and the leader is an object whose
        -- script holds a `loadtrainer` row.  Both are read from the map so
        -- the roster follows the ROM rather than a list that drifts -- LASS
        -- members 1 and 2 stand in Goldenrod Gym, member 9 in Celadon, and
        -- the other fourteen are scattered across the world.
        local members, leader = {}, nil
        for _, obj in ipairs(map.objects or {}) do
          local t = obj.trainer
          if type(t) == "table" and t.class and t.member then
            gymMember[t.class .. ":" .. t.member] = true
            members[#members + 1] = { class = t.class, member = t.member,
                                      sight = true }
          end
          local list = obj.scriptKey and scripts[obj.scriptKey]
          for _, row in ipairs(list or {}) do
            if row.op == "loadtrainer" and row.class and row.member then
              gymMember[row.class .. ":" .. row.member] = true
              local entry = { class = row.class, member = row.member }
              members[#members + 1] = entry
              leader = leader or entry
            end
          end
        end
        -- The gym's type comes from the LEADER's own team, so every trainer
        -- in the gym draws from one on-theme pool.
        if leader and pokemon then
          local leaderName = nameOfIndex[leader.class]
          local roster = leaderName
            and rosterOf(trainers, leaderName, leader.member) or {}
          local primary, secondary = typesOf(pokemon, roster)
          local pool = poolFor(pokemon, speciesUse, primary, secondary)
          for _, m in ipairs(members) do
            gymOf[m.class .. ":" .. m.member] = { pool = pool, sight = m.sight }
          end
        end
      end
    end
    gymsAnalysed = true
    return true
  end

  -- The numeric roster index behind whatever the hook was handed.
  local function memberIndex(classIndex, memberId)
    local member = tonumber(memberId)
    if member then return member end
    if type(memberId) ~= "string" then return nil end
    local byId = memberIndexOf[classIndex]
    return byId and byId[memberId] or nil
  end

  local function inGym(classId, memberId)
    local index = type(classId) == "string" and classIndexOf[classId]
      or tonumber(classId)
    if not index then return false end
    -- A numeric member (Gen 1's shape, and the engine's own `or 1` fallback)
    -- is already an index; a constant resolves through the class roster.
    -- An unresolvable member is NOT a gym trainer: the old `or 1` fallback
    -- made every Lass in the game answer for the one standing in Goldenrod
    -- Gym, so route trainers took the harsher gym curve.
    local member = memberIndex(index, memberId)
    if not member then return false end
    return gymMember[index .. ":" .. member] == true
  end

  -- The gym record for a trainer, or nil when they do not stand in one.
  local function gymEntry(classId, memberId)
    local index = type(classId) == "string" and classIndexOf[classId]
      or tonumber(classId)
    if not index then return nil end
    local member = memberIndex(index, memberId)
    if not member then return nil end
    return gymOf[index .. ":" .. member]
  end

  -- nil means "never scale this trainer".
  local function tierFor(classId, memberId)
    if type(classId) ~= "string" then return "overworld" end
    local id = classId:upper()
    if EXEMPT_CLASSES[id] and mod.options:get("exempt_sidequest") then
      return nil
    end
    if POSTGAME_CLASSES[id] then return "postgame" end
    if BOSS_CLASSES[id] then return "boss" end
    -- a leader is already a boss above; what is left inside a gym is its staff
    if inGym(classId, memberId) then return "gym" end
    return "overworld"
  end

  local function targetLevel(tier, badges)
    local base, perTenths
    if tier == "postgame" then
      base = optionNumber("postgame_base", 21)
      perTenths = optionNumber("postgame_per_badge", 40)
    elseif tier == "boss" then
      base = optionNumber("boss_base", 7)
      perTenths = optionNumber("boss_per_badge", 45)
    elseif tier == "gym" then
      base = optionNumber("gym_base", 7)
      perTenths = optionNumber("gym_per_badge", 40)
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

  -- The player's own cap, read off the same curves the enemies use.  nil
  -- means uncapped.
  local function expCapLevel()
    local tier = mod.options:get("exp_cap_tier")
    if tier == nil or tier == "off" then return nil end
    return targetLevel(tier, badgeCount())
  end

  -- Vanilla bosses carry authored teams as small as two (Falkner), which stay
  -- a pushover at Lv75 no matter the level.  Grow linearly from the authored
  -- size at 0 badges to a full team at 16.
  local function targetSize(tier, originalSize, badges, gym)
    -- Standing in a gym is a job, not a badge reward: a leader fields a full
    -- team the day you walk in, whether that is your first badge or your
    -- fifteenth.  The badge ramp below is for the bosses who are not gym
    -- staff -- the Elite Four, the champion, both rivals and Red.
    if gym and mod.options:get("fill_gym_teams") then
      if gym.sight and not mod.options:get("fill_gym_trainers") then
        return originalSize
      end
      return math.max(originalSize,
        math.min(6, math.max(1, optionNumber("gym_team_size", 6))))
    end
    if not (tier == "boss" or tier == "postgame")
        or not mod.options:get("pad_boss_teams") then
      return originalSize
    end
    local full = math.min(6, math.max(1, optionNumber("boss_full_team", 6)))
    if originalSize >= full then return originalSize end
    local grown = originalSize + (full - originalSize) * badges / MAX_BADGES
    return math.min(full, math.max(originalSize, math.floor(grown + 0.5)))
  end

  -- A boss dragged to Lv50 was still fielding an unevolved Pidgey, and the
  -- padded clones inherited it. Follow the species' own EVOLVE_LEVEL chain as
  -- far as the new level allows, so a scaled roster looks like a team that got
  -- there rather than one that was stretched.
  --
  -- EVOLVE_LEVEL and EVOLVE_STAT carry their own level and apply to everyone.
  -- EVOLVE_ITEM and EVOLVE_TRADE carry none, so they are a judgement rather
  -- than a rule: bosses take them from `stone_evo_level` upward, route trainers
  -- never. EVOLVE_HAPPINESS is left out -- Golbat stays a Golbat.
  --
  -- Several species branch (Gloom to Vileplume or Bellossom, Poliwhirl to
  -- Poliwrath or Politoed, Eevee three ways). The first listed branch wins:
  -- arbitrary, but deterministic, so a given leader always fields the same
  -- team.
  local NO_LEVEL_EVOS = { EVOLVE_ITEM = true, EVOLVE_TRADE = true }

  local function evolvedFor(species, level, data, allowNoLevel)
    local pokemon = data and data.pokemon
    if not pokemon then return species end
    local current = species
    -- a guard rather than trusting the data to be acyclic
    for _ = 1, 8 do
      local def = pokemon[current]
      local nextForm = nil
      local threshold = optionNumber("stone_evo_level", 30)
      for _, evo in ipairs((def and def.evolutions) or {}) do
        local method = evo.method
        if evo.into and pokemon[evo.into] then
          if (method == "EVOLVE_LEVEL" or method == "EVOLVE_STAT")
              and (tonumber(evo.level) or math.huge) <= level then
            nextForm = evo.into
            break
          elseif allowNoLevel and NO_LEVEL_EVOS[method] and level >= threshold then
            nextForm = evo.into
            break
          end
        end
      end
      if not nextForm then break end
      current = nextForm
    end
    return current
  end

  local function moveEntry(data, id)
    local def = data.moves and data.moves[id]
    local pp = (def and def.pp) or 0
    return { id = id, pp = pp, maxPp = pp }
  end

  -- Every move learned at or below `level`, in learn order, deduped. The
  -- engine keeps a rolling window of four (src/battle/gen2/Mon.lua
  -- movesAtLevel), so the last four of this list is what a wild mon of that
  -- level would actually know.
  local function levelPool(def, level)
    local out, seen = {}, {}
    for _, entry in ipairs((def and def.levelMoves) or {}) do
      if (entry.level or 1) <= level and not seen[entry.move] then
        seen[entry.move] = true
        out[#out + 1] = entry.move
      end
    end
    return out, seen
  end

  -- Raw power overstates a move that spends a turn charging, spends the next
  -- turn recharging, or faints the user. Halving them keeps SOLARBEAM and
  -- HYPER_BEAM from crowding out moves that actually hit every turn, and
  -- SELFDESTRUCT from being picked at all.
  local DISCOUNT = {
    -- a turn spent charging or recharging
    EFFECT_SOLARBEAM = 0.5, EFFECT_HYPER_BEAM = 0.5, EFFECT_FLY = 0.5,
    EFFECT_SKY_ATTACK = 0.5, EFFECT_RAZOR_WIND = 0.5,
    -- the user does not survive it
    EFFECT_SELFDESTRUCT = 0.1,
    EFFECT_RECOIL_HIT = 0.85,
    -- dead weight unless a condition the AI cannot arrange is already true:
    -- DREAM_EATER needs a sleeping target, SNORE a sleeping user, the two
    -- counters an incoming hit of the right kind, FALSE_SWIPE deliberately
    -- will not finish anything off.
    EFFECT_DREAM_EATER = 0.15, EFFECT_SNORE = 0.15,
    EFFECT_COUNTER = 0.15, EFFECT_MIRROR_COAT = 0.15,
    EFFECT_FALSE_SWIPE = 0.15, EFFECT_BIDE = 0.15,
    -- damage that only arrives later, or only after several unbroken turns
    EFFECT_FUTURE_SIGHT = 0.5,
    EFFECT_ROLLOUT = 0.6, EFFECT_FURY_CUTTER = 0.6,
  }

  -- Expected damage per use, with STAB. Status moves score 0 and are only
  -- reached for when a species has fewer than four attacks available.
  local function moveScore(data, def, id)
    local m = data.moves and data.moves[id]
    if not m or (m.power or 0) <= 0 then return 0 end
    local score = (m.power or 0) * ((m.accuracy or 100) / 100)
    score = score * (DISCOUNT[m.effect] or 1)
    for _, t in ipairs((def and def.types) or {}) do
      if t == m.type then return score * 1.5 end
    end
    return score
  end

  local function rebuildMoves(mon, data, tier)
    local def = data and data.pokemon and data.pokemon[mon.species]
    if not def then return end
    local level = mon.level or 1
    local pool, inPool = levelPool(def, level)

    local chosen, seen = {}, {}
    local function take(id)
      if not id or seen[id] or #chosen >= 4 then return end
      if not (data.moves and data.moves[id]) then return end
      seen[id] = true
      chosen[#chosen + 1] = id
    end

    local bossBest = (tier == "boss" or tier == "postgame")
      and mod.options:get("boss_best_moves")

    -- Off a boss, moves the author picked that the species never learns by
    -- level are deliberate TM coverage and are kept. On a boss they compete on
    -- merit instead: privileging them is what put MIMIC and MUD_SLAP on a
    -- Lv50 gym team and left it hitting like a Lv7 one.
    if not bossBest then
      for _, entry in ipairs(mon.moves or {}) do
        local id = entry and entry.id
        if id and not inPool[id] then take(id) end
      end
    end

    if bossBest then
      local candidates = {}
      for _, entry in ipairs(mon.moves or {}) do
        if entry and entry.id then candidates[#candidates + 1] = entry.id end
      end
      for _, id in ipairs(pool) do candidates[#candidates + 1] = id end
      for _, id in ipairs(def.tmhm or {}) do candidates[#candidates + 1] = id end
      table.sort(candidates, function(a, b)
        local sa, sb = moveScore(data, def, a), moveScore(data, def, b)
        if sa == sb then return a < b end
        return sa > sb
      end)
      for _, id in ipairs(candidates) do take(id) end
    end

    -- Fill from the newest level-up moves backwards: what the species would
    -- know at this level.
    for i = #pool, 1, -1 do take(pool[i]) end

    if #chosen == 0 then return end
    local built = {}
    for _, id in ipairs(chosen) do built[#built + 1] = moveEntry(data, id) end
    mon.moves = built
  end

  -- Mon.new stamps `experience` from the level it built at, so rewriting the
  -- level leaves that field describing the old one. Nothing reads an enemy's
  -- experience today -- rewards come from the loser's LEVEL, and the exp bar is
  -- drawn for the player's party only -- but Mon.gainExperience recomputes the
  -- level FROM it, so a stale total is a trap for anything that ever grants exp
  -- to a trainer's mon. Recompute it rather than leave a lie in the data.
  --
  -- Clearing it instead would be worse: that path reads `(mon.experience or 0)`
  -- and would compute level 1.
  --
  -- This is the engine's own module, not another mod, and the sandbox permits
  -- it (only io/os/debug/package/ffi/love/jit are denied). Loaded through pcall
  -- so a future engine that moves it degrades to leaving experience alone.
  local monModule, monTried = nil, false
  local function engineMon()
    if not monTried then
      monTried = true
      local ok, module = pcall(require, "src.battle.gen2.Mon")
      if ok then monModule = module end
    end
    return monModule
  end

  local function refreshExperience(mon, data)
    local M = engineMon()
    if not (M and M.growthFor and M.experienceForLevel) then return end
    local def = data and data.pokemon and data.pokemon[mon.species]
    if not def then return end
    local ok, exp = pcall(function()
      return M.experienceForLevel(M.growthFor(data, def.growthRate), mon.level or 1)
    end)
    if ok and type(exp) == "number" then mon.experience = exp end
  end

  -- Battle mons are plain tables with no metatable (src/battle/gen2/Mon.lua),
  -- so a deep copy is itself a valid mon.
  local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = deepCopy(v) end
    return out
  end

  local function rescale(party, tier, badges, data, gym)
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
    local target = targetLevel(tier, badges)
    local delta = target - top
    -- the floor the tail is not allowed to sink below
    local cap = optionNumber("spread_cap", 6)
    local floorLevel = math.max(1, math.min(target, target - math.max(0, cap)))

    local out = {}
    for i = 1, size do out[i] = party[i] end

    -- Pad before levelling, so the new mons take the same shift and the same
    -- evolutions as the authored ones.
    --
    -- The species come from a TYPE POOL, not from cloning.  Cloning is what
    -- turned a scaled Morty into six identical Gengar: evolution collapses an
    -- evolutionary line, so a roster that varied only by stage ends up
    -- uniform.  The pool is drawn only from species the game actually gives
    -- to some trainer, ordered by how often it does, so nothing is invented
    -- and nothing is off-theme.
    --
    -- Cloning survives as the FALLBACK, for a roster that shares no type at
    -- all -- a rival's team does not, and inventing a theme for it would be
    -- worse than a repeat.
    local want = targetSize(tier, size, badges, gym)
    if want > size then
      local pokemon = data and data.pokemon
      local pool = gym and gym.pool
      if (not pool or #pool == 0) and pokemon and speciesUse then
        local primary, secondary = typesOf(pokemon, party)
        if primary then
          pool = poolFor(pokemon, speciesUse, primary, secondary)
        end
      end
      local Mon = engineMon()
      local canBuild = pool and #pool > 0 and Mon and Mon.new and data

      -- Dedupe on what a mon will BE after the levelling pass, not on what it
      -- is now.  Clair's authored roster is three Dragonair, which all evolve
      -- into Dragonite: matching on the pre-evolution name let the pool hand
      -- her two more Dragonite on top, for five.  The species compared here
      -- are the ones the player will actually see.
      local stones = (tier == "boss" or tier == "postgame")
        and mod.options:get("boss_stone_evos")
      local function finalForm(species, level)
        if not (data and mod.options:get("evolve_scaled")) then return species end
        local shifted = math.max(1, math.min(MAX_LEVEL,
          math.max((tonumber(level) or 1) + delta, floorLevel)))
        return evolvedFor(species, shifted, data, stones)
      end

      local have = {}
      for _, m in ipairs(out) do
        have[finalForm(m.species, m.level)] = true
      end
      local pick = 1
      while #out < want do
        -- levels cycle the authored roster, so the team keeps its own spread
        local donor = party[(#out % size) + 1]
        local built = nil
        if canBuild then
          local species, form = nil, nil
          for lap = 1, 2 do
            for _ = 1, #pool do
              local candidate = pool[((pick - 1) % #pool) + 1]
              pick = pick + 1
              local grown = finalForm(candidate, donor.level or 5)
              -- the first lap prefers forms not already on the team; the
              -- second allows repeats, which is all a four-species pool offers
              if candidate and (lap == 2 or not have[grown]) then
                species, form = candidate, grown
                break
              end
            end
            if species then break end
          end
          if species then
            built = Mon.new(data, species, donor.level or 5,
              { dvs = { attack = TRAINER_DVS.attack,
                        defense = TRAINER_DVS.defense,
                        speed = TRAINER_DVS.speed,
                        special = TRAINER_DVS.special } })
            if built then have[form] = true end
          end
        end
        out[#out + 1] = built or deepCopy(donor)
      end
    end

    for _, mon in ipairs(out) do
      local shifted = (tonumber(mon.level) or 1) + delta
      if shifted < floorLevel then shifted = floorLevel end
      mon.level = math.max(1, math.min(MAX_LEVEL, shifted))
      -- Before experience and moves: growth rate, the learnset and the TM pool
      -- all belong to the species, so the evolution has to land first.
      -- Mon.refreshStats calls syncIdentity, which repairs name, types, gender
      -- and the base stats from whatever species is set here.
      if data and mod.options:get("evolve_scaled") then
        local stones = (tier == "boss" or tier == "postgame")
          and mod.options:get("boss_stone_evos")
        mon.species = evolvedFor(mon.species, mon.level, data, stones)
      end
      -- Mon.refreshStats only ever clamps hp DOWN to the new maximum, so a mon
      -- whose level went up would walk in on its old, much smaller hp.
      -- Clearing it makes the engine's refresh -- which runs immediately after
      -- this hook returns -- fill the mon to full.
      mon.hp = nil
      if data then refreshExperience(mon, data) end
      if data and mod.options:get("scale_movesets") then
        rebuildMoves(mon, data, tier)
      end
    end
    return out
  end

  mod.hooks:wrap("trainer.party", function(nextFn, classId, _memberId, party)
    -- Let the rest of the chain compose the roster first; this mod only
    -- rescales whatever the trainer ended up with.
    local composed = nextFn() or party
    if not mod.options:get("enabled") then return composed end
    if type(composed) ~= "table" or #composed == 0 then return composed end
    if inTowerChallenge() then return composed end

    -- the gym walk has to happen before the first tier lookup, and retries
    -- until it succeeds rather than latching on a failed attempt
    if not gymsAnalysed then
      local okGym, errGym = pcall(analyseGyms, mod.game and mod.game.data)
      if not okGym then
        gymsAnalysed = true
        mod.log:error("could not map the gyms: %s", tostring(errGym))
      end
    end

    local tier = tierFor(classId, _memberId)
    if not tier then return composed end
    if tier == "overworld" and not mod.options:get("scale_overworld") then
      return composed
    end

    local badges = badgeCount()
    local data = mod.game and mod.game.data
    local gym = gymEntry(classId, _memberId)
    local ok, result = pcall(rescale, composed, tier, badges, data, gym)
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

  -- The three roaming beasts bypass every encounter hook: World's roamer check
  -- runs before ChooseWildEncounter, builds the mon from the save slot and
  -- calls startBattle directly, returning before rollEncounter. (The engine's
  -- own comment in src/core/gen2/Roamers.lua says encounter.species "still runs
  -- downstream" for them -- it does not; the branch returns first.)
  --
  -- `roamer.encountered` fires from inside the roll that picked the beast, and
  -- its payload carries the LIVE save slot -- Roamers.slot returns
  -- save.roamers[index] itself, not a copy -- so setting slot.level here is
  -- read by Roamers.beginBattle a moment later when it builds the mon.
  mod.events:on("roamer.encountered", function(payload)
    if not mod.options:get("enabled") then return end
    if not mod.options:get("scale_wilds") then return end
    if not mod.options:get("scale_roamers") then return end
    local slot = payload and payload.slot
    if type(slot) ~= "table" then return end
    local current = tonumber(slot.level) or 40
    local want = wildLevel(current, badgeCount())
    if want == current then return end
    slot.level = want
    -- Banked HP is the beast's wound between encounters. Leaving it alone
    -- keeps that meaning; a raised level simply makes the same banked value a
    -- smaller share of a bigger bar, which is what a hurt beast should look
    -- like. Only an untouched slot (hp 0) gets a full bar, which beginBattle
    -- already does for itself.
    mod.log:info("roamer %s scaled to L%d", tostring(slot.species), want)
  end)

  -- ------------------------------------------------------------------
  -- Rewards
  -- ------------------------------------------------------------------

  -- `exp.gain` is called once per recipient, per KO, with the mon that is
  -- about to be paid (src/battle/gen2/Battle.lua giveExperiencePass).  The
  -- cap is therefore per mon, not per party: a fresh Lv5 catch still earns at
  -- full rate while the rest of a capped team creeps.
  --
  -- The Battle Tower is left out for the same reason it is left out of
  -- scaling -- it is a level-normalised format, and starving its exp would
  -- tax a mode the curve never touched.
  mod.hooks:wrap("exp.gain", function(nextFn, ctx)
    local amount = nextFn()
    if type(amount) ~= "number" then return amount end
    if not mod.options:get("enabled") then return amount end
    if not mod.options:get("lean_rewards") then return amount end
    if inTowerChallenge() then return amount end

    local cap = expCapLevel()
    local level = tonumber(ctx and ctx.mon and ctx.mon.level)
    local percent
    if cap and level and level >= cap then
      percent = optionNumber("exp_over_cap", 10)
    else
      percent = optionNumber("exp_rate", 100)
    end
    if percent == 100 then return amount end
    return math.floor(amount * percent / 100)
  end)

  -- Prize money has no hook.  `Prize.award` reads the reward through the
  -- module table -- `local quarter = Prize.reward(opts.baseMoney, opts.level)`
  -- -- and `Prize.reward` is a pure function with exactly that one caller, so
  -- wrapping it scales the payout and the "got Y1234 for winning" line that
  -- quotes it, and nothing else.
  --
  -- The vanilla function is parked on the table so a reload wraps the
  -- original rather than stacking a second multiplier on the first wrapper.
  -- The wrapper reads the options every call, so turning the mod off restores
  -- vanilla payouts without needing to unwrap.
  local okPrize, Prize = pcall(require, "src.battle.gen2.Prize")
  if okPrize and type(Prize) == "table" and type(Prize.reward) == "function" then
    Prize.levelMatchVanillaReward = Prize.levelMatchVanillaReward or Prize.reward
    local vanillaReward = Prize.levelMatchVanillaReward
    Prize.reward = function(baseMoney, level)
      local amount = vanillaReward(baseMoney, level)
      if type(amount) ~= "number" then return amount end
      if not mod.options:get("enabled") then return amount end
      if not mod.options:get("lean_rewards") then return amount end
      local percent = optionNumber("money_rate", 50)
      if percent == 100 then return amount end
      return math.floor(amount * percent / 100)
    end
  else
    mod.log:warn("prize money left at vanilla: could not reach Prize.reward")
  end

  mod.log:info("level_match ready -- trainer.party, wild encounters, rewards")
end
