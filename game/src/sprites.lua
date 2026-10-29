-- Icons rasterized in Lua, once per screen scale, at the exact pixel size
-- they're drawn at. Edges are antialiased per pixel (analytic coverage for
-- round shapes, 4x4 supersampling for polygons). LÖVE's own filled shapes
-- have jagged edges without MSAA, which the handheld's GLES setup can't be
-- counted on for; these stay smooth and land exactly on screen pixels.
--
-- Each icon is a list of white masks, each tinted with a theme slot when
-- drawn, so one set of images serves every theme.

local theme = require("src.theme")

local sprites = { s = 1 }

local sqrt, max, min, floor = math.sqrt, math.max, math.min, math.floor

local function clamp01(v)
    return v < 0 and 0 or (v > 1 and 1 or v)
end

-- Distance from (px, py) to the segment (x1, y1)-(x2, y2).
local function segDist(px, py, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local l2 = dx * dx + dy * dy
    local t = l2 > 0 and clamp01(((px - x1) * dx + (py - y1) * dy) / l2) or 0
    local qx, qy = x1 + dx * t, y1 + dy * t
    return sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
end

local function inPoly(px, py, pts)
    local inside = false
    local n = #pts
    local jx, jy = pts[n - 1], pts[n]
    for i = 1, n, 2 do
        local ix, iy = pts[i], pts[i + 1]
        if (iy > py) ~= (jy > py) and px < (jx - ix) * (py - iy) / (jy - iy) + ix then
            inside = not inside
        end
        jx, jy = ix, iy
    end
    return inside
end

-- Coverage (0-1) of one shape at design point (x, y); pu is the size of a
-- screen pixel in design units.
local function coverage(sh, x, y, pu)
    local kind = sh[1]
    if kind == "disc" then
        local d = sqrt((x - sh[2]) ^ 2 + (y - sh[3]) ^ 2)
        return clamp01((sh[4] - d) / pu + 0.5)
    elseif kind == "ring" then
        local d = sqrt((x - sh[2]) ^ 2 + (y - sh[3]) ^ 2)
        local half = sh[5] / 2
        return clamp01((half - math.abs(d - sh[4])) / pu + 0.5)
    elseif kind == "capsule" then
        return clamp01((sh[6] - segDist(x, y, sh[2], sh[3], sh[4], sh[5])) / pu + 0.5)
    elseif kind == "glow" then
        local d = sqrt((x - sh[2]) ^ 2 + (y - sh[3]) ^ 2)
        return clamp01(1 - d / sh[4]) ^ (sh[5] or 2)
    elseif kind == "spikes" then
        -- a four-pointed sparkle: thin lines fading toward their tips
        local dx, dy = math.abs(x - sh[2]), math.abs(y - sh[3])
        local len, w = sh[4], sh[5]
        local a = clamp01((w - dy) / pu + 0.5) * clamp01(1 - dx / len) ^ 2
        local b = clamp01((w - dx) / pu + 0.5) * clamp01(1 - dy / len) ^ 2
        return max(a, b)
    elseif kind == "poly" then
        local hits = 0
        for i = 0, 3 do
            for j = 0, 3 do
                if inPoly(x + ((i + 0.5) / 4 - 0.5) * pu, y + ((j + 0.5) / 4 - 0.5) * pu, sh[2]) then
                    hits = hits + 1
                end
            end
        end
        return hits / 16
    end
    return 0
end

-- Rasterize a mask: shapes are unioned; shapes in `cut` are removed. With
-- `angle` (degrees, clockwise) the design is drawn rotated about its center,
-- so rotated icons get edges as clean as upright ones.
local function rasterize(n, unit, shapes, cut, angle)
    local pu = unit / n
    local c = unit / 2
    local ca, sa = 1, 0
    if angle and angle ~= 0 then
        ca, sa = math.cos(math.rad(angle)), math.sin(math.rad(angle))
    end
    local data = love.image.newImageData(n, n)
    data:mapPixel(function(px, py)
        local ox, oy = (px + 0.5) * pu - c, (py + 0.5) * pu - c
        local x, y = c + ox * ca + oy * sa, c - ox * sa + oy * ca
        local a = 0
        for _, sh in ipairs(shapes) do
            a = max(a, coverage(sh, x, y, pu))
            if a >= 1 then break end
        end
        if cut and a > 0 then
            for _, sh in ipairs(cut) do a = a * (1 - coverage(sh, x, y, pu)) end
        end
        return 1, 1, 1, a
    end)
    local img = love.graphics.newImage(data)
    img:setFilter("linear", "linear")
    return img
end

-- Icon designs on a 38-unit box (one sector cell), pointing up.
-- Each part: { slot = theme slot, a = alpha, shapes = {...}, cut = {...} }.
local C = 19
local ICONS = {
    ship = {
        { slot = "ship", shapes = {
            { "disc", C, 13.5, 7.5 },
            { "capsule", C, 18, C, 23, 1.7 },
            { "capsule", C, 22, C, 28.5, 3 },
            { "capsule", C, 25.5, 12.5, 27.5, 1.2 },
            { "capsule", C, 25.5, 25.5, 27.5, 1.2 },
            { "capsule", 12.5, 22, 12.5, 33, 2.2 },
            { "capsule", 25.5, 22, 25.5, 33, 2.2 },
        } },
        { slot = "bg", a = 0.55, shapes = { { "ring", C, 13.5, 4.2, 1.2 } } },
    },
    queene = {
        { slot = "ship", shapes = { { "poly", { C, 5, 29, 31, C, 25, 9, 31 } } } },
        { slot = "bg", a = 0.55, shapes = { { "capsule", C, 12, C, 21, 1.2 } } },
    },
    klingon = {
        { slot = "klingon", shapes = {
            { "disc", C, 8.5, 3.4 },
            { "capsule", C, 10, C, 20, 1.7 },
            { "disc", C, 21.5, 4.6 },
            { "poly", { C, 15.5, 34, 20.5, 36.5, 31, 31.5, 27.5, C, 24.5, 6.5, 27.5, 1.5, 31, 4, 20.5 } },
        } },
        { slot = "bg", a = 0.5, shapes = { { "disc", C, 21.5, 1.8 } } },
    },
    base = {
        { slot = "base", a = 0.22, shapes = { { "glow", C, C, 18, 1.6 } } },
        { slot = "base", shapes = {
            { "ring", C, C, 12.5, 2.4 },
            { "disc", C, C, 4.6 },
            { "capsule", C, 7, C, 31, 1 },
            { "capsule", 7, C, 31, C, 1 },
            { "disc", C, 6.5, 2.4 }, { "disc", C, 31.5, 2.4 },
            { "disc", 6.5, C, 2.4 }, { "disc", 31.5, C, 2.4 },
        } },
    },
    star = {
        { slot = "star", a = 0.5, shapes = { { "glow", C, C, 15, 2.2 } } },
        { slot = "star", a = 0.9, shapes = { { "spikes", C, C, 13, 0.6 } } },
        { slot = "star", shapes = { { "disc", C, C, 4.2 } } },
        { slot = "text", a = 0.6, shapes = { { "disc", C, C, 2.2 } } },
    },
    planet = {
        { slot = "planet", a = 0.35, shapes = { { "ring", C, C, 12.5, 1 } } },
        { slot = "planet", shapes = { { "disc", C, C, 8 } } },
        { slot = "bg", a = 0.5, shapes = { { "disc", C, C, 8 } }, cut = { { "disc", 16.2, 16.2, 8.6 } } },
        { slot = "text", a = 0.35, shapes = { { "disc", 15.8, 15.6, 2 } } },
    },
    hole = {
        { slot = "hole", a = 0.35, shapes = { { "glow", C, C, 16, 1.4 } } },
        { slot = "hole", shapes = { { "ring", C, C, 9.5, 3 } } },
        { slot = "bg", shapes = { { "disc", C, C, 7.6 } } },
        { slot = "hole", a = 0.5, shapes = { { "ring", C, C, 7, 0.9 } } },
    },
}

local cache = {}

function sprites.resize(s)
    sprites.s = s
    cache = {}
end

-- The parts of icon `name` at `size` canvas units, drawn at `angle`
-- degrees (rounded to a multiple of 6).
local STEP = 6
function sprites.icon(name, size, angle)
    local n = math.max(2, floor(size * sprites.s + 0.5))
    angle = (floor((angle or 0) / STEP + 0.5) * STEP) % 360
    local key = name .. "@" .. n .. "@" .. angle
    local parts = cache[key]
    if not parts then
        parts = {}
        for k, part in ipairs(ICONS[name]) do
            parts[k] = { img = rasterize(n, 38, part.shapes, part.cut, angle), slot = part.slot, a = part.a or 1 }
        end
        cache[key] = parts
    end
    return parts, n
end

-- Draw icon `name` centered on (cx, cy), `size` canvas units across,
-- turned `rot` degrees clockwise. Still icons are rasterized at their angle;
-- with `moving`, the upright image is rotated by the GPU instead, which is
-- a little softer but costs nothing while something turns or slides.
-- slot overrides the tint of the icon's main part.
function sprites.draw(name, cx, cy, size, rot, alpha, slot, moving)
    rot = rot or 0
    local parts, n = sprites.icon(name, size, moving and 0 or rot)
    local s = sprites.s
    local inv = 1 / s
    -- whole screen pixels for the top-left corner
    local px = (floor(cx * s - n / 2 + 0.5) + n / 2) * inv
    local py = (floor(cy * s - n / 2 + 0.5) + n / 2) * inv
    local r = moving and math.rad(rot) or 0
    for k, p in ipairs(parts) do
        local tint = p.slot
        if slot and tint ~= "bg" and tint ~= "text" then tint = slot end
        theme.set(tint, p.a * (alpha or 1))
        love.graphics.draw(p.img, px, py, r, inv, inv, n / 2, n / 2)
    end
end

-- Plain antialiased discs and rings for the interface, d canvas units across.
local discs = {}
function sprites.disc(d)
    local n = math.max(2, floor(d * sprites.s + 0.5))
    local key = "disc" .. n
    if not discs[key] or discs[key].s ~= sprites.s then
        discs[key] = { s = sprites.s, img = rasterize(n, n, { { "disc", n / 2, n / 2, n / 2 } }) }
    end
    return discs[key].img, n
end

function sprites.ring(d, w)
    local n = math.max(2, floor(d * sprites.s + 0.5))
    local key = "ring" .. n .. ":" .. w
    if not discs[key] or discs[key].s ~= sprites.s then
        local ws = w * sprites.s
        discs[key] = { s = sprites.s, img = rasterize(n, n, { { "ring", n / 2, n / 2, n / 2 - ws / 2, ws } }) }
    end
    return discs[key].img, n
end

return sprites
