-- Development only: presses random buttons through every screen for a while
-- to shake out errors in the interface. Run with:
--   RGTREK_FUZZ=60 love game        (seconds to run, default 60)
-- Errors are printed with a traceback and the game exits with status 1.

local input = require("src.input")
local C = require("src.trek.const")

local M = {}

local ACTIONS = {
    { "up", 8 }, { "down", 8 }, { "left", 8 }, { "right", 8 },
    { "a", 10 }, { "b", 6 }, { "x", 4 }, { "y", 5 },
    { "l1", 3 }, { "r1", 3 }, { "select", 2 }, { "start", 2 },
}

function M.start(app, seconds)
    seconds = tonumber(seconds) or 60
    local total = 0
    for _, a in ipairs(ACTIONS) do total = total + a[2] end
    local rng = love.math.newRandomGenerator(os.time())
    local function pick()
        local r = rng:random() * total
        for _, a in ipairs(ACTIONS) do
            r = r - a[2]
            if r <= 0 then return a[1] end
        end
        return "a"
    end

    love.errorhandler = function(msg)
        print("FUZZ ERROR: " .. tostring(msg))
        print(debug.traceback("", 2))
        os.exit(1)
    end

    app.settings.speed = "fast"
    local t, next, presses, games = 0, 0, 0, 0
    local origUpdate = love.update
    love.update = function(dt)
        local ok, err = xpcall(function() origUpdate(dt) end, debug.traceback)
        if not ok then
            print("FUZZ ERROR in update: " .. err)
            os.exit(1)
        end
        t = t + dt
        if t > seconds then
            print(("fuzz: %d presses, %d games started, no errors"):format(presses, games))
            love.event.quit()
            return
        end
        if t < next then return end
        next = t + 0.03
        local top = app.top()
        -- keep the game going: start missions from the title, leave the
        -- quit item alone
        if top.name == "title" then
            if not app.hasGame() then
                games = games + 1
                app.newGame(1 + rng:random(0, 5), ({ 1, 2, 4 })[rng:random(1, 3)])
            else
                app.setScene("play")
            end
            return
        end
        if top.name == "newgame" or top.name == "records" or top.name == "help" then
            input.handler("b")
            return
        end
        -- a fresh mission every so often, so more situations come up
        if presses > 0 and presses % 500 == 0 and top.name ~= "gameover" then
            games = games + 1
            app.settings.theme = ({ "space", "phosphor", "amber" })[rng:random(1, 3)]
            app.applySettings()
            app.newGame(1 + rng:random(0, 5), ({ 1, 2, 4 })[rng:random(1, 3)])
            presses = presses + 1
            return
        end
        -- now and then, stir up the ship's state
        local g = app.game
        if g and not g.over and rng:random() < 0.01 then
            local d = C.DEVICES[rng:random(1, #C.DEVICES)]
            g.dmg[d.key] = rng:random() * 2
        end
        if g and not g.over and rng:random() < 0.003 then
            app.settings.display = app.settings.display == "classic" and "modern" or "classic"
        end
        local a = pick()
        -- Save and exit / Quit would end the run early
        if top.name == "shipmenu" and a == "a" and top.items[top.sel] and top.items[top.sel].label == "Save and exit" then
            a = "b"
        end
        presses = presses + 1
        local ok, err = xpcall(function() input.handler(a) end, debug.traceback)
        if not ok then
            print(("FUZZ ERROR on '%s' in %s: %s"):format(a, top.name, err))
            os.exit(1)
        end
    end

    local origDraw = love.draw
    love.draw = function()
        local ok, err = xpcall(origDraw, debug.traceback)
        if not ok then
            print("FUZZ ERROR in draw (" .. app.top().name .. "): " .. err)
            os.exit(1)
        end
    end
end

return M
