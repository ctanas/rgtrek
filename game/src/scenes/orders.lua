-- Orders for whatever is under the cursor: move there, fire on it, dock
-- with it... Each order shows what it costs before you commit, and the
-- grid shows the plotted course or the torpedo's line.

local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")
local C = require("src.trek.const")

local Orders = { overlay = true }
Orders.__index = Orders

local NS = C.NSECTS

function Orders.new(app)
    local self = setmetatable({ app = app, t = 0, sel = 1 }, Orders)
    self.play = app.find("play")
    self:build()
    return self
end

-- "Warp 5.0 · 0.24 days · 62 energy"
local function costText(info)
    local engine = info.engine == "warp" and ("Warp " .. ui.one(app.game.ship.warp)) or "Impulse"
    local text = ("%s  ·  %.2f days  ·  %s energy"):format(engine, info.time, ui.number(info.energy))
    if info.detour then text = text .. "\nGoing around an obstacle." end
    if info.strain then text = text .. ("\n%d%% risk of overheating the warp drive."):format(math.floor(info.strain * 100 + 0.5)) end
    return text
end

function Orders:build()
    local app = self.app
    local g = app.game
    local play = self.play
    local c = play.cursor
    local v = play.view
    local items = {}
    self.items = items

    local function add(item) items[#items + 1] = item end
    local function run(fn)
        return function()
            app.pop()
            play:run(fn)
        end
    end

    local function moveItem(label, tx, ty, approach)
        local ax, ay = tx, ty
        if approach then ax, ay = g:approachSector(tx, ty) end
        if not ax then
            add({ label = label, why = "There's no room alongside." })
            return
        end
        local info = g:plan(v.qx * NS + ax, v.qy * NS + ay)
        if ax == v.x and ay == v.y then
            info = { ok = true, route = nil }
        end
        add({
            label = label,
            detail = info.ok and info.engine and costText(info) or (info.ok and "We're alongside already." or nil),
            why = not info.ok and info.reason or nil,
            preview = info.route and { kind = "move", route = info.route },
            run = run(function(game)
                if approach then game:cmdApproach(tx, ty) else game:cmdMove(tx, ty) end
            end),
        })
    end

    local function torpedoItem(label, detail)
        local why = g:torpedoCheck()
        add({
            label = label,
            detail = detail or (("%d left  ·  strays up to %.1f°%s"):format(
                g.ship.torps, g:torpedoSpread(), g.ship.up and " with shields up" or "")),
            why = why,
            preview = { kind = "torpedo", x = c.x, y = c.y, spread = g:torpedoSpread() },
            run = function()
                app.pop()
                play:fireTorpedo()
            end,
        })
    end

    local visible = play:visible(c.x, c.y)
    local obj = visible and play:at(c.x, c.y) or nil
    local isShip = c.x == v.x and c.y == v.y
    local where = c.x .. "," .. c.y

    if isShip then
        self.title = g.ship.name
        self.subtitle = "Sector " .. where
        local s = g.ship
        add({
            label = s.up and "Lower shields" or "Raise shields",
            detail = s.up and "Warp costs half as much with shields down." or "Costs 40 energy.",
            why = (not s.up and g:damaged("shield")) and "Shield control is damaged." or nil,
            run = run(function(game) game:cmdShields() end),
        })
        if g:adjacentBase() and not s.docked then
            add({ label = "Dock at the starbase", detail = "Refills energy, shields and torpedoes.",
                  run = run(function(game) game:cmdDock() end) })
        end
        add({
            label = "Rest and repair...", detail = "Let time pass while the crew makes repairs.",
            why = g:restCheck(),
            run = function() app.pop() app.push("rest") end,
        })
        add({ label = "Damage report", detail = "The state of every system.",
              run = function() app.pop() app.push("damage") end })
    elseif obj == C.KLINGON then
        local k = g:klingonAt(c.x, c.y)
        self.title = "Klingon"
        self.subtitle = ("Sector %s  ·  %.1f sectors away"):format(where, g:dist(c.x, c.y))
        torpedoItem("Fire a photon torpedo")
        add({
            label = "Phasers on this Klingon...",
            detail = k and ("About %s energy would destroy it."):format(ui.number(g:phaserNeed(k))) or nil,
            why = g:phaserCheck(),
            run = function()
                app.pop()
                app.push("phasers", { x = c.x, y = c.y })
            end,
        })
        add({
            label = "Demand surrender",
            detail = k and ("About %d%% chance. Weaker ships give up more readily."):format(
                math.floor(g:captureChance(k) * 100 + 0.5)) or nil,
            why = g:captureCheck(),
            run = run(function(game) game:cmdCapture(c.x, c.y) end),
        })
    elseif obj == C.BASE then
        self.title = "Starbase"
        self.subtitle = "Sector " .. where
        if g:adjacentBase() then
            add({
                label = "Dock", detail = "Refills energy, shields and torpedoes, and doubles the repair rate.",
                why = g.ship.docked and "We're already docked." or nil,
                run = run(function(game) game:cmdDock() end),
            })
        else
            moveItem("Approach and dock", c.x, c.y, true)
        end
    elseif obj == C.STAR then
        self.title = "Star"
        self.subtitle = "Sector " .. where
        moveItem("Move alongside", c.x, c.y, true)
        torpedoItem("Fire a torpedo into it", "It will probably nova, destroying everything next to it.")
    elseif obj == C.INHABIT then
        self.title = g:here().sys or "Inhabited system"
        self.subtitle = "Sector " .. where .. "  ·  inhabited"
        moveItem("Move alongside", c.x, c.y, true)
    elseif obj == C.HOLE then
        self.title = "Black hole"
        self.subtitle = "Sector " .. where
        moveItem("Move alongside", c.x, c.y, true)
    else
        self.title = visible and "Empty sector" or "Unknown sector"
        self.subtitle = "Sector " .. where .. (visible and "" or "  ·  beyond scanner range")
        moveItem("Move here", c.x, c.y, false)
        torpedoItem("Fire a torpedo this way")
    end
    self.sel = math.min(self.sel, #items)
    self:updatePreview()
end

function Orders:updatePreview()
    local item = self.items[self.sel]
    self.play.preview = item and not item.why and item.preview or nil
end

function Orders:leave()
    self.play.preview = nil
end

function Orders:update(dt)
    self.t = self.t + dt
end

function Orders:busy()
    return self.t < 0.3
end

function Orders:action(a)
    if a == "up" then
        self.sel = (self.sel - 2) % #self.items + 1
        sound.play("menu")
        self:updatePreview()
    elseif a == "down" then
        self.sel = self.sel % #self.items + 1
        sound.play("menu")
        self:updatePreview()
    elseif a == "a" then
        local item = self.items[self.sel]
        if item.why or not item.run then
            sound.play("error")
        else
            sound.play("open")
            item.run()
        end
    elseif a == "b" or a == "start" then
        sound.play("close")
        self.app.pop()
    end
end

function Orders:draw()
    local p = ui.ease(self.t / 0.14)
    local x, w = self.play.PX - 12, self.play.PW + 24
    local y = 16
    -- measure
    local rowsH = 0
    local heights = {}
    for k, item in ipairs(self.items) do
        local note = item.why or item.detail
        local h = 30
        if note then h = h + ui.wrap(note, 14, "regular", w - 44) end
        heights[k] = h + 8
        rowsH = rowsH + heights[k]
    end
    local h = math.max(404, 74 + rowsH + 40)

    ui.panel(x, y, w, h, p)
    ui.brackets(x - 1, y - 1, w + 2, h + 2, 10, 2, "accent", p)
    theme.set("text", p)
    ui.centered(self.title, x + 18, y + 26, 20, "bold", "left")
    theme.set("muted", p)
    ui.centered(self.subtitle, x + 18, y + 50, 14, "regular", "left")

    local ry = y + 70
    for k, item in ipairs(self.items) do
        local selected = k == self.sel
        local rh = heights[k]
        if selected then
            theme.set("raised", p)
            ui.rect("fill", x + 8, ry, w - 16, rh - 4)
            theme.set("accent", p)
            ui.rect("fill", x + 8, ry, 3, rh - 4)
        end
        theme.set(item.why and "dim" or (selected and "text" or "muted"), p)
        ui.centered(item.label, x + 22, ry + 15, 17, selected and "bold" or "regular", "left")
        local note = item.why or item.detail
        if note then
            theme.set(item.why and "warn" or "muted", p * (selected and 1 or 0.8))
            ui.text(note, x + 22, ry + 26, 14, "regular", "left", w - 44)
        end
        ry = ry + rh
    end

    ui.hints({ { "B", "Back" }, { "A", "Order" } }, x + w - 16, y + h - 22, "right", p, 14)
end

return Orders
