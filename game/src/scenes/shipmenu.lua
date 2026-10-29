-- The ship menu (Start): shields, docking, rest, cloak, reports, and the
-- emergency measures, which ask for confirmation.

local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")

local ShipMenu = { overlay = true }
ShipMenu.__index = ShipMenu

-- mode: nil for the main menu, "emergency" for the emergency measures.
function ShipMenu.new(app, mode)
    local self = setmetatable({ app = app, t = 0, sel = 1, mode = mode }, ShipMenu)
    self.play = app.find("play")
    self:build()
    return self
end

function ShipMenu:resume()
    self:build()
end

function ShipMenu:build()
    local app, play = self.app, self.play
    local g = app.game
    local s = g.ship
    local items = {}
    self.items = items
    local function add(label, run, why, detail)
        items[#items + 1] = { label = label, run = run, why = why, detail = detail }
    end
    local function order(fn)
        return function()
            app.popTo("play")
            play:run(fn)
        end
    end

    if self.mode == "emergency" then
        self.title = "Emergency"
        local fail = g:helpFailChance()
        add("Call a starbase for help", function()
            local lost = fail and math.floor(fail ^ 3 * 1000 + 0.5) / 10 or 0
            app.push("confirm", {
                title = "Call for help?",
                body = ("The nearest starbase will try to beam the crew home, up to three times. "
                    .. "Chance all three fail: %s%%. It costs 100 points."):format(lost < 0.1 and "under 0.1" or ui.one(lost)),
                yes = "Call",
                onYes = order(function(game) game:cmdHelp() end),
            })
        end, g:helpCheck())
        add("Abandon ship", function()
            app.push("confirm", {
                title = "Abandon the " .. s.name .. "?",
                body = "The crew takes the shuttlecraft to the nearest starbase and commands the Faire Queene, "
                    .. "which has no cloaking device. It costs 200 points.",
                yes = "Abandon",
                onYes = order(function(game) game:cmdAbandon() end),
            })
        end, g:abandonCheck())
        add("Self-destruct", function()
            app.push("confirm", {
                title = "Self-destruct?",
                body = "The ship is destroyed along with any Klingons within 6 sectors. The game ends.",
                yes = "Destruct",
                onYes = order(function(game) game:cmdDestruct() end),
            })
        end)
        return
    end

    self.title = s.name
    add(s.up and "Lower shields" or "Raise shields", order(function(game) game:cmdShields() end),
        (not s.up and g:damaged("shield")) and "Shield control is damaged." or nil)
    if g:adjacentBase() and not s.docked then
        add("Dock at the starbase", order(function(game) game:cmdDock() end))
    end
    add("Rest and repair...", function() app.pop() app.push("rest") end, g:restCheck())
    if s.hasCloak then
        local why
        if not s.cloaked and g:damaged("cloak") then why = "The cloaking device is damaged."
        elseif not s.cloaked and s.docked then why = "We can't cloak while docked." end
        add(s.cloaked and "Cloaking device off" or "Cloaking device on",
            order(function(game) game:cmdCloak() end), why)
    end
    add("Star chart", function() app.pop() app.push("chart") end)
    add("Damage report", function() app.pop() app.push("damage") end)
    add("Captain's log", function() app.pop() app.push("log") end)
    add("Emergency...", function() app.push("shipmenu", "emergency") end)
    add("Settings", function() app.push("settings") end)
    add("How to play", function() app.push("help") end)
    add("Save and exit", function()
        app.saveGame()
        app.setScene("title")
    end)
end

function ShipMenu:update(dt)
    self.t = self.t + dt
end

function ShipMenu:busy()
    return self.t < 0.3
end

function ShipMenu:action(a)
    if a == "up" then
        self.sel = (self.sel - 2) % #self.items + 1
        sound.play("menu")
    elseif a == "down" then
        self.sel = self.sel % #self.items + 1
        sound.play("menu")
    elseif a == "a" then
        local item = self.items[self.sel]
        if item.why then
            sound.play("error")
        else
            sound.play("open")
            item.run()
        end
    elseif a == "b" or a == "start" or a == "menu" then
        sound.play("close")
        self.app.pop()
    end
end

function ShipMenu:draw()
    local p = ui.ease(self.t / 0.14)
    local rowH = 30
    local item = self.items[self.sel]
    local noteH = item.why and 26 or 0
    local w = 360
    local h = 70 + #self.items * rowH + noteH + 40
    local x, y = ui.card(w, h, p)

    theme.set("text", p)
    ui.centered(self.title, x + 24, y + 30, 22, "bold", "left")
    if self.mode ~= "emergency" then
        theme.set("muted", p)
        local g = self.app.game
        ui.centered("Stardate " .. ui.one(g.date), x + w - 24, y + 31, 14, "regular", "right")
    end

    for k, it in ipairs(self.items) do
        local cy = y + 72 + (k - 1) * rowH
        local selected = k == self.sel
        if selected then
            theme.set("raised", p)
            ui.rect("fill", x + 12, cy - rowH / 2 + 2, w - 24, rowH - 4)
            theme.set("accent", p)
            ui.rect("fill", x + 12, cy - rowH / 2 + 2, 3, rowH - 4)
        end
        theme.set(it.why and "dim" or (selected and "text" or "muted"), p)
        ui.centered(it.label, x + 28, cy, 17, selected and "bold" or "regular", "left")
    end
    if item.why then
        theme.set("warn", p)
        ui.centered(item.why, x + 28, y + 72 + #self.items * rowH, 14, "regular", "left")
    end
    ui.hints({ { "B", "Back" }, { "A", "Select" } }, x + w - 18, y + h - 22, "right", p, 14)
end

return ShipMenu
