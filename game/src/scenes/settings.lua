local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")
local starfield = require("src.starfield")

local Settings = {}
Settings.__index = Settings

local ROWS = {
    { key = "theme", label = "Theme",
      about = "Deep Space is the default. Phosphor and Amber are monochrome, like the terminals BSD trek was first played on." },
    { key = "display", label = "Sector display", choices = { { "modern", "Modern" }, { "classic", "Classic" } },
      about = "Modern draws ships and stars. Classic shows the original letters: E is you, K a Klingon, # a starbase, * a star, @ an inhabited planet. A black hole is a gap in the dots." },
    { key = "speed", label = "Animations", choices = { { "normal", "Normal" }, { "fast", "Fast" } },
      about = "Fast plays combat and travel at double speed. Any button skips them." },
    { key = "sound", label = "Sound effects", about = "Phasers, torpedoes, alarms and the rest." },
}

function Settings.new(app)
    return setmetatable({ app = app, t = 0, sel = 1 }, Settings)
end

function Settings:update(dt)
    self.t = self.t + dt
end

function Settings:change(dir)
    local s = self.app.settings
    local row = ROWS[self.sel]
    if row.key == "theme" then
        local idx = 1
        for k, key in ipairs(theme.ORDER) do
            if key == s.theme then idx = k end
        end
        s.theme = theme.ORDER[(idx - 1 + dir) % #theme.ORDER + 1]
    elseif row.choices then
        local idx = 1
        for k, c in ipairs(row.choices) do
            if c[1] == s[row.key] then idx = k end
        end
        s[row.key] = row.choices[(idx - 1 + dir) % #row.choices + 1][1]
    else
        s[row.key] = not s[row.key]
    end
    self.app.applySettings()
    self.app.saveSettings()
    sound.play("menu")
end

function Settings:action(a)
    if a == "up" then
        self.sel = (self.sel - 2) % #ROWS + 1
        sound.play("menu")
    elseif a == "down" then
        self.sel = self.sel % #ROWS + 1
        sound.play("menu")
    elseif a == "left" then
        self:change(-1)
    elseif a == "right" or a == "a" then
        self:change(1)
    elseif a == "b" or a == "start" then
        sound.play("close")
        self.app.pop()
    end
end

function Settings:value(row)
    local v = self.app.settings[row.key]
    if row.key == "theme" then return theme.name(v) end
    if row.choices then
        for _, c in ipairs(row.choices) do
            if c[1] == v then return c[2] end
        end
    end
    return v and "On" or "Off"
end

function Settings:draw()
    starfield.draw(0.5)
    theme.set("text")
    ui.centered("Settings", 64, 52, 30, "bold", "left")

    local x, w, y0, h = 64, 592, 100, 46
    for k, row in ipairs(ROWS) do
        local cy = y0 + (k - 1) * h + h / 2
        local selected = (k == self.sel)
        if selected then
            theme.set("panel")
            ui.rect("fill", x - 16, cy - h / 2 + 3, w + 32, h - 6)
            theme.set("accent")
            ui.rect("fill", x - 16, cy - h / 2 + 3, 3, h - 6)
        end
        theme.set(selected and "text" or "muted")
        ui.centered(row.label, x, cy, 20, selected and "bold" or "regular", "left")
        theme.set(selected and "accent" or "text")
        local vw = ui.centered(self:value(row), x + w - 24, cy, 20, "bold", "right")
        if selected then
            theme.set("muted")
            ui.centered("←", x + w - 24 - vw - 18, cy, 22, "pixel", "center")
            ui.centered("→", x + w - 4, cy, 22, "pixel", "center")
        end
    end

    theme.set("muted")
    ui.text(ROWS[self.sel].about, x, y0 + #ROWS * h + 18, 16, "regular", "left", w)
    ui.hints({ { "B", "Back" }, { "A", "Change" } }, 696, 456, "right")
end

return Settings
