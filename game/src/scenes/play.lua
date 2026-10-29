-- The bridge: the short-range scan of the current quadrant on the left, the
-- ship's status and the crew's log on the right.
--
-- Commands change the game straight away; this screen then plays back the
-- stream of messages and effects they produced (game.out), updating its
-- own copy of the sector grid (self.view) as it goes, so the picture always
-- matches the animation.

local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")
local sprites = require("src.sprites")
local starfield = require("src.starfield")
local C = require("src.trek.const")
local Game = require("src.trek.game")

local Play = {}
Play.__index = Play

local NS = C.NSECTS
local CELL, GX, GY = 38, 40, 40       -- sector grid
local GW = CELL * NS                  -- 380
local PX, PW = 440, 264               -- right panel
local PR = PX + PW

Play.CELL, Play.GX, Play.GY, Play.PX, Play.PW = CELL, GX, GY, PX, PW

local ICON = {
    [C.SHIP] = "ship", [C.QUEENE] = "queene", [C.KLINGON] = "klingon", [C.BASE] = "base",
    [C.STAR] = "star", [C.INHABIT] = "planet", [C.HOLE] = "hole",
}
local CLASSIC = {
    [C.SHIP] = "ship", [C.QUEENE] = "ship", [C.KLINGON] = "klingon", [C.BASE] = "base",
    [C.STAR] = "star", [C.INHABIT] = "planet", [C.EMPTY] = "dot",
}
local ROLE = {
    Helm = "helm", Tactical = "tactical", Science = "science", Comms = "comms",
    Engineering = "engineering", Medical = "medical", Computer = "computer",
}
local TONE = { info = "text", good = "good", warn = "warn", bad = "bad", alert = "bad" }
local SHORT = {
    warp = "Warp", srscan = "SR scan", lrscan = "LR scan", phaser = "Phasers", torped = "Torpedoes",
    impulse = "Impulse", shield = "Shields", computer = "Computer", radio = "Radio",
    lifesup = "Life support", sins = "Navigation", cloak = "Cloak", xporter = "Transporter",
}
local CONDITION = {
    green = { "GREEN", "good" }, yellow = { "YELLOW", "warn" },
    red = { "RED ALERT", "bad" }, docked = { "DOCKED", "info" },
}

-- How long each kind of event holds up the stream, in seconds.
local DUR = {
    msg = 0.05, phaser = 0.42, kfire = 0.34, kmove = 0.2, enter = 0.9,
    shields = 0.2, dock = 0.35, cloak = 0.35, beam = 0.5, turn = 0.12,
    over = 0.5, nova = 0.4, supernova = 0.8, boom = 0.12,
}

local function cx(x) return GX + x * CELL + CELL / 2 end
local function cy(y) return GY + y * CELL + CELL / 2 end
Play.cellCenter = function(x, y) return cx(x), cy(y) end

function Play.new(app)
    local self = setmetatable({ app = app, t = 0, effects = {}, shake = 0, contentAlpha = 1 }, Play)
    local g = app.game
    self.view = g:snapshot()
    self.revealed = g.logN
    self.turnStart = math.max(0, g.logN - 2)
    self.cursor = { x = self.view.x, y = self.view.y }
    self:autoTarget()
    return self
end

function Play:enter()
    if self.app.game.over then self.endDelay = 0.3 end
end

function Play:at(x, y)
    return self.view.grid[y * NS + x + 1]
end

function Play:setCell(x, y, v)
    self.view.grid[y * NS + x + 1] = v
end

-- Cursor and targets ------------------------------------------------------------------

-- Things worth pointing at, nearest first: Klingons, then the starbase and
-- other notable objects.
function Play:targets()
    local list = {}
    local v = self.view
    for y = 0, NS - 1 do
        for x = 0, NS - 1 do
            local obj = self:at(x, y)
            local rank = (obj == C.KLINGON and 1) or (obj == C.BASE and 2) or (obj == C.INHABIT and 3)
                or (obj == C.HOLE and 4)
            if rank and self:visible(x, y) then
                list[#list + 1] = { x = x, y = y, rank = rank, d = (x - v.x) ^ 2 + (y - v.y) ^ 2 }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.d < b.d
    end)
    return list
end

-- Point the cursor at the nearest Klingon, or at the ship.
function Play:autoTarget()
    local list = self:targets()
    if list[1] and list[1].rank == 1 then
        self.cursor.x, self.cursor.y = list[1].x, list[1].y
    else
        self.cursor.x, self.cursor.y = self.view.x, self.view.y
    end
end

