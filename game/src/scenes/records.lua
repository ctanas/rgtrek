-- The best scores so far.

local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")
local starfield = require("src.starfield")
local C = require("src.trek.const")

local Records = {}
Records.__index = Records

function Records.new(app, highlight)
    return setmetatable({ app = app, t = 0, highlight = highlight }, Records)
end

function Records:update(dt)
    self.t = self.t + dt
end

function Records:action(a)
    if a == "a" or a == "b" or a == "start" then
        sound.play("close")
        self.app.pop()
    end
end

local function lengthName(key)
    for _, l in ipairs(C.LENGTHS) do
        if l.key == key then return l.name end
    end
    return "?"
end

function Records:draw()
    starfield.draw(0.5)
    theme.set("text")
    ui.centered("Records", 64, 52, 30, "bold", "left")
    local list = self.app.records
    if #list == 0 then
        theme.set("muted")
        ui.text("No missions finished yet. Scores appear here when a mission ends, won or lost.",
            64, 100, 17, "regular", "left", 592)
    else
        local cols = { 64, 140, 236, 336, 486, 656 }
        theme.set("dim")
        ui.centered("SCORE", cols[2] + 60, 96, 12, "bold", "right")
        ui.centered("RESULT", cols[3], 96, 12, "bold", "left")
        ui.centered("MISSION", cols[4], 96, 12, "bold", "left")
        ui.centered("KLINGONS", cols[5], 96, 12, "bold", "left")
        ui.centered("DATE", cols[6], 96, 12, "bold", "right")
        for k, r in ipairs(list) do
            local cy = 124 + (k - 1) * 31
            if k == self.highlight then
                theme.set("panel")
                ui.rect("fill", 48, cy - 14, 624, 28)
                theme.set("accent")
                ui.rect("fill", 48, cy - 14, 3, 28)
            end
            theme.set("dim")
            ui.centered(tostring(k), cols[1], cy, 22, "pixel", "left")
            theme.set("text")
            ui.centered(ui.number(r.score), cols[2] + 60, cy, 22, "pixel", "right")
            theme.set(r.won and "good" or "bad")
            ui.centered(r.won and "Won" or "Lost", cols[3], cy, 16, "bold", "left")
            theme.set("muted")
            ui.centered(lengthName(r.length) .. ", " .. (C.SKILLS[r.skill] or "?"), cols[4], cy, 16, "regular", "left")
            ui.centered(("%d of %d"):format(r.killed or 0, r.klingons or 0), cols[5], cy, 16, "regular", "left")
            ui.centered(r.date or "", cols[6], cy, 16, "regular", "right")
        end
    end
    ui.hints({ { "B", "Back" } }, 696, 456, "right")
end

return Records
