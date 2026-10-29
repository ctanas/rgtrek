-- The star chart: what the long-range scanners have seen of the galaxy, and
-- the helm. Pick a quadrant, set the warp factor, see the cost, engage.

local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")
local sprites = require("src.sprites")
local starfield = require("src.starfield")
local C = require("src.trek.const")

local Chart = {}
Chart.__index = Chart

local NQ, NS = C.NQUADS, C.NSECTS
local CELL, GX, GY = 46, 40, 40
local GW = CELL * NQ
local PX, PW = 432, 272

local function cx(x) return GX + x * CELL + CELL / 2 end
local function cy(y) return GY + y * CELL + CELL / 2 end

function Chart.new(app)
    local g = app.game
    local self = setmetatable({ app = app, t = 0 }, Chart)
    self.cursor = { x = g.ship.qx, y = g.ship.qy }
    self:refresh()
    return self
end

function Chart:refresh()
    local g = self.app.game
    local c = self.cursor
    local s = g.ship
    if c.x == s.qx and c.y == s.qy then
        self.plan = nil
    else
        self.plan = g:plan(c.x * NS + s.x, c.y * NS + s.y)
    end
end

function Chart:update(dt)
    self.t = self.t + dt
end

function Chart:busy()
    return self.t < 0.3
end

function Chart:action(a)
    local g = self.app.game
    local c = self.cursor
    local function move(dx, dy)
        local nx = math.max(0, math.min(NQ - 1, c.x + dx))
        local ny = math.max(0, math.min(NQ - 1, c.y + dy))
        if nx ~= c.x or ny ~= c.y then
            c.x, c.y = nx, ny
            sound.play("move")
            self:refresh()
        end
    end
    if a == "up" then move(0, -1)
    elseif a == "down" then move(0, 1)
    elseif a == "left" then move(-1, 0)
    elseif a == "right" then move(1, 0)
    elseif a == "l1" or a == "r1" then
        local w = g.ship.warp + (a == "r1" and 0.5 or -0.5)
        g:setWarp(w)
        if g.ship.warp == w then sound.play("menu") else sound.play("error") end
        self:refresh()
        self.app.saveGame()
    elseif a == "a" then
        if not self.plan then
            sound.play("error")
            return
        end
        if not self.plan.ok then
            sound.play("error")
            return
        end
        local tx, ty = c.x, c.y
        sound.play("open")
        self.app.pop()
        self.app.find("play"):run(function(game) game:cmdWarp(tx, ty) end)
    elseif a == "b" or a == "select" or a == "start" then
        sound.play("close")
        self.app.pop()
    end
end

function Chart:drawCell(x, y)
    local g = self.app.game
    local info = g:chartInfo(x, y)
    local q = g:quad(x, y)
    local bx, by = GX + x * CELL, GY + y * CELL
    local mx, my = cx(x), cy(y)
    local here = x == g.ship.qx and y == g.ship.qy

    if not info then
        theme.set("dim", 0.7)
        ui.centered("?", mx, my, 11, "pixel", "center")
        return
    end
    if info.nova then
        theme.set("bad", 0.1)
        ui.rect("fill", bx + 1, by + 1, CELL - 1, CELL - 1)
        sprites.draw("star", mx, my, 34, 0, 0.9, "bad")
        return
    end
    local stale = not info.live and (g.date - info.d) > 1.5
    local a = stale and 0.55 or 1
    if info.k > 0 then
        theme.set("klingon", a)
        ui.centered(tostring(info.k), mx, my, 22, "pixel", "center")
    end
    if info.b > 0 then sprites.draw("base", bx + CELL - 11, by + 11, 20, 0, a) end
    if info.sys then sprites.draw("planet", bx + 11, by + 11, 20, 0, a) end
    theme.set("star", a * 0.8)
    ui.centered("*" .. info.s, bx + CELL - 4, by + CELL - 9, 11, "pixel", "right")
    if here then
        sprites.draw(g.ship.kind == C.QUEENE and "queene" or "ship", bx + 11, by + CELL - 11, 22, 0, 1)
    end
    -- distress calls in red
    if q.distress and (q.attacked or q.enslaved) then
        theme.set("bad")
        ui.rect("line", bx + 2, by + 2, CELL - 3, CELL - 3)
    end
