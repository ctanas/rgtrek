-- Rest: let days pass while the crew repairs the ship.

local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")

local Rest = { overlay = true }
Rest.__index = Rest

function Rest.new(app)
    local self = setmetatable({ app = app, t = 0 }, Rest)
    local need = app.game:repairTime()
    self.days = need > 0 and math.ceil(need * 10) / 10 or 1
    self:clamp()
    return self
end

function Rest:maxDays()
    return math.max(0.5, math.min(10, math.floor(self.app.game.time * 10) / 10))
end

function Rest:clamp()
    self.days = math.max(0.1, math.min(self:maxDays(), self.days))
end

function Rest:update(dt)
    self.t = self.t + dt
end

function Rest:busy()
    return self.t < 0.3
end

function Rest:action(a)
    local before = self.days
    if a == "left" then self.days = math.floor((self.days - 0.5) * 2 + 0.5) / 2
    elseif a == "right" then self.days = math.floor((self.days + 0.5) * 2 + 0.5) / 2
    elseif a == "y" then
        local need = self.app.game:repairTime()
        if need > 0 then self.days = math.ceil(need * 10) / 10 end
    elseif a == "a" then
        local days = self.days
        sound.play("open")
        self.app.pop()
        self.app.find("play"):run(function(g) g:cmdRest(days) end)
        return
    elseif a == "b" or a == "start" then
        sound.play("close")
        self.app.pop()
        return
    end
    self:clamp()
    if self.days ~= before then sound.play("move") end
end

function Rest:draw()
    local g = self.app.game
    local p = ui.ease(self.t / 0.14)
    local w, h = 400, 236
    local x, y = ui.card(w, h, p)
    theme.set("text", p)
    ui.centered("Rest and repair", x + 24, y + 30, 22, "bold", "left")

    local cy = y + 86
    theme.set("accent", p)
    ui.centered("←", x + 70, cy, 22, "pixel", "center")
    ui.centered("→", x + w - 70, cy, 22, "pixel", "center")
    theme.set("text", p)
    ui.centered(ui.one(self.days), x + w / 2 - 4, cy, 33, "pixel", "right")
    theme.set("muted", p)
    ui.centered("days", x + w / 2 + 6, cy + 2, 17, "regular", "left")

    local need = g:repairTime()
    local lines = {
        need > 0 and ("All repairs done in %.1f days%s."):format(need, g.ship.docked and " (docked, so twice as fast)" or "")
            or "Every system is working.",
        ("Time left: %.1f days. Resting stops early if something comes up."):format(g.time),
    }
    local ly = cy + 34
    for _, l in ipairs(lines) do
        theme.set("muted", p)
        ui.text(l, x + 24, ly, 15, "regular", "left", w - 48)
        ly = ly + ui.wrap(l, 15, "regular", w - 48) + 4
    end
    local hints = { { "B", "Cancel" }, { "A", "Rest" } }
    if need > 0 then table.insert(hints, 1, { "Y", "Until repaired" }) end
    ui.hints(hints, x + w - 18, y + h - 22, "right", p, 14)
end

return Rest
