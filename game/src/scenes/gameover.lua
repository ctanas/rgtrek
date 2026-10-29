-- The end of a mission: what happened, the score, and the records.

local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")
local starfield = require("src.starfield")
local C = require("src.trek.const")

local GameOver = {}
GameOver.__index = GameOver

function GameOver.new(app)
    local self = setmetatable({ app = app, t = 0 }, GameOver)
    local g = app.game
    self.won = g.over.won
    self.text = g.over.text
    self.total, self.rows = g:score()
    -- BSD trek promoted a captain who won well
    local par = g.p.klings * g.p.klingpwr / 4
    if self.won and self.total >= par and g.stats.basesKilled == 0 then
        self.promotion = C.RANKS[g.skill + 1]
    end
    self.place = app.recordGame()
    return self
end

function GameOver:enter()
    sound.play(self.won and "win" or "lose")
end

function GameOver:update(dt)
    self.t = self.t + dt
end

function GameOver:busy()
    return self.t < 1.2
end

function GameOver:action(a)
    if self.t < 0.6 then return end
    if a == "a" or a == "b" or a == "start" then
        sound.play("open")
        local app = self.app
        app.game = nil
        app.setScene("title")
        if self.place then app.push("records", self.place) end
    end
end

function GameOver:draw()
    starfield.draw(0.5)
    local p = ui.ease(self.t / 0.6)
    theme.set(self.won and "good" or "bad", p)
    ui.centered(self.won and "MISSION ACCOMPLISHED" or "MISSION FAILED", 64, 56, 33, "pixel", "left")
    theme.set("text", p)
    ui.text(self.text, 64, 86, 18, "regular", "left", 592)
    local y = 96 + ui.wrap(self.text, 18, "regular", 592)

    if self.promotion then
        theme.set("accent", p)
        ui.centered("Starfleet promotes you to " .. self.promotion .. ".", 64, y + 14, 18, "bold", "left")
        y = y + 34
    end

    y = y + 18
    local maxRows = math.floor((404 - y) / 24)
    for k, row in ipairs(self.rows) do
        if k > maxRows then break end
        local cy = y + (k - 1) * 24
        theme.set("muted", p)
        ui.centered(row.label .. (row.count and row.count ~= 1 and ("  ×" .. row.count) or ""), 64, cy, 16, "regular", "left")
        theme.set(row.points >= 0 and "text" or "bad", p)
        ui.centered((row.points > 0 and "+" or "") .. ui.number(row.points), 656, cy, 16, "bold", "right")
    end
    local ty = math.min(y + #self.rows * 24, y + maxRows * 24) + 4
    theme.set("line", p)
    ui.rect("fill", 64, ty - 10, 592, 1)
    theme.set("text", p)
    ui.centered("Score", 64, ty + 12, 20, "bold", "left")
    theme.set("accent", p)
    ui.centered(ui.number(self.total), 656, ty + 12, 22, "pixel", "right")

    if self.place then
        theme.set("muted", p)
        ui.centered(self.place == 1 and "A new best score!" or ("Number " .. self.place .. " in the records."),
            64, 456, 16, "regular", "left")
    end
    ui.hints({ { "A", "Continue" } }, 696, 456, "right", p)
end

return GameOver