function Play:cycleTarget(dir)
    local list = self:targets()
    if #list == 0 then return end
    local idx = 0
    for k, t in ipairs(list) do
        if t.x == self.cursor.x and t.y == self.cursor.y then idx = k end
    end
    idx = (idx - 1 + dir) % #list + 1
    if idx < 1 then idx = #list end
    self.cursor.x, self.cursor.y = list[idx].x, list[idx].y
    sound.play("move")
end

function Play:visible(x, y)
    local g = self.app.game
    if not g:damaged("srscan") then return true end
    return (x - self.view.x) ^ 2 + (y - self.view.y) ^ 2 < 2.3
end

-- Running commands ------------------------------------------------------------------

-- Run fn(game), then play back what it produced.
function Play:run(fn)
    if self.queue then self:skip() end
    local g = self.app.game
    self.turnStart = self.revealed
    self.startQ = self.view.qx * 8 + self.view.qy
    self.wasKlingon = self:at(self.cursor.x, self.cursor.y) == C.KLINGON
    fn(g)
    local out = g:takeOutput()
    self.app.saveGame()
    self.queue, self.qi = out, 0
    self:nextItem()
end

function Play:nextItem()
    while self.queue do
        self.qi = self.qi + 1
        local e = self.queue[self.qi]
        if not e then
            self:endStream()
            return
        end
        local dur = self:beginItem(e, false)
        if self.app.settings.speed == "fast" then dur = dur * 0.5 end
        if dur > 0 then
            self.cur, self.curT, self.curDur = e, 0, dur
            return
        end
        self:finishItem(e)
    end
end

-- Finish everything still queued at once.
function Play:skip()
    if self.cur then
        local e = self.cur
        self.cur = nil
        self:finishItem(e)
    end
    while self.queue do
        self.qi = self.qi + 1
        local e = self.queue[self.qi]
        if not e then
            self:endStream()
            return
        end
        self:beginItem(e, true)
        self:finishItem(e)
    end
end

function Play:endStream()
    local g = self.app.game
    self.queue, self.cur = nil, nil
    self.contentAlpha = 1
    self.view = g:snapshot()
    self.revealed = g.logN
    if self.view.qx * 8 + self.view.qy ~= self.startQ then
        self:autoTarget()
    elseif self.wasKlingon and self:at(self.cursor.x, self.cursor.y) ~= C.KLINGON then
        self:autoTarget()
    end
    if g.over then self.endDelay = 1.1 end
    self.app.requestRedraw()
end