end

function Chart:drawPanel()
    local g = self.app.game
    local c = self.cursor
    local s = g.ship
    local x, r = PX, PX + PW
    local info = g:chartInfo(c.x, c.y)
    local q = g:quad(c.x, c.y)

    theme.set("text")
    ui.centered(("Quadrant %d,%d"):format(c.x, c.y), x, 30, 22, "bold", "left")
    local y = 54
    local function line(text, slot, weight)
        theme.set(slot or "muted")
        ui.centered(text, x, y, 15, weight or "regular", "left")
        y = y + 22
    end
    if not info then
        line("Not scanned yet.")
    elseif info.nova then
        line("Supernova remnant. Nothing survived.", "bad")
    else
        if info.sys then line(info.sys .. (q.enslaved and q.distress and ", enslaved" or ""), "planet", "bold") end
        line(info.k > 0 and (info.k .. " Klingon" .. (info.k == 1 and "" or "s")) or "No Klingons",
            info.k > 0 and "klingon" or "muted", info.k > 0 and "bold" or "regular")
        if info.b > 0 then line(q.attacked and q.distress and "Starbase, under attack" or "Starbase", "base", "bold") end
        line(info.s .. " star" .. (info.s == 1 and "" or "s"))
        line(info.live and "Live scan: we're here." or ("Scanned on stardate %.1f"):format(info.d), "dim")
    end

    y = math.max(y + 8, 170)
    theme.set("line")
    ui.rect("fill", x, y - 12, PW, 1)

    -- the helm
    theme.set("dim")
    ui.centered("WARP FACTOR", x, y + 4, 12, "bold", "left")
    theme.set("accent")
    ui.centered("←", r - 104, y + 24, 22, "pixel", "center")
    ui.centered("→", r - 14, y + 24, 22, "pixel", "center")
    theme.set("text")
    ui.centered(ui.one(s.warp), r - 59, y + 24, 22, "pixel", "center")
    local plan = self.plan
    y = y + 52
    if not plan then
        line("Pick another quadrant to plot a course.")
    else
        if plan.dist then
            line(("Course %d°  ·  %.1f quadrants"):format(math.floor(plan.course + 0.5) % 360, plan.dist), "muted")
        end
        if plan.ok then
            local engine = plan.engine == "warp" and "" or "Impulse only: "
            theme.set("muted")
            ui.centered(engine .. "Time", x, y, 15, "regular", "left")
            theme.set(plan.time > g.time and "bad" or "text")
            ui.centered(("%.2f days"):format(plan.time), r, y, 15, "bold", "right")
            y = y + 22
            theme.set("muted")
            ui.centered("Energy", x, y, 15, "regular", "left")
            theme.set(plan.energy > s.energy * 0.6 and "warn" or "text")
            ui.centered(ui.number(plan.energy) .. " of " .. ui.number(s.energy), r, y, 15, "bold", "right")
            y = y + 24
            if s.up then line("Shields are up, so warp costs double.", "dim") end
            if plan.strain then line(("%d%% risk of overheating the drive."):format(math.floor(plan.strain * 100 + 0.5)), "warn") end
            if plan.detour then line("Going around an obstacle.", "dim") end
        else
            theme.set("warn")
            ui.text(plan.reason, x, y - 8, 15, "regular", "left", PW)
            y = y + ui.wrap(plan.reason, 15, "regular", PW)
        end
    end

    -- distress calls
    local calls = g:distressCalls()
    if #calls > 0 then
        y = math.max(y + 6, 340)
        theme.set("dim")
        ui.centered("DISTRESS CALLS", x, y, 12, "bold", "left")
        y = y + 20
        for k, d in ipairs(calls) do
            if k > 3 then break end
            theme.set("bad")
            local text = d.kind == "base" and ("Starbase %d,%d: falls at %.1f"):format(d.x, d.y, d.until_)
                or ("%s (%d,%d) enslaved"):format(d.sys or "Planet", d.x, d.y)
            ui.centered(text, x, y, 14, "regular", "left")
            y = y + 20
        end
    end
