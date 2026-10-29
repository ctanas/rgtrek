-- The captain's log: every message of the voyage so far, with stardates.

local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")

local Log = {}
Log.__index = Log

local ROLE = {
    Helm = "helm", Tactical = "tactical", Science = "science", Comms = "comms",
    Engineering = "engineering", Medical = "medical", Computer = "computer",
}
local TONE = { info = "text", good = "good", warn = "warn", bad = "bad", alert = "bad" }

local X, W, TOP, BOTTOM = 40, 640, 76, 436

function Log.new(app)
    local self = setmetatable({ app = app, t = 0, scroll = 0 }, Log)
    return self
end

-- Lay out every entry: { y, h, entry }, from the top.
function Log:layout()
    local list, y = {}, 0
    for _, e in ipairs(self.app.game.log) do
        local h = ui.wrap(e.who .. "  " .. e.text, 16, "regular", W - 90)
        list[#list + 1] = { y = y, h = h, e = e }
        y = y + h + 6
    end
    return list, y
end

function Log:maxScroll()
    local _, total = self:layout()
    return math.max(0, total - (BOTTOM - TOP))
end

function Log:enter()
    self.scroll = self:maxScroll()
end

function Log:update(dt)
    self.t = self.t + dt
end

function Log:action(a)
    local step
    if a == "up" then step = -40
    elseif a == "down" then step = 40
    elseif a == "l1" or a == "left" then step = -(BOTTOM - TOP - 40)
    elseif a == "r1" or a == "right" then step = BOTTOM - TOP - 40
    elseif a == "a" or a == "b" or a == "start" then
        sound.play("close")
        self.app.pop()
        return
    end
    if step then
        local before = self.scroll
        self.scroll = math.max(0, math.min(self:maxScroll(), self.scroll + step))
        if self.scroll ~= before then sound.play("move") end
    end
end

function Log:draw()
    theme.set("text")
    ui.centered("Captain's log", X, 38, 26, "bold", "left")
    theme.set("muted")
    ui.centered("Stardate " .. ui.one(self.app.game.date), X + W, 40, 15, "regular", "right")
    theme.set("line")
    ui.rect("fill", X, 60, W, 1)

    local list = self:layout()
    for _, row in ipairs(list) do
        local y = TOP + row.y - self.scroll
        if y + row.h > TOP - 2 and y < BOTTOM then
            if y >= TOP - 2 and y + row.h <= BOTTOM + 2 then
                local e = row.e
                theme.set("dim")
                ui.text(ui.one(e.d), X, y, 16, "regular")
                ui.colored({ ROLE[e.who] or "muted", e.who .. "  ", TONE[e.tone] or "text", e.text },
                    X + 90, y, 16, "regular", W - 90)
            end
        end
    end
    -- scroll bar
    local max = self:maxScroll()
    if max > 0 then
        local trackH = BOTTOM - TOP
        local thumb = math.max(24, trackH * trackH / (trackH + max))
        theme.set("raised")
        ui.rect("fill", X + W + 12, TOP, 3, trackH)
        theme.set("muted")
        ui.rect("fill", X + W + 12, TOP + (trackH - thumb) * (self.scroll / max), 3, thumb)
    end
    ui.hints({ { "L1", "Page up" }, { "R1", "Page down" }, { "B", "Close" } }, X + W, 462, "right", 1, 14)
end

return Log
