-- Development only: plays through every screen and saves screenshots to the
-- LÖVE save directory. Run with:  RGTREK_AUTOSHOT=1 love game
-- Add RGTREK_LOWDPI=1 on a Retina Mac to get the device's exact 720x480.
-- Screenshots land in shots/ in the save directory
-- (~/Library/Application Support/LOVE/rgtrek on macOS).

local input = require("src.input")
local C = require("src.trek.const")
local Game = require("src.trek.game")

local M = {}

function M.start(app)
    love.filesystem.createDirectory("shots")

    local function press(...)
        for _, a in ipairs({ ... }) do input.handler(a) end
    end
    local function shot(name)
        app.requestRedraw()
        love.graphics.captureScreenshot("shots/" .. name .. ".png")
    end
    local function play() return app.find("play") end

    -- A game with Klingons in the next quadrant over.
    local function setup()
        app.settings.theme, app.settings.display = "space", "modern"
        app.applySettings()
        local g = Game.new({ seed = 20261029, skill = 2, length = 1 })
        g:takeOutput()
        local s = g.ship
        local tx = s.qx < 7 and s.qx + 1 or s.qx - 1
        local q = g:quad(tx, s.qy)
        if q.nova then q.nova = false end
        if q.k == 0 then
            q.k = 3
            g.klings = g.klings + 3
            g.resource = g.klings * g.time
        end
        g.events = {}
        app.game = g
        app.saveGame()
        return g, tx
    end

    local target
    local steps = {
        function() return 2.4 end,
        function() shot("01_title") end,
        function() press("a") return 0.4 end,
        function() shot("02_newgame") end,
        function()
            local _, tx = setup()
            target = tx
            app.setScene("play")
            return 0.6
        end,
        function() shot("03_bridge") end,
        function() press("a") return 0.4 end,
        function() shot("04_orders_ship") end,
        function() press("b", "left", "left", "up", "a") return 0.4 end,
        function() shot("05_orders_move") end,
        function() press("b", "select") return 0.4 end,
        function()
            -- a mid-mission chart: some of the galaxy already scanned
            local g = app.game
            for _, q in ipairs({ { 1, 1 }, { 2, 1 }, { 1, 5 }, { 2, 5 }, { 2, 6 }, { 5, 5 }, { 6, 5 }, { 6, 6 }, { 5, 0 }, { 6, 1 } }) do
                if g:quad(q[1], q[2]) then g:remember(q[1], q[2]) end
            end
            local chart = app.top()
            chart.cursor.x = target
            chart:refresh()
            return 0.3
        end,
        function() shot("06_chart") end,
        function() press("r1", "a") return 0.35 end,
        function() shot("07_warp") return 2.6 end,
        function() shot("08_red_alert") end,
        function() press("a") return 0.4 end,
        function() shot("09_orders_klingon") end,
        function() press("b", "x") return 0.4 end,
        function() shot("10_phasers") end,
        function() press("b", "y") return 0.2 end,
        function() shot("11_torpedo") return 0.35 end,
        function() shot("12_torpedo_hit") return 2.5 end,
        function() shot("13_combat_log") end,
        function()
            local g = app.game
            g.dmg.phaser, g.dmg.lrscan, g.dmg.warp = 1.4, 0.6, 2.2
            press("start")
            return 0.4
        end,
        function() shot("14_shipmenu") end,
        function() press("b") app.push("damage") return 0.4 end,
        function() shot("15_damage") end,
        function() press("b") app.push("log") return 0.4 end,
        function() shot("16_log") end,
        function() press("b") return 0.3 end,
        function()
            app.settings.display = "classic"
            app.applySettings()
            app.requestRedraw()
            return 0.3
        end,
        function() shot("17_classic") end,
        function()
            app.settings.theme = "phosphor"
            app.applySettings()
            return 0.3
        end,
        function() shot("18_phosphor") end,
        function()
            app.settings.theme, app.settings.display = "amber", "modern"
            app.applySettings()
            return 0.3
        end,
        function() shot("19_amber") end,
        function()
            app.settings.theme = "space"
            app.applySettings()
            app.saveSettings()
            press("select")
            return 0.4
        end,
        function() shot("20_chart_damaged") end,
        function() press("b") app.push("shipmenu", "emergency") return 0.4 end,
        function() shot("21_emergency") end,
        function() press("b") app.push("rest") return 0.4 end,
        function() shot("21b_rest") end,
        function() press("b") return 0.3 end,
        function() app.push("help") return 0.3 end,
        function() shot("22_help") end,
        function() press("right") return 0.2 end,
        function() shot("23_help_controls") end,
        function() press("b") app.push("settings") return 0.3 end,
        function() shot("24_settings") end,
        function()
            press("b")
            -- win the game: one Klingon left, right in front of us
            local g = app.game
            for i = 1, C.NQUADS * C.NQUADS do
                if g.quads[i] ~= g:here() then g.quads[i].k = 0 end
            end
            for i = #g.kl, 2, -1 do
                g:put(g.kl[i].x, g.kl[i].y, C.EMPTY)
                table.remove(g.kl, i)
            end
            g:here().k = #g.kl
            g.klings = #g.kl
            g:updateTime()
            g.rng.float = function() return 0.5 end
            local k = g.kl[1]
            if k then
                k.power = 1
                local p = play()
                p.view = g:snapshot()
                p.cursor.x, p.cursor.y = k.x, k.y
                press("y")
            end
            return 3.4
        end,
        function() shot("25_gameover") end,
        function() press("a") return 0.6 end,
        function() shot("26_records") end,
    }

    local origUpdate = love.update
    local t, idx, waitUntil = 0, 1, 0
    love.update = function(dt)
        origUpdate(dt)
        t = t + dt
        if t >= waitUntil then
            if idx <= #steps then
                local step = steps[idx]
                idx = idx + 1
                waitUntil = t + (step() or 0.15)
            else
                love.event.quit()
            end
        end
    end
end

return M
