-- Phaser control: choose how much energy to fire, at every Klingon in the
-- quadrant or at one. The grid shows what each Klingon would take.

local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")
local Game = require("src.trek.game")

local Phasers = { overlay = true }
Phasers.__index = Phasers

-- focus: optional {x, y} of one Klingon to aim at.
function Phasers.new(app, focus)
    local self = setmetatable({ app = app, t = 0 }, Phasers)
    self.play = app.find("play")
    local g = app.game
    local c = self.play.cursor
    -- the cursor's Klingon, if any, is the one Y focuses on
    self.focusable = g:klingonAt(c.x, c.y) and { x = c.x, y = c.y }
    self.focus = focus
    self.units = self:needed()
    if self.units <= 0 then self.units = 200 end
    self:clamp()
    self:updatePreview()
    return self
end

function Phasers:focusK()
    return self.focus and self.app.game:klingonAt(self.focus.x, self.focus.y)
end

-- Energy that would destroy every target.
function Phasers:needed()
    local need = 0
    for _, e in ipairs(self.app.game:phaserPlan(1e9, self:focusK())) do need = need + e.need end
    return need
end

function Phasers:maxUnits()
    local g = self.app.game
    return math.max(0, math.min(Game.MAX_PHASER, math.floor((g.ship.energy - 1) / 10) * 10))
end

function Phasers:clamp()
    self.units = math.max(10, math.min(self:maxUnits(), self.units))
end

function Phasers:updatePreview()
    self.plan = self.app.game:phaserPlan(self.units, self:focusK())
    self.play.preview = { kind = "phaser", plan = self.plan }
end

function Phasers:leave()
    self.play.preview = nil
end

function Phasers:update(dt)
    self.t = self.t + dt
end

function Phasers:busy()
    return self.t < 0.3
end

function Phasers:adjust(d)
    local before = self.units
    self.units = self.units + d
    self:clamp()
    if self.units ~= before then
        sound.play("move")
        self:updatePreview()
    end
end

function Phasers:action(a)
    if a == "left" then self:adjust(-50)
    elseif a == "right" then self:adjust(50)
    elseif a == "down" or a == "l1" then self:adjust(-250)
    elseif a == "up" or a == "r1" then self:adjust(250)
    elseif a == "y" then
        if self.focus then
            self.focus = nil
        elseif self.focusable then
            self.focus = self.focusable
        else
            sound.play("error")
            return
        end
        sound.play("menu")
        self.units = math.max(10, math.min(self:maxUnits(), self:needed()))
        self:updatePreview()
    elseif a == "a" then
        local units, focus = self.units, self.focus
        sound.play("open")
        self.app.pop()
        self.play:run(function(g)
            if focus then g:cmdPhasers(units, focus.x, focus.y) else g:cmdPhasers(units) end
        end)
    elseif a == "b" or a == "start" then
        sound.play("close")
        self.app.pop()
    end
end

function Phasers:draw()
    local g = self.app.game
    local p = ui.ease(self.t / 0.14)
    local x, w = self.play.PX - 12, self.play.PW + 24
    local y, h = 16, 404
    ui.panel(x, y, w, h, p)
    ui.brackets(x - 1, y - 1, w + 2, h + 2, 10, 2, "accent", p)

    theme.set("text", p)
    ui.centered("Phasers", x + 18, y + 26, 20, "bold", "left")
    theme.set("muted", p)
    local focusK = self:focusK()
    ui.centered(focusK and ("On the Klingon at %d,%d"):format(focusK.x, focusK.y)
        or ("Spread across %d Klingon%s"):format(#g.kl, #g.kl == 1 and "" or "s"), x + 18, y + 50, 14, "regular", "left")

    -- energy to fire
    local cy = y + 104
    theme.set("dim", p)
    ui.centered("ENERGY", x + 18, cy - 22, 12, "bold", "left")
    theme.set("accent", p)
    ui.centered("←", x + 18, cy, 22, "pixel", "left")
    ui.centered("→", x + w - 18, cy, 22, "pixel", "right")
    theme.set("text", p)
    ui.centered(ui.number(self.units), x + w / 2, cy, 33, "pixel", "center")

    local need = self:needed()
    local lines = {
        { "Needed to destroy " .. (focusK and "it" or "all"), ui.number(need), self.units >= need and "good" or "warn" },
        { "Energy afterwards", ui.number(g.ship.energy - self.units), "text" },
    }
    local ly = cy + 36
    for _, l in ipairs(lines) do
        theme.set("muted", p)
        ui.centered(l[1], x + 18, ly, 15, "regular", "left")
        theme.set(l[3], p)
        ui.centered(l[2], x + w - 18, ly, 15, "bold", "right")
        ly = ly + 22
    end

    -- each target
    theme.set("line", p)
    ui.rect("fill", x + 12, ly - 4, w - 24, 1)
    ly = ly + 12
    for _, e in ipairs(self.plan) do
        if ly > y + h - 110 then break end
        local k = e.k
        local d = g:dist(k.x, k.y)
        local sure = e.units >= e.need
        theme.set("klingon", p)
        ui.centered(("%d,%d"):format(k.x, k.y), x + 18, ly, 15, "bold", "left")
        theme.set("muted", p)
        ui.centered(("%.1f away"):format(d), x + 64, ly, 15, "regular", "left")
        local text, slot
        if e.units <= 0 then
            text, slot = "no energy left", "dim"
        elseif sure then
            text, slot = "destroyed", "good"
        else
            text, slot = ("hit for ~%d"):format(math.floor(e.units * 0.9 ^ d)), "phaser"
        end
        theme.set(slot, p)
        ui.centered(text, x + w - 18, ly, 15, sure and "bold" or "regular", "right")
        ly = ly + 21
    end

    -- warnings
    local notes = {}
    if g.ship.up then notes[#notes + 1] = "Shields drop to fire and come back up after, weaker this turn." end
    if self.units > 1000 then notes[#notes + 1] = "Over 1,000 the phaser banks may overheat." end
    local ny = y + h - 46
    for k = #notes, 1, -1 do
        local nh = ui.wrap(notes[k], 14, "regular", w - 36)
        ny = ny - nh - 2
        theme.set(k == 2 and "warn" or "muted", p)
        ui.text(notes[k], x + 18, ny, 14, "regular", "left", w - 36)
    end

    local hints = { { "B", "Cancel" }, { "A", "Fire" } }
    if self.focusable or self.focus then table.insert(hints, 1, { "Y", self.focus and "Spread" or "Focus" }) end
    ui.hints(hints, x + w - 16, y + h - 22, "right", p, 14)
end

return Phasers
