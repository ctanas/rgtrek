-- Damage report: every system, and how long its repairs will take.

local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")
local C = require("src.trek.const")

local Damage = { overlay = true }
Damage.__index = Damage

function Damage.new(app)
    return setmetatable({ app = app, t = 0 }, Damage)
end

function Damage:update(dt)
    self.t = self.t + dt
end

function Damage:busy()
    return self.t < 0.3
end

function Damage:action(a)
    if a == "a" or a == "b" or a == "start" then
        sound.play("close")
        self.app.pop()
    end
end

function Damage:draw()
    local g = self.app.game
    local s = g.ship
    local p = ui.ease(self.t / 0.14)
    local w, h = 520, 404
    local x, y = ui.card(w, h, p)
    theme.set("text", p)
    ui.centered("Damage report", x + 24, y + 30, 22, "bold", "left")
    theme.set("muted", p)
    ui.centered(s.docked and "Docked: repairs run twice as fast" or "Repairs run twice as fast when docked",
        x + w - 24, y + 31, 14, "regular", "right")

    local rate = s.docked and 2 or 1
    local col = { x + 24, x + w / 2 + 8 }
    local rowH = 26
    for k, d in ipairs(C.DEVICES) do
        local cx = col[(k - 1) % 2 + 1]
        local cy = y + 74 + math.floor((k - 1) / 2) * rowH
        local cw = w / 2 - 32
        local left = g.dmg[d.key] / rate
        local absent = d.key == "cloak" and not s.hasCloak
        theme.set(absent and "dim" or "text", p)
        ui.centered(d.name, cx, cy, 15, "regular", "left")
        if absent then
            theme.set("dim", p)
            ui.centered("none", cx + cw, cy, 15, "regular", "right")
        elseif left > 0 then
            theme.set("bad", p)
            ui.centered(("%.1f days"):format(left), cx + cw, cy, 15, "bold", "right")
        else
            theme.set("good", p)
            ui.centered("OK", cx + cw, cy, 15, "bold", "right")
        end
    end

    local fy = y + 74 + 7 * rowH + 6
    theme.set("line", p)
    ui.rect("fill", x + 24, fy - 12, w - 48, 1)
    local facts = {
        { "Crew", tostring(s.crew) },
        { "Captives in the brig", tostring(s.brig) },
        { "Life support reserves", ("%.1f days"):format(s.reserves) },
        { "Repairs complete in", g:repairTime() > 0 and ("%.1f days"):format(g:repairTime()) or "nothing to repair" },
    }
    for k, f in ipairs(facts) do
        local cy = fy + 8 + (k - 1) * 24
        theme.set("muted", p)
        ui.centered(f[1], x + 24, cy, 15, "regular", "left")
        theme.set("text", p)
        ui.centered(f[2], x + w - 24, cy, 15, "bold", "right")
    end
    if g:damaged("lifesup") and not s.docked then
        theme.set("bad", p)
        ui.centered("Life support is down: the reserves are running out.", x + 24, y + h - 54, 15, "bold", "left")
    end
    ui.hints({ { "B", "Close" } }, x + w - 18, y + h - 22, "right", p, 14)
end

return Damage