function Play:spawn(e)
    e.t = 0
    self.effects[#self.effects + 1] = e
    return e
end

-- Start an event. Returns how long it holds up the stream.
function Play:beginItem(e, quiet)
    local k = e.kind
    local v = self.view
    if e.stats and k ~= "kfire" then v.stats = e.stats end
    local function play(name, vol) if not quiet then sound.play(name, vol) end end
    if k == "msg" then
        self.revealed = e.n
        return DUR.msg
    elseif k == "set" then
        self:setCell(e.x, e.y, e.v)
        return 0
    elseif k == "move" then
        play(e.push and "hit" or "impulse")
        e.fromHeading = v.heading
        local d = math.sqrt((e.tx - e.x) ^ 2 + (e.ty - e.y) ^ 2)
        return math.min(0.75, 0.2 + 0.055 * d)
    elseif k == "kmove" then
        return DUR.kmove
    elseif k == "enter" then
        play(e.beam and "beam" or "warp")
        return DUR.enter
    elseif k == "turn" then
        v.heading = e.heading
        return DUR.turn
    elseif k == "phaser" then
        play("phaser")
        return DUR.phaser
    elseif k == "torpedo" then
        play("torpedo")
        v.heading = e.heading
        local d = math.sqrt((e.tx - v.x) ^ 2 + (e.ty - v.y) ^ 2)
        return 0.1 + 0.05 * d
    elseif k == "kfire" then
        play("kfire")
        return DUR.kfire
    elseif k == "boom" then
        if not quiet then
            play(e.size >= 2 and "boom" or (e.size == 0 and "small" or "boom"), e.size == 0 and 0.7 or 1)
            local parts = {}
            local n = 10 + e.size * 8
            for i = 1, n do
                local a = (i / n) * math.pi * 2 + math.random() * 0.5
                parts[i] = { a = a, sp = 18 + math.random() * (30 + e.size * 30) }
            end
            self:spawn({ kind = "boom", x = e.x, y = e.y, size = e.size, parts = parts, dur = 0.7 + e.size * 0.25 })
            if e.size >= 2 then self.shake = math.max(self.shake, 6) end
        end
        return DUR.boom
    elseif k == "nova" then
        play("nova")
        if not quiet then
            self:spawn({ kind = "ring", x = e.x, y = e.y, slot = "star", r1 = CELL * 1.9, dur = 0.8 })
            self:spawn({ kind = "glow", x = e.x, y = e.y, slot = "star", dur = 0.6 })
            self.shake = math.max(self.shake, 4)
        end
        return DUR.nova
    elseif k == "supernova" then
        play("nova")
        if not quiet then
            self:spawn({ kind = "flash", dur = 1.2 })
            self.shake = math.max(self.shake, 10)
        end
        return DUR.supernova
    elseif k == "shake" then
        if not quiet then self.shake = math.max(self.shake, e.amount or 4) end
        return 0
    elseif k == "shields" then
        play(e.up and "shieldsUp" or "shieldsDown", 0.8)
        if not quiet then self:spawn({ kind = "bubble", up = e.up, dur = 0.45 }) end
        return DUR.shields
    elseif k == "dock" then
        play("dock")
        return DUR.dock
    elseif k == "cloak" then
        play("cloak")
        return DUR.cloak
    elseif k == "beam" then
        play("beam")
        if not quiet then self:spawn({ kind = "sparkle", x = e.x, y = e.y, dur = 0.8 }) end
        return DUR.beam
    elseif k == "sound" then
        play(e.name)
        return 0
    elseif k == "sync" then
        if e.snap then self.view = e.snap end
        return 0
    elseif k == "over" then
        return DUR.over
    end
    return 0
end

function Play:finishItem(e)
    local k = e.kind
    local v = self.view
    if k == "move" then
        if self:at(e.x, e.y) == v.kind then self:setCell(e.x, e.y, C.EMPTY) end
        self:setCell(e.tx, e.ty, v.kind)
        v.x, v.y, v.heading = e.tx, e.ty, e.heading
    elseif k == "kmove" then
        self:setCell(e.x, e.y, C.EMPTY)
        if not e.leave then self:setCell(e.tx, e.ty, C.KLINGON) end
        if self.cursor.x == e.x and self.cursor.y == e.y and not e.leave then
            self.cursor.x, self.cursor.y = e.tx, e.ty
        end
    elseif k == "enter" then
        if not e.swapped then self.view = e.snap end
        self.contentAlpha = 1
        self.cursor.x, self.cursor.y = self.view.x, self.view.y
    elseif k == "phaser" then
        self:spawn({ kind = "number", x = e.x, y = e.y, text = "-" .. e.hit, slot = "phaser", dur = 0.9 })
    elseif k == "kfire" then
        v.stats = e.stats
        if e.eff > 0 then
            sound.play("hit", 0.8)
            self.shake = math.max(self.shake, math.min(8, 2 + e.eff / 60))
            self:spawn({ kind = "number", x = v.x, y = v.y, text = "-" .. e.eff, slot = "bad", dur = 0.9 })
        end
        if e.hit > e.eff then self:spawn({ kind = "bubble", up = true, dur = 0.35 }) end
    end
end

-- Update ------------------------------------------------------------------------------

function Play:update(dt)
    self.t = self.t + dt
    for i = #self.effects, 1, -1 do
        local e = self.effects[i]
        e.t = e.t + dt
        if e.t >= e.dur then table.remove(self.effects, i) end
    end
    if self.shake > 0 then self.shake = math.max(0, self.shake - dt * 28) end

    if self.cur then
        self.curT = self.curT + dt
        local e = self.cur
        if e.kind == "enter" then
            local p = self.curT / self.curDur
            if not e.swapped and p >= 0.45 then
                e.swapped = true
                self.view = e.snap
            end
            self.contentAlpha = p < 0.45 and (1 - p / 0.45) or ((p - 0.45) / 0.55)
        end
        if self.curT >= self.curDur then
            self.cur = nil
            self:finishItem(e)
            self:nextItem()
        end
    end

    if self.endDelay and not self.queue then
        self.endDelay = self.endDelay - dt
        if self.endDelay <= 0 then
            self.endDelay = nil
            self.app.push("gameover")
        end
    end
end

function Play:busy()
    return self.queue ~= nil or #self.effects > 0 or self.shake > 0 or self.endDelay ~= nil
end

-- Input ----------------------------------------------------------------------------------

function Play:action(a)
    if self.queue then
        if a == "a" or a == "b" or a == "start" or a == "x" or a == "y" then self:skip() end
        return
    end
    local g = self.app.game
    if g.over or self.endDelay then return end
    local c = self.cursor
    local function moveCursor(dx, dy)
        local nx = math.max(0, math.min(NS - 1, c.x + dx))
        local ny = math.max(0, math.min(NS - 1, c.y + dy))
        if nx ~= c.x or ny ~= c.y then
            c.x, c.y = nx, ny
            sound.play("move")
        end
    end
    if a == "up" then moveCursor(0, -1)
    elseif a == "down" then moveCursor(0, 1)
    elseif a == "left" then moveCursor(-1, 0)
    elseif a == "right" then moveCursor(1, 0)
    elseif a == "a" then
        sound.play("open")
        self.app.push("orders")
    elseif a == "b" then
        if c.x ~= self.view.x or c.y ~= self.view.y then
            c.x, c.y = self.view.x, self.view.y
            sound.play("move")
        end
    elseif a == "x" then
        local why = g:phaserCheck()
        if why then
            self:run(function(game) game:refuse("Tactical", why) end)
        else
            sound.play("open")
            self.app.push("phasers")
        end
    elseif a == "y" then
        self:fireTorpedo()
    elseif a == "r1" then
        self:cycleTarget(1)
    elseif a == "l1" then
        self:cycleTarget(-1)
    elseif a == "select" then
        sound.play("open")
        self.app.push("chart")
    elseif a == "start" or a == "menu" then
        sound.play("open")
        self.app.push("shipmenu")
    end
end

-- Fire a torpedo at the cursor, checking first if that would hit a friend.
function Play:fireTorpedo()
    local c = self.cursor
    local obj = self:visible(c.x, c.y) and self:at(c.x, c.y)
    local function fire()
        self:run(function(g) g:cmdTorpedo(c.x, c.y) end)
    end
    if obj == C.BASE or obj == C.INHABIT then
        self.app.push("confirm", {
            title = obj == C.BASE and "Fire on the starbase?" or "Fire on the planet?",
            body = obj == C.BASE and "A torpedo would destroy it, and Starfleet takes a dim view of that."
                or "A torpedo would destroy an inhabited system.",
            yes = "Fire",
            onYes = fire,
        })
    else
        fire()
    end
end

-- Drawing ---------------------------------------------------------------------------------

function Play:shakeOffset()
    if self.shake <= 0 then return 0, 0 end
    local a = self.shake
    return math.floor((math.random() * 2 - 1) * a + 0.5), math.floor((math.random() * 2 - 1) * a + 0.5)
end

-- Where the ship is drawn right now, and which way it faces.
function Play:shipPose()
    local v = self.view
    local e = self.cur
    if e and e.kind == "move" then
        local p = ui.ease(self.curT / self.curDur)
        local turn = math.min(1, self.curT / (self.curDur * 0.3))
        local h0, h1 = e.fromHeading or e.heading, e.heading
        local dh = ((h1 - h0 + 540) % 360) - 180
        return e.x + (e.tx - e.x) * p, e.y + (e.ty - e.y) * p, h0 + dh * turn, e.x, e.y
    end
    return v.x, v.y, v.heading
end

function Play:drawObject(obj, x, y, px, py, rot, alpha, moving)
    local classic = self.app.settings.display == "classic"
    if classic then
        if obj == C.HOLE then return end -- BSD trek showed black holes as a blank
        local slot = CLASSIC[obj] or "text"
        theme.set(slot, alpha)
        ui.centered(obj, px, py, 22, "pixel", "center")
        return
    end
    if obj == C.EMPTY then
        theme.set("dot", alpha)
        ui.rect("fill", px - 1, py - 1, 2, 2)
        return
    end
    local icon = ICON[obj]
    if icon then sprites.draw(icon, px, py, CELL, rot or 0, alpha, nil, moving) end
end

function Play:drawGrid()
    local g = self.app.game
    local v = self.view
    local c = self.cursor

    theme.set("panel", 0.6)
    ui.rect("fill", GX, GY, GW, GW)
    theme.set("grid")
    for i = 1, NS - 1 do
        ui.rect("fill", GX + i * CELL, GY + 1, 1, GW - 1)
        ui.rect("fill", GX + 1, GY + i * CELL, GW - 1, 1)
    end
    theme.set("line")
    ui.rect("line", GX, GY, GW + 1, GW + 1)

    -- axis labels: columns are x, rows are y
    for i = 0, NS - 1 do
        theme.set(i == c.x and "accent" or "dim")
        ui.centered(tostring(i), cx(i), GY - 13, 11, "pixel", "center")
        theme.set(i == c.y and "accent" or "dim")
        ui.centered(tostring(i), GX - 13, cy(i), 11, "pixel", "center")
    end

    local alpha = self.contentAlpha
    local e = self.cur
    local shipX, shipY, shipRot, fromX, fromY = self:shipPose()
    local moving = e and e.kind == "kmove" and e
    for y = 0, NS - 1 do
        for x = 0, NS - 1 do
            local obj = self:at(x, y)
            local isShip = obj == v.kind or (fromX and x == fromX and y == fromY)
            if isShip then
                -- drawn below, possibly in motion
            elseif not self:visible(x, y) then
                theme.set("dot", alpha * 0.35)
                ui.rect("fill", cx(x) - 1, cy(y) - 1, 2, 2)
            elseif not (moving and moving.x == x and moving.y == y) then
                local rot = 0
                if obj == C.KLINGON then rot = Game.course(v.x - x, v.y - y) end
                self:drawObject(obj, x, y, cx(x), cy(y), rot, alpha)
                if obj == C.KLINGON and self.app.settings.display ~= "classic" then
                    local k = g:klingonAt(x, y)
                    if k and not g:damaged("srscan") then
                        local frac = math.max(0, k.power / g.p.klingpwr)
                        local bx, by = GX + x * CELL + 8, GY + y * CELL + CELL - 5
                        theme.set("raised", alpha)
                        ui.rect("fill", bx, by, 22, 2)
                        theme.set("klingon", alpha)
                        ui.rect("fill", bx, by, math.max(1, math.floor(22 * frac + 0.5)), 2)
                    end
                end
            end
        end
    end

    if moving then
        local p = ui.ease(self.curT / self.curDur)
        local mx, my = moving.x + (moving.tx - moving.x) * p, moving.y + (moving.ty - moving.y) * p
        local a = moving.leave and (1 - p) or 1
        self:drawObject(C.KLINGON, mx, my, GX + mx * CELL + CELL / 2, GY + my * CELL + CELL / 2,
            Game.course(v.x - mx, v.y - my), alpha * a, true)
    end

    -- the ship, possibly in motion
    local px, py = GX + shipX * CELL + CELL / 2, GY + shipY * CELL + CELL / 2
    if fromX or self:at(v.x, v.y) == v.kind then -- gone after self-destruct
        local cloaked = v.stats.cloaked
        if self.app.settings.display == "classic" then
            theme.set("ship", alpha * (cloaked and 0.4 or 1))
            ui.centered(v.kind, px, py, 22, "pixel", "center")
        else
            sprites.draw(v.kind == C.QUEENE and "queene" or "ship", px, py, CELL, shipRot,
                alpha * (cloaked and 0.35 or 1), nil, fromX ~= nil)
        end
    end

    -- cursor
    local bx, by = GX + c.x * CELL, GY + c.y * CELL
    theme.set("accent", 0.08)
    ui.rect("fill", bx + 1, by + 1, CELL - 1, CELL - 1)
    ui.brackets(bx - 1, by - 1, CELL + 3, CELL + 3, 9, 2, "accent")
end

-- Plotted courses and aim lines while a dialog is choosing an action.
local function dashed(x1, y1, x2, y2, dash, gap)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    local ux, uy = dx / len, dy / len
    local t = 0
    while t < len do
        local t2 = math.min(len, t + dash)
        love.graphics.line(x1 + ux * t, y1 + uy * t, x1 + ux * t2, y1 + uy * t2)
        t = t2 + gap
    end
end

function Play:drawPreview()
    local p = self.preview
    if not p or self.queue then return end
    local v = self.view
    local sx, sy = cx(v.x), cy(v.y)
    love.graphics.setLineWidth(1.5)
    if p.kind == "move" and p.route then
        theme.set("accent", 0.75)
        local x0, y0 = sx, sy
        local qx0, qy0 = v.qx * NS, v.qy * NS
        for _, wp in ipairs(p.route) do
            local lx, ly = wp[1] - qx0, wp[2] - qy0
            local x1, y1 = GX + lx * CELL + CELL / 2, GY + ly * CELL + CELL / 2
            local a, b, c2, d = starfield.clip(x0, y0, x1, y1, GX, GY, GW, GW)
            if a then dashed(a, b, c2, d, 6, 5) end
            x0, y0 = x1, y1
        end
    elseif p.kind == "torpedo" then
        local rad = math.rad(Game.course(p.x - v.x, p.y - v.y))
        local ux, uy = math.sin(rad), -math.cos(rad)
        local far = GW * 1.5
        local a, b, c2, d = starfield.clip(sx, sy, sx + ux * far, sy + uy * far, GX, GY, GW, GW)
        theme.set("torpedo", 0.8)
        if a then dashed(a, b, c2, d, 3, 4) end
        for _, side in ipairs({ -1, 1 }) do
            local r2 = rad + math.rad(p.spread * side)
            local a2, b2, c3, d3 = starfield.clip(sx, sy, sx + math.sin(r2) * far, sy - math.cos(r2) * far, GX, GY, GW, GW)
            theme.set("torpedo", 0.25)
            if a2 then love.graphics.line(a2, b2, c3, d3) end
        end
    elseif p.kind == "phaser" and p.plan then
        for _, e in ipairs(p.plan) do
            if e.units > 0 then
                local kx, ky = cx(e.k.x), cy(e.k.y)
                theme.set("phaser", 0.55)
                dashed(sx, sy, kx, ky, 4, 4)
                local sure = e.units >= e.need
                theme.set(sure and "good" or "phaser")
                ui.centered(sure and "×" or ("-" .. math.floor(e.units * 0.9 ^ math.sqrt((e.k.x - v.x) ^ 2 + (e.k.y - v.y) ^ 2))),
                    kx, ky - 24, 11, "pixel", "center")
            end
        end
    end
end

function Play:drawEffects()
    local v = self.view
    local e = self.cur
    local sx, sy = cx(v.x), cy(v.y)
    if e and e.kind == "phaser" then
        local p = self.curT / self.curDur
        local reach = math.min(1, p / 0.25)
        local fade = p > 0.7 and (1 - (p - 0.7) / 0.3) or 1
        local tx, ty = cx(e.x), cy(e.y)
        local ex, ey = sx + (tx - sx) * reach, sy + (ty - sy) * reach
        local flicker = 0.75 + 0.25 * math.sin(self.t * 70)
        love.graphics.setLineWidth(6)
        theme.set("phaser", 0.22 * fade)
        love.graphics.line(sx, sy, ex, ey)
        love.graphics.setLineWidth(2)
        theme.set("phaser", fade * flicker)
        love.graphics.line(sx, sy, ex, ey)
        if reach >= 1 then ui.disc(tx, ty, 10, "phaser", 0.7 * fade) end
    elseif e and e.kind == "kfire" then
        local p = self.curT / self.curDur
        local kx, ky = cx(e.x), cy(e.y)
        local reach = math.min(1, p / 0.3)
        local fade = p > 0.65 and (1 - (p - 0.65) / 0.35) or 1
        local ex, ey = kx + (sx - kx) * reach, ky + (sy - ky) * reach
        love.graphics.setLineWidth(5)
        theme.set("kfire", 0.2 * fade)
        love.graphics.line(kx, ky, ex, ey)
        love.graphics.setLineWidth(1.5)
        theme.set("kfire", fade)
        love.graphics.line(kx, ky, ex, ey)
    elseif e and e.kind == "torpedo" then
        local p = math.min(1, self.curT / self.curDur)
        local tx, ty = GX + e.tx * CELL + CELL / 2, GY + e.ty * CELL + CELL / 2
        local hx, hy = sx + (tx - sx) * p, sy + (ty - sy) * p
        local tail = math.max(0, p - 0.25)
        local lx, ly = sx + (tx - sx) * tail, sy + (ty - sy) * tail
        love.graphics.setLineWidth(2)
        theme.set("torpedo", 0.35)
        love.graphics.line(lx, ly, hx, hy)
        ui.disc(hx, hy, 9, "torpedo", 0.45)
        ui.disc(hx, hy, 5, "text")
    elseif e and e.kind == "enter" then
        local p = self.curT / self.curDur
        local k = 1 - math.abs(p - 0.45) / 0.55
        if e.beam then
            for i = 1, 6 do
                local off = (i - 3.5) * 5
                theme.set("info", 0.5 * k)
                ui.rect("fill", sx + off, sy - 16 + ((self.t * 60 + i * 7) % 32), 1, 2)
            end
        else
            starfield.streaks(GX + 1, GY + 1, GW - 1, GW - 1, e.heading, k, self.t)
        end
    end

    for _, f in ipairs(self.effects) do
        local p = f.t / f.dur
        if f.kind == "boom" then
            local x, y = cx(f.x), cy(f.y)
            local q = ui.ease(p)
            if p < 0.25 then ui.disc(x, y, (16 + f.size * 14) * (0.6 + p * 2), "torpedo", 1 - p * 3) end
            love.graphics.setLineWidth(2)
            theme.set("torpedo", (1 - p) * 0.8)
            love.graphics.circle("line", x, y, 6 + q * (16 + f.size * 18))
            for _, part in ipairs(f.parts) do
                local d = part.sp * q
                theme.set(p < 0.4 and "text" or "torpedo", 1 - p)
                ui.rect("fill", x + math.cos(part.a) * d - 1, y + math.sin(part.a) * d - 1, 2, 2)
            end
        elseif f.kind == "ring" then
            local q = ui.ease(p)
            love.graphics.setLineWidth(3 * (1 - p) + 1)
            theme.set(f.slot, 1 - p)
            love.graphics.circle("line", cx(f.x), cy(f.y), 4 + q * f.r1)
        elseif f.kind == "glow" then
            ui.disc(cx(f.x), cy(f.y), 30 + p * 40, f.slot, (1 - p) * 0.6)
        elseif f.kind == "flash" then
            theme.set("text", (1 - p) * 0.85)
            ui.rect("fill", GX + 1, GY + 1, GW - 1, GW - 1)
        elseif f.kind == "number" then
            local q = ui.ease(p)
            theme.set(f.slot, p > 0.6 and (1 - (p - 0.6) / 0.4) or 1)
            ui.centered(f.text, cx(f.x), cy(f.y) - 22 - q * 14, 15, "bold", "center")
        elseif f.kind == "bubble" then
            local x, y = self:shipPose()
            local r = CELL * 0.62 + (f.up and (1 - p) * 4 or p * 6)
            love.graphics.setLineWidth(2)
            theme.set("shield", (1 - p) * 0.9)
            love.graphics.circle("line", GX + x * CELL + CELL / 2, GY + y * CELL + CELL / 2, r)
        elseif f.kind == "sparkle" then
            for i = 1, 7 do
                local off = (i - 4) * 4
                theme.set("info", (1 - p))
                ui.rect("fill", cx(f.x) + off, cy(f.y) - 14 + ((f.t * 70 + i * 11) % 28), 1, 3)
            end
        end
    end
end

-- What's under the cursor, in one line below the grid.
function Play:drawReadout()
    local g = self.app.game
    local c = self.cursor
    local v = self.view
    local y = GY + GW + 18
    local where = c.x .. "," .. c.y
    local d = math.sqrt((c.x - v.x) ^ 2 + (c.y - v.y) ^ 2)
    local dist = d > 0 and ("  ·  %.1f sectors away"):format(d) or ""
    local obj = self:at(c.x, c.y)
    local name, slot, extra
    if c.x == v.x and c.y == v.y then
        name, slot = v.kind == C.QUEENE and "Faire Queene" or "Enterprise", "ship"
        extra = "  ·  you are here"
    elseif not self:visible(c.x, c.y) then
        name, slot, extra = "Sector " .. where, "muted", "  ·  beyond scanner range"
        where = ""
    elseif obj == C.KLINGON then
        local k = g:klingonAt(c.x, c.y)
        name, slot = "Klingon", "klingon"
        extra = k and ("  ·  power %d%%"):format(math.max(0, math.floor(k.power / g.p.klingpwr * 100 + 0.5))) or ""
    elseif obj == C.BASE then
        name, slot, extra = "Starbase", "base", g:adjacentBase() and "  ·  alongside, ready to dock" or ""
    elseif obj == C.STAR then
        name, slot = "Star", "star"
    elseif obj == C.INHABIT then
        name, slot = (g:here().sys or "Inhabited system"), "planet"
    elseif obj == C.HOLE then
        name, slot = "Black hole", "hole"
    else
        name, slot = "Empty sector", "muted"
    end
    theme.set(slot)
    local w = ui.centered(name, GX, y, 15, "bold", "left")
    theme.set("muted")
    ui.centered((where ~= "" and ("  " .. where) or "") .. (extra or "") .. dist, GX + w, y, 15, "regular", "left")
end

function Play:drawPanel()
    local g = self.app.game
    local v = self.view
    local st = v.stats
    local x, r = PX, PR

    -- name and condition
    theme.set("text")
    ui.centered(string.upper(v.kind == C.QUEENE and "Faire Queene" or "Enterprise"), x, 28, 22, "pixel", "left")
    local cond = CONDITION[st.cond] or CONDITION.green
    local blink = st.cond == "red" and self.queue and (math.floor(self.t * 4) % 2 == 0)
    local cw = math.floor(ui.width(cond[1], 13, "bold") + 16)
    theme.set(cond[2], blink and 0.55 or 1)
    ui.rect("fill", r - cw, 18, cw, 20)
    theme.set("bg")
    ui.centered(cond[1], r - cw / 2, 28, 13, "bold", "center")
    if st.cloaked then
        local w2 = math.floor(ui.width("CLOAKED", 13, "bold") + 16)
        theme.set("hole")
        ui.rect("line", r - cw - w2 - 6, 18, w2, 20)
        ui.centered("CLOAKED", r - cw - 6 - w2 / 2, 28, 13, "bold", "center")
    end
    theme.set("line")
    ui.rect("fill", x, 46, PW, 1)

    -- readouts, two columns
    local col2 = x + 136
    local function label(text, lx, ly)
        theme.set("dim")
        ui.centered(text, lx, ly, 12, "bold", "left")
    end
    local function value(text, lx, ly, slot)
        theme.set(slot or "text")
        return ui.centered(text, lx, ly, 22, "pixel", "left")
    end
    label("STARDATE", x, 62)
    value(ui.one(st.date), x, 82)
    label("TIME LEFT", col2, 62)
    local tw = value(ui.one(st.time), col2, 82, st.time < 2 and "bad" or (st.time < 4 and "warn" or "text"))
    theme.set("muted")
    ui.centered("days", col2 + tw + 6, 84, 14, "regular", "left")

    label("QUADRANT", x, 108)
    value(v.qx .. "," .. v.qy, x, 128)
    label("SECTOR", col2, 108)
    value(v.x .. "," .. v.y, col2, 128)

    label("KLINGONS LEFT", x, 154)
    value(tostring(st.klings), x, 174, "klingon")
    label("TORPEDOES", col2, 154)
    for i = 1, g.p.torps do
        theme.set(i <= st.torps and "torpedo" or "raised")
        ui.rect("fill", col2 + (i - 1) * 12, 168, 8, 12)
    end

    -- energy and shields
    local p = g.p
    label("ENERGY", x, 202)
    local eslot = st.energy > 2500 and "good" or (st.energy > 1000 and "warn" or "bad")
    theme.set(eslot)
    ui.centered(ui.number(st.energy), r, 200, 22, "pixel", "right")
    ui.bar(x, 214, PW, 5, st.energy / p.energy, eslot)

    label("SHIELDS", x, 236)
    local up = st.up
    theme.set(up and "shield" or "dim")
    ui.centered(up and "UP" or "DOWN", x + 66, 236, 12, "bold", "left")
    theme.set(up and "shield" or "muted")
    ui.centered(ui.number(st.shield), r, 234, 22, "pixel", "right")
    ui.bar(x, 248, PW, 5, st.shield / p.shield, up and "shield" or "dim")

    -- damaged systems
    local top = 266
    local damaged = {}
    for _, d in ipairs(C.DEVICES) do
        if g:damaged(d.key) then damaged[#damaged + 1] = SHORT[d.key] end
    end
    theme.set("line")
    ui.rect("fill", x, top, PW, 1)
    if #damaged > 0 then
        local text = "Damaged: " .. table.concat(damaged, ", ")
        local h = ui.wrap(text, 14, "regular", PW)
        theme.set("bad")
        ui.text(text, x, top + 7, 14, "regular", "left", PW)
        top = top + 10 + h
        theme.set("line")
        ui.rect("fill", x, top, PW, 1)
    end

    self:drawLog(x, top + 6, PW, GY + GW - top - 6)
end

-- The crew's log, newest at the bottom. This turn's lines are bright.
function Play:drawLog(x, y, w, h)
    local g = self.app.game
    local bottom = y + h
    local yy = bottom
    for i = #g.log, 1, -1 do
        local e = g.log[i]
        if e.n <= self.revealed then
            local old = e.n <= self.turnStart
            local text = e.who .. "  " .. e.text
            local hgt = ui.wrap(text, 15, "regular", w)
            yy = yy - hgt
            if yy < y then break end
            ui.colored({ ROLE[e.who] or "muted", e.who .. "  ", old and "muted" or (TONE[e.tone] or "text"), e.text },
                x, yy, 15, "regular", w, old and 0.6 or 1)
            yy = yy - 4
        end
    end
end

function Play:draw()
    starfield.draw(0.5)
    local ox, oy = self:shakeOffset()
    love.graphics.push()
    love.graphics.translate(ox, oy)
    self:drawGrid()
    self:drawPreview()
    self:drawEffects()
    love.graphics.pop()
    self:drawPanel()
    self:drawReadout()
    if self.app.top() == self then
        ui.hints({
            { "A", "Orders" }, { "X", "Phasers" }, { "Y", "Torpedo" },
            { "R1", "Target" }, { "Select", "Chart" }, { "Start", "Ship" },
        }, PR, 462, "right", 1, 14)
    end
end

return Play
