-- Tests for the game rules. Run from the project root with luajit or lua:
--   luajit tests/test_trek.lua [games]
-- `games` is how many bot-played games the fuzz test plays (default 150).

package.path = "game/?.lua;" .. package.path

local C = require("src.trek.const")
local Game = require("src.trek.game")
local storage = require("src.storage")

local NS, NQ = C.NSECTS, C.NQUADS
local failures, checks = 0, 0

local function check(cond, msg)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    end
    return cond
end

local function count(g, what)
    local n = 0
    for i = 1, NS * NS do
        if g.sect[i] == what then n = n + 1 end
    end
    return n
end

-- Everything that must always hold between commands.
local function invariants(g, where)
    local total = 0
    for i = 1, NQ * NQ do
        local q = g.quads[i]
        total = total + q.k
        if q.k < 0 or q.k > C.MAXKLQUAD then return check(false, where .. ": quadrant has " .. q.k .. " Klingons") end
    end
    if not check(total == g.klings, ("%s: galaxy holds %d Klingons, count says %d"):format(where, total, g.klings)) then return false end
    local here = g:here()
    if not check(#g.kl == here.k, ("%s: %d Klingons listed here, quadrant says %d"):format(where, #g.kl, here.k)) then return false end
    if not check(count(g, C.KLINGON) == #g.kl, where .. ": K on the grid doesn't match the list") then return false end
    for _, k in ipairs(g.kl) do
        if not check(g:at(k.x, k.y) == C.KLINGON, where .. ": a listed Klingon isn't on the grid") then return false end
    end
    local s = g.ship
    if not (g.over and g.over.reason == "destruct") then
        if not check(g:at(s.x, s.y) == s.kind, ("%s: ship not on the grid at %d,%d (found %q)"):format(where, s.x, s.y, tostring(g:at(s.x, s.y)))) then return false end
        if not check(count(g, s.kind) == 1, where .. ": more than one ship on the grid") then return false end
    end
    local bases = 0
    for i = 1, NQ * NQ do bases = bases + g.quads[i].b end
    if not check(bases == #g.bases, where .. ": starbase list and quadrants disagree") then return false end
    if not check(count(g, C.BASE) == here.b or here.nova, where .. ": starbase on the grid doesn't match") then return false end
    if not check(s.energy == s.energy and s.shield >= -0.001 and s.torps >= 0, where .. ": bad ship numbers") then return false end
    if not check(s.qx >= 0 and s.qx < NQ and s.qy >= 0 and s.qy < NQ, where .. ": ship outside the galaxy") then return false end
    if g.klings > 0 then
        check(math.abs(g.time - g.resource / g.klings) < 1e-6, where .. ": time doesn't match resources")
    end
    return true
end

-- A game with nothing in the current quadrant except the ship, for
-- setting up exact situations.
local function blank(seed, skill)
    local g = Game.new({ seed = seed or 1, skill = skill or 2, length = 1 })
    local q = g:here()
    g.klings = g.klings - q.k
    q.k, q.b, q.s, q.h, q.sys = 0, 0, 0, 0, nil
    for i, b in ipairs(g.bases) do
        if b.x == g.ship.qx and b.y == g.ship.qy then table.remove(g.bases, i) break end
    end
    g.ship.x, g.ship.y = 1, 5
    g:initQuad()
    g.events = {}
    g:takeOutput()
    return g
end

local function addKlingon(g, x, y, power)
    g:put(x, y, C.KLINGON)
    g.kl[#g.kl + 1] = { x = x, y = y, power = power or g.p.klingpwr }
    g:here().k = g:here().k + 1
    g.klings = g.klings + 1
    g:updateTime()
end

-- Setup ---------------------------------------------------------------------------

for skill = 1, 6 do
    for _, len in ipairs({ 1, 2, 4 }) do
        for seed = 1, 8 do
            local g = Game.new({ seed = seed * 7919 + skill * 31 + len, skill = skill, length = len })
            local where = ("setup skill %d length %d seed %d"):format(skill, len, seed)
            invariants(g, where)
            check(g.klings >= skill * len * 5, where .. ": too few Klingons")
            check(#g.bases >= 1 and #g.bases <= 6, where .. ": wrong number of starbases")
            check(g:here().b == 1, where .. ": ship doesn't start at a starbase")
            check(#g.kl == 0, where .. ": Klingons in the starting quadrant")
            local systems = 0
            for i = 1, NQ * NQ do if g.quads[i].sys then systems = systems + 1 end end
            check(systems == #C.SYSTEMS, where .. ": wrong number of inhabited systems")
        end
    end
end

-- Same seed, same galaxy
do
    local a, b = Game.new({ seed = 42 }), Game.new({ seed = 42 })
    check(storage.encode(a:serialize()) == storage.encode(b:serialize()), "the same seed gives a different game")
end

-- Movement --------------------------------------------------------------------------

do
    local g = blank(3)
    local e0, d0 = g.ship.energy, g.date
    local info = g:plan(g.ship.qx * NS + 6, g.ship.qy * NS + 5)
    check(info.ok and info.engine == "warp", "plan a short warp")
    check(math.abs(info.energy - 0.5 * 125 * 2) < 1, "warp 5 with shields up costs dist * 125 * 2")
    check(g:cmdMove(6, 5), "move inside the quadrant")
    check(g.ship.x == 6 and g.ship.y == 5, "ship arrived")
    check(g.ship.energy < e0 and g.date > d0, "moving costs energy and time")
    invariants(g, "after move")

    -- the computer plots a way around a star in the way...
    g:put(8, 5, C.STAR)
    local around = g:plan(g.ship.qx * NS + 9, g.ship.qy * NS + 5)
    check(around.ok and around.detour, "plan a detour around the star")
    g:cmdMove(9, 5)
    check(g.ship.x == 9 and g.ship.y == 5, "flew around the star")
    invariants(g, "after detour")

    -- ...and stops next to it when it's the destination
    g:cmdMove(8, 5)
    check(g.ship.x == 9 and g.ship.y == 5, "can't fly into a star")
    g:put(9, 1, C.STAR)
    g:cmdMove(9, 1)
    check(g.ship.x == 9 and g.ship.y == 2, "stopped next to the star")
    invariants(g, "after blocked move")

    -- lowering shields halves the cost of warp
    g:cmdShields(false)
    local info2 = g:plan(g.ship.qx * NS + 9, g.ship.qy * NS + 7)
    check(math.abs(info2.energy - 0.5 * 125) < 1, "warp with shields down costs half")
end

do
    local g = blank(4)
    local s = g.ship
    local tq = (s.qx < NQ - 1) and s.qx + 1 or s.qx - 1
    check(g:cmdWarp(tq, s.qy), "warp to the next quadrant")
    check(s.qx == tq, "arrived in the next quadrant")
    invariants(g, "after warp")
    local q = g:quad(tq, s.qy)
    check(q.known ~= nil, "arriving scans the quadrant")

    -- supernova remnants are off limits while the computer works
    local nq = g:quad(s.qx, (s.qy + 2) % NQ)
    nq.nova = true
    check(not g:cmdWarp(s.qx, (s.qy + 2) % NQ), "computer refuses to enter a supernova")
end

do
    local g = blank(5)
    g.ship.warp = 9
    g.dmg.warp = 2
    local info = g:plan(g.ship.qx * NS + 8, g.ship.qy * NS + 5)
    check(info.engine == "impulse", "impulse when the warp drive is damaged")
    g.dmg.impulse = 1
    check(not g:plan(g.ship.qx * NS + 8, g.ship.qy * NS + 5).ok, "no engines, no move")
end

-- Weapons -----------------------------------------------------------------------------

do
    local g = blank(6)
    addKlingon(g, 5, 5)
    local before = g.klings
    local t0 = g.time
    g.rng.float = function() return 0.5 end -- no misfire, no spread
    check(g:cmdTorpedo(5, 5), "fire a torpedo")
    check(g.klings == before - 1, "torpedo destroyed the Klingon")
    check(g.time > t0, "destroying a Klingon buys time")
    check(g.ship.torps == 9, "torpedo used")
    invariants(g, "after torpedo")
end

do
    local g = blank(7)
    addKlingon(g, 4, 5)
    addKlingon(g, 1, 9)
    local need = 0
    for _, k in ipairs(g.kl) do need = need + g:phaserNeed(k) end
    local plan = g:phaserPlan(need)
    check(#plan == 2 and plan[1].units >= plan[1].need and plan[2].units >= plan[2].need, "phaser plan covers both")
    check(g.ship.up, "shields start up")
    check(g:cmdPhasers(need), "fire phasers")
    check(#g.kl == 0, "phasers with the needed energy destroy every Klingon")
    check(g.ship.up, "shields come back up after phasers")
    invariants(g, "after phasers")
end

do
    local g = blank(8)
    g.ship.docked = true
    addKlingon(g, 4, 5)
    check(not g:cmdPhasers(500), "no phasers while docked")
    check(not g:cmdTorpedo(4, 5), "no torpedoes while docked")
end

-- Klingon attacks: full shields soak a hit; shields down, energy takes it
do
    local g = blank(9)
    addKlingon(g, 3, 5)
    g.rng.float = function() return 0.99 end -- no Klingon movement
    local e0, sh0 = g.ship.energy, g.ship.shield
    g:klingonsAttack()
    check(g.ship.energy == e0 and g.ship.shield < sh0, "full shields absorb the whole hit")
    g.ship.up = false
    local e1 = g.ship.energy
    g:klingonsAttack()
    check(g.ship.energy < e1, "with shields down the hit drains energy")
end

-- A torpedo into a star novas it and takes out the Klingon beside it
do
    local g = blank(10)
    g:put(5, 5, C.STAR)
    g:here().s = 1
    addKlingon(g, 6, 5)
    local seq = { 0.5, 0.5, 0.5, 0.9, 0.9 } -- no misfire, no spread, nova happens, no supernova
    local n = 0
    g.rng.float = function() n = n + 1 return seq[n] or 0.99 end
    g:cmdTorpedo(5, 5)
    check(g:at(5, 5) == C.EMPTY, "the star novaed")
    check(#g.kl == 0, "the nova destroyed the Klingon next to it")
    check(g.stats.stars == 1, "star counted")
    invariants(g, "after nova")
end

-- Docking refills; resting repairs
do
    local g = Game.new({ seed = 11 })
    g:takeOutput()
    local s = g.ship
    s.energy, s.torps = 1200, 2
    g.dmg.phaser = 1.0
    local bx, by
    for y = 0, NS - 1 do for x = 0, NS - 1 do if g:at(x, y) == C.BASE then bx, by = x, y end end end
    check(g:cmdApproach(bx, by), "approach the starbase")
    check(s.docked, "docked at the starbase")
    check(s.energy == g.p.energy and s.torps == g.p.torps, "docking refills energy and torpedoes")
    g.events = {} -- nothing to interrupt the rest
    check(g:cmdRest(0.6), "rest while docked")
    check(not g:damaged("phaser"), "docked repairs run twice as fast")
    invariants(g, "after docking")
end

-- Capture, cloak, shields
do
    local g = blank(12)
    addKlingon(g, 3, 5, 10)
    g.rng.float = function() return 0.0 end
    check(g:cmdCapture(3, 5), "demand surrender")
    check(#g.kl == 0 and g.stats.captured == 1 and g.ship.brig > 0, "a beaten Klingon surrenders")
    invariants(g, "after capture")
end

do
    local g = blank(13)
    check(g:cmdCloak(true), "cloak on")
    addKlingon(g, 3, 3)
    g.rng.float = function() return 0.99 end
    local e0 = g.ship.energy
    g:klingonsAttack()
    check(g.ship.energy == e0 and g.ship.shield == g.p.shield, "Klingons can't hit a cloaked ship")
    check(not g:cmdTorpedo(3, 3), "no torpedoes while cloaked")
end

-- Time runs out
do
    local g = blank(14)
    addKlingon(g, 9, 9)
    g.resource = g.klings * 0.05
    g:updateTime()
    g:cmdShields(false)
    g:advance(1)
    check(g.over and g.over.reason == "time", "losing when time runs out")
end

-- Winning: destroy the last Klingon
do
    local g = blank(15)
    for i = 1, NQ * NQ do g.quads[i].k = 0 end
    g.klings = 0
    addKlingon(g, 4, 5)
    g.rng.float = function() return 0.5 end
    g:cmdTorpedo(4, 5)
    check(g.over and g.over.won, "destroying the last Klingon wins")
    local total, rows = g:score()
    check(total > 0 and #rows > 0, "a won game scores")
end

-- Saving -------------------------------------------------------------------------------

do
    local g = Game.new({ seed = 99, skill = 3, length = 2 })
    g:cmdMove((g.ship.x + 3) % NS, g.ship.y)
    local text = storage.encode(g:serialize())
    local back = Game.deserialize(storage.decode(text))
    check(back ~= nil, "saved game loads")
    if back then
        check(storage.encode(back:serialize()) == text, "save round trip is exact")
        local r1, r2 = g.rng:float(), back.rng:float()
        check(r1 == r2, "random numbers continue the same after loading")
        invariants(back, "loaded game")
    end
    check(Game.deserialize({ v = 0 }) == nil, "old saves are rejected")
end

-- Fuzz: a simple bot plays whole games ---------------------------------------------------

local function nearestKlingon(g)
    local best, bd
    for _, k in ipairs(g.kl) do
        local d = g:dist(k.x, k.y)
        if not bd or d < bd then best, bd = k, d end
    end
    return best
end

local function botTurn(g, rng)
    local s = g.ship
    local roll = rng()
    -- now and then, something unusual, to exercise every command
    if roll < 0.02 then return g:cmdShields() end
    if roll < 0.03 then return g:cmdCloak() end
    if roll < 0.035 then return g:cmdRest(0.5 + rng() * 2) end
    if roll < 0.037 then return g:cmdHelp() end
    if roll < 0.038 then return g:cmdAbandon() end
    if roll < 0.04 then g:setWarp(1 + math.floor(rng() * 17) / 2) end
    if roll < 0.045 then
        return g:cmdMove(math.floor(rng() * NS), math.floor(rng() * NS))
    end
    if roll < 0.05 then
        return g:cmdTorpedo(math.floor(rng() * NS), math.floor(rng() * NS))
    end
    if s.cloaked and #g.kl > 0 then return g:cmdCloak(false) end

    local k = nearestKlingon(g)
    if k then
        if roll < 0.12 then return g:cmdCapture(k.x, k.y) end
        if not g:torpedoCheck() and roll < 0.7 then return g:cmdTorpedo(k.x, k.y) end
        if not g:phaserCheck() then
            local need = 0
            for _, e in ipairs(g:phaserPlan(1e9)) do need = need + e.need end
            return g:cmdPhasers(math.min(need, s.energy - 200, Game.MAX_PHASER))
        end
        if s.docked then
            return g:cmdMove(math.floor(rng() * NS), math.floor(rng() * NS))
        end
    end
    if g:repairTime() > 0 and #g.kl == 0 and rng() < 0.3 then
        return g:cmdRest(math.min(g:repairTime(), 1.5))
    end
    if (s.energy < 2000 or s.torps < 3) and #g.bases > 0 and not s.docked then
        if g:here().b > 0 then
            for y = 0, NS - 1 do
                for x = 0, NS - 1 do
                    if g:at(x, y) == C.BASE then return g:cmdApproach(x, y) end
                end
            end
        end
        local b = g:nearestBase()
        return g:cmdWarp(b.x, b.y)
    end
    -- head for the nearest quadrant thought to hold Klingons
    local best, bd
    for y = 0, NQ - 1 do
        for x = 0, NQ - 1 do
            local info = g:chartInfo(x, y)
            local d = math.abs(x - s.qx) + math.abs(y - s.qy)
            if d > 0 and not (info and info.nova) and (not info or info.k > 0) then
                local score = d + (info and 0 or 3)
                if not bd or score < bd then best, bd = { x, y }, score end
            end
        end
    end
    if best then return g:cmdWarp(best[1], best[2]) end
    return g:cmdRest(1)
end

local games = tonumber(arg and arg[1]) or 150
local outcomes, totalTurns = {}, 0
local seedState = 12345
local function botRng()
    seedState = (seedState * 16807) % 2147483647
    return seedState / 2147483647
end

for n = 1, games do
    local skill = (n - 1) % 6 + 1
    local length = ({ 1, 1, 2, 1, 4 })[(n - 1) % 5 + 1]
    local g = Game.new({ seed = n * 104729, skill = skill, length = length })
    local turns, ok = 0, true
    while not g.over and turns < 3000 and ok do
        turns = turns + 1
        local good, err = pcall(botTurn, g, botRng)
        if not good then
            check(false, ("game %d (skill %d length %d) turn %d crashed: %s"):format(n, skill, length, turns, tostring(err)))
            ok = false
        else
            g:takeOutput()
            ok = invariants(g, ("game %d turn %d"):format(n, turns))
        end
        if ok and turns % 97 == 0 then
            local back = Game.deserialize(storage.decode(storage.encode(g:serialize())))
            ok = check(back ~= nil, "mid-game save loads")
            if back then g = back end
        end
    end
    totalTurns = totalTurns + turns
    local reason = g.over and g.over.reason or "unfinished"
    outcomes[reason] = (outcomes[reason] or 0) + 1
    if ok and g.over then
        local total = g:score()
        check(type(total) == "number", "score is a number")
    end
end

local summary = {}
for reason, n in pairs(outcomes) do summary[#summary + 1] = reason .. " " .. n end
table.sort(summary)
print(("bot games: %d, %d turns; outcomes: %s"):format(games, totalTurns, table.concat(summary, ", ")))

print(("%d checks, %d failed"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
