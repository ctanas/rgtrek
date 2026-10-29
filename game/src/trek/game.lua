-- The game: galaxy, ship, time and score, after BSD trek. Pure Lua with no
-- LÖVE calls, so the tests can run it.
--
-- Coordinates: x is the column, y the row, both from 0. Quadrants are 0-7,
-- sectors 0-9. "Galaxy sectors" (0-79) put the two together.
--
-- Commands (in commands.lua) change the state straight away and append a
-- stream of messages and visual cues to self.out, which the play screen
-- plays back in order.

local C = require("src.trek.const")
local Rng = require("src.trek.rng")

local Game = {}
Game.__index = Game
Game.SAVE_VERSION = 1

local NS, NQ = C.NSECTS, C.NQUADS
local floor, sqrt = math.floor, math.sqrt
local LOG_KEEP = 150

local function round(v)
    return floor(v + 0.5)
end
Game.round = round

-- Course in degrees for a step of (dx, dy): 0 is up, 90 is right.
function Game.course(dx, dy)
    local a = math.deg(math.atan2 and math.atan2(dx, -dy) or math.atan(dx, -dy))
    if a < 0 then a = a + 360 end
    return a
end

-- Setup -----------------------------------------------------------------------

-- Parameters for a skill (1-6) and length (1, 2 or 4), as in BSD setup.c.
local function params(skill, length, rng)
    local p = {}
    p.bases = (skill >= 6) and 1 or (rng:int(6 - skill) + 2)
    p.time = 6 * length + 2
    local k = floor(skill * length * 3.5 * (rng:float() + 0.75))
    if k < skill * length * 5 then k = skill * length * 5 end
    p.klings = k
    p.energy = 5000
    p.shield = 1500
    p.torps = 10
    p.reserves = math.max(1, (6 - skill) * 2)
    p.crew = 387
    p.brig = 400
    p.klingcrew = 200
    p.klingpwr = 100 + 150 * skill + (skill >= 6 and 150 or 0)
    p.regen = math.max(0, (5 - skill) * 0.05)
    p.damfac = math.log(skill + 0.5)
    p.date = (rng:int(20) + 20) * 100
    return p
end

function Game.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Game)
    self.v = Game.SAVE_VERSION
    self.skill = opts.skill or 2
    self.length = opts.length or 1
    local rng = Rng.new(opts.seed or os.time())
    self.rng = rng
    local p = params(self.skill, self.length, rng)
    self.p = p
    self.date, self.start = p.date, p.date
    self.klings = p.klings
    self.resource = p.klings * p.time
    self.time = p.time
    self.stats = {
        killed = 0, captured = 0, captives = 0, basesKilled = 0, basesLost = 0,
        stars = 0, inhab = 0, deaths = 0, helps = 0, shipLost = false,
    }
    self.log, self.logN = {}, 0
    self.out = {}
    self.dmg = {}
    for _, d in ipairs(C.DEVICES) do self.dmg[d.key] = 0 end

    -- Quadrants: stars, black holes, inhabited systems
    self.quads = {}
    for i = 1, NQ * NQ do
        local stars = rng:int(9) + 1
        self.quads[i] = { k = 0, b = 0, s = stars, h = math.max(0, rng:int(3) - floor(stars / 5)) }
    end
    for _, name in ipairs(C.SYSTEMS) do
        local q
        repeat q = self.quads[rng:int(NQ * NQ) + 1] until not q.sys
        q.sys = name
    end

    -- Starbases, one per quadrant
    self.bases = {}
    for i = 1, p.bases do
        local x, y, q
        repeat
            x, y = rng:int(NQ), rng:int(NQ)
            q = self:quad(x, y)
        until q.b == 0
        q.b = 1
        self.bases[i] = { x = x, y = y }
    end

    -- The ship starts in the first starbase's quadrant
    local home = self.bases[1]
    self.ship = {
        name = "Enterprise", kind = C.SHIP, hasCloak = true,
        qx = home.x, qy = home.y, x = rng:int(NS), y = rng:int(NS),
        energy = p.energy, shield = p.shield, up = true, torps = p.torps,
        crew = p.crew, brig = 0, reserves = p.reserves,
        warp = 5, cloaked = false, cloakGood = false, docked = false, heading = 0,
    }

    -- Klingons, in groups of 1 to 4, never in the starting quadrant
    local left = p.klings
    while left > 0 do
        local klump = math.min(rng:int(4) + 1, left)
        local x, y = rng:int(NQ), rng:int(NQ)
        local q = self:quad(x, y)
        if q.k + klump <= C.MAXKLQUAD and not (x == home.x and y == home.y) then
            q.k = q.k + klump
            left = left - klump
        end
    end

    self.events = {}
    for _, kind in ipairs({ "snova", "tractor", "katsb", "enslave" }) do
        self:schedule(kind, rng:expo(C.EVENT_MEAN[kind]))
    end

    for _, b in ipairs(self.bases) do self:remember(b.x, b.y) end
    self:initQuad()
    self:lrscan()

    self:say("Comms", ("Stardate %.1f. Starfleet orders: destroy %d Klingons in %d days."):format(
        self.date, p.klings, p.time))
    self:say("Comms", ("%d starbase%s can resupply and repair the %s."):format(
        p.bases, p.bases == 1 and "" or "s", self.ship.name))
    return self
