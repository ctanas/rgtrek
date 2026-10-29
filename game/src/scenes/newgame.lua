-- Choose the length of the mission and the skill level.

local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")
local starfield = require("src.starfield")
local C = require("src.trek.const")

local NewGame = {}
NewGame.__index = NewGame

local ABOUT = {
    "Weak Klingons and a quick recharge. Plenty of life support reserves.",
    "The classic starting point. Energy and shields slowly recharge.",
    "Stronger Klingons, fewer starbases, and a slow recharge.",
    "Tough Klingons and few starbases. Energy barely recharges.",
    "No recharge at all: every unit of energy counts.",
    "One starbase and fearsome Klingons. Good luck, Captain.",
}

function NewGame.new(app)
    local self = setmetatable({ app = app, t = 0, row = 1 }, NewGame)
    self.skill = app.settings.skill
    self.lengthIdx = 1
    for k, l in ipairs(C.LENGTHS) do
        if l.key == app.settings.length then self.lengthIdx = k end
    end
    return self
end

function NewGame:update(dt)
    self.t = self.t + dt
end

function NewGame:busy()
    return self.t < 0.3
end

function NewGame:start()
    local app = self.app
    local skill, length = self.skill, C.LENGTHS[self.lengthIdx].key
    if app.hasGame() then
        app.push("confirm", {
            title = "Start a new mission?",
            body = "The mission in progress will be abandoned.",
            yes = "New mission",
            onYes = function() app.newGame(skill, length) end,
        })
    else
        app.newGame(skill, length)
    end
end

function NewGame:action(a)
    if a == "up" or a == "down" then
        self.row = 3 - self.row
        sound.play("menu")
    elseif a == "left" or a == "right" then
        local d = a == "left" and -1 or 1
        if self.row == 1 then
            self.lengthIdx = math.max(1, math.min(#C.LENGTHS, self.lengthIdx + d))
        else
            self.skill = math.max(1, math.min(#C.SKILLS, self.skill + d))
        end
        sound.play("move")
    elseif a == "a" or a == "start" then
        sound.play("open")
        self:start()
    elseif a == "b" then
        sound.play("close")
        self.app.pop()
    end
end

function NewGame:draw()
    starfield.draw(0.5)
    theme.set("text")
    ui.centered("New mission", 64, 52, 30, "bold", "left")

    local length = C.LENGTHS[self.lengthIdx]
    local rows = {
        { "Length", length.name, self.lengthIdx, #C.LENGTHS },
        { "Skill", C.SKILLS[self.skill], self.skill, #C.SKILLS },
    }
    for k, row in ipairs(rows) do
        local cy = 120 + (k - 1) * 56
        local selected = k == self.row
        if selected then
            theme.set("panel")
            ui.rect("fill", 48, cy - 22, 624, 44)
            theme.set("accent")
            ui.rect("fill", 48, cy - 22, 3, 44)
        end
        theme.set(selected and "text" or "muted")
        ui.centered(row[1], 68, cy, 20, selected and "bold" or "regular", "left")
        theme.set(row[3] > 1 and "accent" or "dim")
        ui.centered("←", 420, cy, 22, "pixel", "center")
        theme.set(row[3] < row[4] and "accent" or "dim")
        ui.centered("→", 640, cy, 22, "pixel", "center")
        theme.set(selected and "text" or "muted")
        ui.centered(string.upper(row[2]), 530, cy, 22, "pixel", "center")
    end

    -- what this mission looks like, from the same rules as setup
    local skill, len = self.skill, length.key
    local kmin = skill * len * 5
    local kmax = math.max(kmin, math.floor(skill * len * 3.5 * 1.75))
    local bmin, bmax = 2, 6 - skill + 1
    if skill >= 6 then bmin, bmax = 1, 1 end
    local power = 100 + 150 * skill + (skill >= 6 and 150 or 0)
    local facts = {
        { "Klingons", kmin == kmax and tostring(kmin) or (kmin .. " to " .. kmax) },
        { "Starbases", bmin == bmax and tostring(bmin) or (bmin .. " to " .. bmax) },
        { "Time at the start", (6 * len + 2) .. " days" },
        { "Klingon power", tostring(power) },
    }
    theme.set("muted")
    ui.text(ABOUT[skill], 68, 222, 17, "regular", "left", 584)
    for k, f in ipairs(facts) do
        local cy = 284 + (k - 1) * 28
        theme.set("muted")
        ui.centered(f[1], 68, cy, 16, "regular", "left")
        theme.set("text")
        ui.centered(f[2], 652, cy, 16, "bold", "right")
    end
    theme.set("dim")
    ui.text("Each Klingon destroyed adds to the time left.", 68, 396, 15, "regular", "left", 584)

    ui.hints({ { "B", "Back" }, { "A", "Launch" } }, 696, 456, "right")
end

return NewGame