end

function Chart:draw()
    local g = self.app.game
    local c = self.cursor
    starfield.draw(0.4)

    theme.set("panel", 0.6)
    ui.rect("fill", GX, GY, GW, GW)
    -- long-range scan reach around the ship
    if not g:damaged("lrscan") then
        theme.set("info", 0.06)
        local sx, sy = math.max(0, g.ship.qx - 1), math.max(0, g.ship.qy - 1)
        local ex, ey = math.min(NQ - 1, g.ship.qx + 1), math.min(NQ - 1, g.ship.qy + 1)
        ui.rect("fill", GX + sx * CELL + 1, GY + sy * CELL + 1, (ex - sx + 1) * CELL - 1, (ey - sy + 1) * CELL - 1)
    end
    theme.set("grid")
    for i = 1, NQ - 1 do
        ui.rect("fill", GX + i * CELL, GY + 1, 1, GW - 1)
        ui.rect("fill", GX + 1, GY + i * CELL, GW - 1, 1)
    end
    theme.set("line")
    ui.rect("line", GX, GY, GW + 1, GW + 1)
    for i = 0, NQ - 1 do
        theme.set(i == c.x and "accent" or "dim")
        ui.centered(tostring(i), cx(i), GY - 13, 11, "pixel", "center")
        theme.set(i == c.y and "accent" or "dim")
        ui.centered(tostring(i), GX - 13, cy(i), 11, "pixel", "center")
    end
    for y = 0, NQ - 1 do
        for x = 0, NQ - 1 do self:drawCell(x, y) end
    end

    -- course line
    local s = g.ship
    if self.plan and self.plan.ok then
        local x1, y1 = cx(s.qx), cy(s.qy)
        local x2, y2 = cx(c.x), cy(c.y)
        love.graphics.setLineWidth(1.5)
        theme.set("accent", 0.6)
        local dx, dy = x2 - x1, y2 - y1
        local len = math.sqrt(dx * dx + dy * dy)
        local t = 0
        while t < len do
            local t2 = math.min(len, t + 6)
            love.graphics.line(x1 + dx * t / len, y1 + dy * t / len, x1 + dx * t2 / len, y1 + dy * t2 / len)
            t = t2 + 5
        end
    end
    ui.brackets(GX + c.x * CELL - 1, GY + c.y * CELL - 1, CELL + 3, CELL + 3, 10, 2, "accent")

    -- legend
    local ly = GY + GW + 20
    local lx = GX
    theme.set("klingon")
    ui.centered("3", lx + 6, ly, 11, "pixel", "center")
    theme.set("muted")
    lx = lx + 16 + ui.centered("Klingons", lx + 16, ly, 14, "regular", "left") + 14
    sprites.draw("base", lx + 8, ly, 18, 0, 1)
    theme.set("muted")
    lx = lx + 20 + ui.centered("Starbase", lx + 20, ly, 14, "regular", "left") + 14
    sprites.draw("planet", lx + 8, ly, 18, 0, 1)
    theme.set("muted")
    lx = lx + 20 + ui.centered("Inhabited", lx + 20, ly, 14, "regular", "left") + 14
    theme.set("star")
    ui.centered("*5", lx, ly, 11, "pixel", "left")
    theme.set("muted")
    ui.centered("Stars", lx + 26, ly, 14, "regular", "left")

    self:drawPanel()
    if g:damaged("lrscan") then
        theme.set("bad")
        ui.centered("Long-range scanners damaged: the chart isn't updating.", PX, 432, 14, "regular", "left")
    end
    ui.hints({ { "L1", "Slower" }, { "R1", "Faster" }, { "B", "Back" }, { "A", "Engage" } }, PX + PW, 462, "right", 1, 14)
end

return Chart
