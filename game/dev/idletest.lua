-- Development only: checks that the screen stops redrawing when nothing is
-- happening. Run with:  RGTREK_IDLETEST=1 love game
-- Starts a mission, waits for animations to finish, then counts frames
-- drawn over 6 idle seconds (ideally 0; 360 would mean no idle saving).

local M = {}

function M.start(app)
    local phase, t, start = "settle", 0, 0
    local origUpdate = love.update
    app.newGame(2, 1)
    love.update = function(dt)
        origUpdate(dt)
        t = t + dt
        if phase == "settle" and t > 2 then
            phase, t, start = "measure", 0, app.framesDrawn
        elseif phase == "measure" and t > 6 then
            print(("idle test: %d frames drawn in 6 idle seconds"):format(app.framesDrawn - start))
            love.event.quit()
        end
    end
end

return M