end

-- Fill the sector grid for the ship's quadrant. Klingons start with full
-- power each time the ship arrives, as in BSD trek.
function Game:initQuad()
    local s = self.ship
    local q = self:quad(s.qx, s.qy)
    self.sect = {}
    for i = 1, NS * NS do self.sect[i] = C.EMPTY end
    self:put(s.x, s.y, s.kind)
    self.kl = {}
    for i = 1, q.k do
        local x, y = self:emptySector(3)
        self:put(x, y, C.KLINGON)
        self.kl[i] = { x = x, y = y, power = self.p.klingpwr }
    end
    local function place(what, away)
        local x, y = self:emptySector(away)
        self:put(x, y, what)
    end
    if q.b > 0 then place(C.BASE, 2) end
    if q.sys then place(C.INHABIT, 1) end
    for _ = 1, q.s do place(C.STAR, 1) end
    for _ = 1, q.h do place(C.HOLE, 2) end
    self:remember(s.qx, s.qy)
end

-- A random empty sector, `away` sectors or more from the ship if possible.
function Game:emptySector(away)
    local rng = self.rng
    for try = 1, 300 do
        local x, y = rng:int(NS), rng:int(NS)
        if self:at(x, y) == C.EMPTY and (try > 100 or self:dist(x, y) >= (away or 0)) then
            return x, y
        end
    end
    for i = 1, NS * NS do
        if self.sect[i] == C.EMPTY then return (i - 1) % NS, floor((i - 1) / NS) end
    end
    return 0, 0
end

-- Grid and quadrant access ------------------------------------------------------

function Game:quad(x, y)
    if x < 0 or y < 0 or x >= NQ or y >= NQ then return nil end
    return self.quads[y * NQ + x + 1]
end

function Game:here()
    return self:quad(self.ship.qx, self.ship.qy)
end

function Game:at(x, y)
    if x < 0 or y < 0 or x >= NS or y >= NS then return nil end
    return self.sect[y * NS + x + 1]
end

function Game:put(x, y, v)
    self.sect[y * NS + x + 1] = v
end

-- Change a sector and tell the screen.
function Game:set(x, y, v)
    self:put(x, y, v)
    self:fx("set", { x = x, y = y, v = v })
end

-- Distance in sectors from (x, y) to the ship, or to (x2, y2).
function Game:dist(x, y, x2, y2)
    x2, y2 = x2 or self.ship.x, y2 or self.ship.y
    return sqrt((x - x2) ^ 2 + (y - y2) ^ 2)
end

function Game:klingonAt(x, y)
    for i, k in ipairs(self.kl) do
        if k.x == x and k.y == y then return k, i end
    end
end

function Game:damaged(key)
    return (self.dmg[key] or 0) > 0
end

function Game:radioOK()
    return not self:damaged("radio")
end

-- Short-range scanners see the whole quadrant; when damaged, only the
-- sectors next to the ship.
function Game:visible(x, y)
    return not self:damaged("srscan") or self:dist(x, y) < 1.5
end

function Game:condition()
    local s = self.ship
    if s.docked then return "docked" end
    if #self.kl > 0 then return "red" end
    if s.energy < 1000 then return "yellow" end
    return "green"
end

-- Long-range scan: record the quadrants around the ship on the star chart.
function Game:lrscan()
    local s = self.ship
    if self:damaged("lrscan") then
        self:remember(s.qx, s.qy)
        return
    end
    for dy = -1, 1 do
        for dx = -1, 1 do
            if self:quad(s.qx + dx, s.qy + dy) then self:remember(s.qx + dx, s.qy + dy) end
        end
    end
