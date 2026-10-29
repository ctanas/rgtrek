-- A fixed background starfield, and warp streaks for travel.

local ui = require("src.ui")
local theme = require("src.theme")

local starfield = {}

local stars = {}
do
    local rng = love.math.newRandomGenerator(1977)
    for i = 1, 150 do
        stars[i] = {
            x = rng:random() * ui.W, y = rng:random() * ui.H,
            b = 0.12 + rng:random() ^ 3 * 0.6,
            big = rng:random() < 0.1,
            angle = rng:random() * math.pi * 2,
            r = rng:random(),
        }
    end
end

-- Stars as single (or double) screen pixels, never blurred.
function starfield.draw(alpha)
    local s = ui.s
    local px = math.max(1, math.floor(s + 0.5)) / s
    for _, st in ipairs(stars) do
        theme.set("text", st.b * (alpha or 1))
        local size = st.big and px * 2 or px
        love.graphics.rectangle("fill", ui.snap(st.x), ui.snap(st.y), size, size)
    end
end

-- Clip the segment (x1,y1)-(x2,y2) to a box (Liang-Barsky). Returns nil if
-- it's outside.
local function clip(x1, y1, x2, y2, bx, by, bw, bh)
    local t0, t1 = 0, 1
    local dx, dy = x2 - x1, y2 - y1
    local p = { -dx, dx, -dy, dy }
    local q = { x1 - bx, bx + bw - x1, y1 - by, by + bh - y1 }
    for i = 1, 4 do
        if p[i] == 0 then
            if q[i] < 0 then return nil end
        else
            local r = q[i] / p[i]
            if p[i] < 0 then
                if r > t1 then return nil end
                if r > t0 then t0 = r end
            else
                if r < t0 then return nil end
                if r < t1 then t1 = r end
            end
        end
    end
    return x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy
end
starfield.clip = clip

-- Streaks flying past along `heading` (degrees), inside a box. k (0-1) is
-- how strong the effect is; t is time, for the motion.
function starfield.streaks(bx, by, bw, bh, heading, k, t)
    local rad = math.rad(heading or 0)
    local ux, uy = math.sin(rad), -math.cos(rad)
    local nx, ny = -uy, ux
    local cx, cy = bx + bw / 2, by + bh / 2
    local span = math.sqrt(bw * bw + bh * bh)
    love.graphics.setLineWidth(1.5)
    for i, st in ipairs(stars) do
        if i > 60 then break end
        local off = (st.r - 0.5) * span
        local along = ((st.x / ui.W + t * (1.2 + st.b * 2.5)) % 1 - 0.5) * span
        local len = (12 + 90 * st.b) * k
        -- streaks move against the heading, as the ship flies forward
        local x2, y2 = cx + nx * off - ux * along, cy + ny * off - uy * along
        local x1, y1 = x2 + ux * len, y2 + uy * len
        local a, b, c, d = clip(x1, y1, x2, y2, bx, by, bw, bh)
        if a then
            theme.set("text", (0.25 + st.b) * k)
            love.graphics.line(a, b, c, d)
        end
    end
end

return starfield
