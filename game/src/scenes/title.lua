local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")
local sprites = require("src.sprites")
local starfield = require("src.starfield")
local C = require("src.trek.const")

local Title = {}
Title.__index = Title

local INTRO = 1.6 -- warp streaks, then the stars settle

function Title.new(app)
    local self = setmetatable({ app = app, t = 0, sel = 1 }, Title)
    self:build()
    return self
end

function Title:build()
    local app = self.app
    self.items = {}
    if app.hasGame() then
        local g = app.game
        self.items[#self.items + 1] = {
            label = "Continue",
            detail = ("Stardate %.1f  ·  %d Klingons left"):format(g.date, g.klings),
            run = function() app.setScene("play") end,
        }
    end
    self.items[#self.items + 1] = { label = "New mission", run = function() app.push("newgame") end }
    self.items[#self.items + 1] = { label = "How to play", run = function() app.push("help") end }
    self.items[#self.items + 1] = { label = "Records", run = function() app.push("records") end }
    self.items[#self.items + 1] = { label = "Settings", run = function() app.push("settings") end }
    self.items[#self.items + 1] = { label = "Quit", run = function() app.quit() end }
    self.sel = math.min(self.sel, #self.items)
end

function Title:enter()
    sound.play("warp", 0.6)
end

function Title:resume()
    self:build()
end

function Title:update(dt)
    self.t = self.t + dt
end

function Title:busy()
    return self.t < INTRO + 0.6
end

function Title:action(a)
    if a == "up" then
        self.sel = (self.sel - 2) % #self.items + 1
        sound.play("menu")
    elseif a == "down" then
        self.sel = self.sel % #self.items + 1
        sound.play("menu")
    elseif a == "a" or a == "start" then
        sound.play("open")
        self.items[self.sel].run()
    end
end

function Title:draw()
    local t = self.t
    local settle = ui.ease((t - INTRO * 0.6) / 0.8)
    starfield.draw(settle)
    if t < INTRO then
        local k = math.sin(math.min(1, t / INTRO) * math.pi)
        starfield.streaks(0, 0, ui.W, ui.H, 270, k, t)
    end

    -- the ship, coming out of warp
    local p = ui.ease((t - 0.5) / 1.1)
    local shipX, shipY = 548 - (1 - p) * 200, 236 + (1 - p) * 90
    sprites.draw("star", 610, 132, 120, 0, settle * 0.5)
    sprites.draw("planet", 610, 132, 64, 0, settle)
    sprites.draw("ship", shipX, shipY, 120, 52, p)
    sprites.draw("klingon", 668, 380, 44, 300, settle * 0.9)
    sprites.draw("star", 452, 404, 30, 0, settle)

    local a = ui.ease((t - 0.3) / 0.6)
    theme.set("text", a)
    ui.centered("rgTREK", 60, 92, 66, "pixel", "left")
    theme.set("muted", a)
    ui.centered("BSD trek, reborn for handhelds", 62, 140, 17, "regular", "left")

    local y = 206
    for k, item in ipairs(self.items) do
        local selected = (k == self.sel)
        local cy = y + (k - 1) * 40
        if selected then
            theme.set("accent", a)
            ui.rect("fill", 44, cy - 6, 8, 12)
        end
        theme.set(selected and "text" or "muted", a)
        local w = ui.centered(item.label, 64, cy, 24, selected and "bold" or "regular", "left")
        if item.detail then
            theme.set("dim", a)
            ui.centered(item.detail, 64 + w + 14, cy + 1, 15, "regular", "left")
        end
    end

    theme.set("dim", a)
    ui.centered("Version " .. self.app.version, 24, 456, 11, "pixel", "left")
    ui.hints({ { "A", "Select" } }, 696, 456, "right", a)
end

-- for the help screen and others that want the names
Title.SKILLS = C.SKILLS

return Title