end

function Game:remember(x, y)
    local q = self:quad(x, y)
    q.known = { k = q.k, b = q.b, s = q.s, sys = q.sys, nova = q.nova, d = self.date }
end

-- What the star chart knows about a quadrant: live for the ship's own
-- quadrant, the last scan for others, nil if never scanned.
function Game:chartInfo(x, y)
    local q = self:quad(x, y)
    if not q then return nil end
    if x == self.ship.qx and y == self.ship.qy then
        return { k = q.k, b = q.b, s = q.s, sys = q.sys, nova = q.nova, d = self.date, live = true }
    end
    return q.known
end

-- Distress calls the ship has heard and that are still going on.
function Game:distressCalls()
    local list = {}
    for y = 0, NQ - 1 do
        for x = 0, NQ - 1 do
            local q = self:quad(x, y)
            if q.distress and (q.attacked or q.enslaved) then
                list[#list + 1] = {
                    x = x, y = y, kind = q.attacked and "base" or "planet",
                    sys = q.sys, until_ = q.attacked,
                }
            end
        end
    end
    return list
end

function Game:nearestBase()
    local s = self.ship
    local best, bd
    for _, b in ipairs(self.bases) do
        local d = sqrt((b.x - s.qx) ^ 2 + (b.y - s.qy) ^ 2)
        if not bd or d < bd then best, bd = b, d end
    end
    return best, bd
end

function Game:adjacentBase()
    local s = self.ship
    for dy = -1, 1 do
        for dx = -1, 1 do
            if self:at(s.x + dx, s.y + dy) == C.BASE then return s.x + dx, s.y + dy end
        end
    end
end

-- Days until every device is repaired, at the current repair rate.
function Game:repairTime()
    local most = 0
    for _, d in ipairs(C.DEVICES) do most = math.max(most, self.dmg[d.key]) end
    return most / (self.ship.docked and 2 or 1)
end

-- Output for the screen ---------------------------------------------------------

function Game:fx(kind, data)
    data = data or {}
    data.kind = kind
    self.out[#self.out + 1] = data
    return data
end

-- Add a line to the log. who is the crew station speaking; tone is one of
-- info, good, warn, bad, alert.
function Game:say(who, text, tone)
    self.logN = self.logN + 1
    local log = self.log
    log[#log + 1] = { n = self.logN, d = self.date, who = who, text = text, tone = tone or "info" }
    if #log > LOG_KEEP then table.remove(log, 1) end
    self:fx("msg", { n = self.logN })
end

-- Say why a command can't be done. Returns false so commands can
-- `return self:refuse(...)`.
function Game:refuse(who, text)
    self:say(who, text, "warn")
    self:fx("sound", { name = "error" })
    return false
end

-- Hand the queued output to the screen.
function Game:takeOutput()
    local out = self.out
    self.out = {}
    return out
end

function Game:shipStats()
    local s = self.ship
    return {
        energy = floor(s.energy), shield = floor(s.shield), up = s.up, torps = s.torps,
        docked = s.docked, cloaked = s.cloaked, date = self.date, time = self.time,
        klings = self.klings, cond = self:condition(), crew = s.crew,
    }
end

-- The sector grid and ship as they are now, for the screen to draw from.
function Game:snapshot()
    local grid = {}
    for i = 1, NS * NS do grid[i] = self.sect[i] end
    local s = self.ship
    return {
        grid = grid, qx = s.qx, qy = s.qy, x = s.x, y = s.y,
        heading = s.heading, kind = s.kind, stats = self:shipStats(),
    }
end

-- Time --------------------------------------------------------------------------

-- BSD trek's clock: the Federation has a pool of resources that the
-- remaining Klingons drain, so time left = resources / Klingons. Every
-- Klingon destroyed buys more time; every new one costs some.
function Game:updateTime()
    if self.klings > 0 then self.time = self.resource / self.klings end
end

-- Let dt days pass with no events: repairs, recharging, life support.
function Game:passTime(dt)
    if dt <= 0 or self.over then return end
    local s, p = self.ship, self.p
    self.date = self.date + dt
    self.resource = self.resource - self.klings * dt
    self:updateTime()

    local rate = s.docked and 2 or 1
    for _, d in ipairs(C.DEVICES) do
        local left = self.dmg[d.key]
        if left > 0 then
            left = left - dt * rate
            if left <= 0 then
                left = 0
                self:say("Engineering", d.name .. " repaired.", "good")
            end
            self.dmg[d.key] = left
        end
    end

    if not s.docked and p.regen > 0 then
        local f = 1 - math.exp(-p.regen * dt)
        if s.energy < p.energy then s.energy = s.energy + (p.energy - s.energy) * f end
        if s.shield < p.shield then s.shield = s.shield + (p.shield - s.shield) * f end
    end
    if s.cloaked then s.energy = s.energy - 1000 * dt end

    if self:damaged("lifesup") and not s.docked then
        s.reserves = s.reserves - dt
        if s.reserves <= 0 then return self:lose("nolife") end
    end
    if self.time <= 0 then return self:lose("time") end
    if s.energy <= 0 then return self:lose("energy") end
end

-- Let dt days pass, handling events as their time comes. With
-- `interruptible`, stop early after an event that needs the captain.
function Game:advance(dt, interruptible)
    local target = self.date + dt
    while not self.over do
        local e, i = self:nextEvent()
        if e and e.date <= target then
            self:passTime(e.date - self.date)
            if self.over then return end
            table.remove(self.events, i)
            self:handleEvent(e)
            if interruptible and self.interrupt then return end
        else
            self:passTime(target - self.date)
            return
        end
    end
end

-- After a command: time passes, then any Klingons here open fire.
function Game:endTurn(dt)
    if self.over then return end
    self.interrupt = false
    if dt and dt > 0 then self:advance(dt) end
    if self.over then return end
    self:klingonsAttack()
    self.shieldChange = false
    local s = self.ship
    if s.cloaked then s.cloakGood = true end
    if not self.over and s.energy <= 0 then self:lose("energy") end
end

-- Winning and losing -----------------------------------------------------------

function Game:win()
    if self.over then return end
    self.over = { won = true, reason = "won", text = "The last Klingon is gone. The Federation is saved!" }
    self:say("Comms", "Starfleet Command: congratulations, Captain. The Federation is safe.", "good")
    self:fx("over")
end

function Game:lose(reason, text)
    if self.over then return end
    self.over = { won = false, reason = reason, text = text or C.LOSS[reason] or "The mission failed." }
    self:say("Computer", self.over.text, "bad")
    self:fx("over")
end

-- Score, as in BSD score.c. Returns the total and a list of rows.
function Game:score()
    local st, p = self.stats, self.p
    local rows, total = {}, 0
    local function add(label, count, each, points)
        points = points or floor(count * each)
        if points ~= 0 then
            rows[#rows + 1] = { label = label, count = count, points = points }
            total = total + points
        end
    end
    local per = floor(p.klingpwr / 4)
    add("Klingons destroyed", st.killed, per)
    add("Klingons captured", st.captured, per)
    add("Captives taken", st.captives, 1)
    local kills = st.killed + st.captured
    local days = math.max(1, self.date - self.start)
    if kills > 0 then add("Kill rate", nil, nil, floor(400 * kills / days)) end
    add("Starbases you destroyed", st.basesKilled, -400)
    add("Starbases lost", st.basesLost, -100)
    add("Calls for help", st.helps, -100)
    add("Stars destroyed", st.stars, -5)
    add("Inhabited systems destroyed", st.inhab, -150)
    add("Casualties", st.deaths, -1)
    if st.shipLost then add("Enterprise abandoned", 1, -200) end
    if self.over and self.over.won then add("Victory bonus", nil, nil, 100 * self.skill * self.length) end
    return total, rows
end

-- Saving --------------------------------------------------------------------------

function Game:serialize()
    local t = {}
    for k, v in pairs(self) do
        if k ~= "out" and k ~= "rng" then t[k] = v end
    end
    t.rng = self.rng.s
    return t
end

function Game.deserialize(t)
    if type(t) ~= "table" or t.v ~= Game.SAVE_VERSION or type(t.ship) ~= "table"
        or type(t.quads) ~= "table" or type(t.sect) ~= "table" then
        return nil
    end
    local self = setmetatable(t, Game)
    self.rng = Rng.new(t.rng)
    self.out = {}
    return self
end

require("src.trek.combat")(Game)
require("src.trek.events")(Game)
require("src.trek.commands")(Game)

return Game
