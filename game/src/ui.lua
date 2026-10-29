-- Layout, text and shared drawing helpers.
--
-- The layout is designed on a 720x480 canvas, the RG34XXSP's native screen,
-- where one canvas unit is one screen pixel. Other resolutions scale it
-- uniformly. To keep text crisp:
--
-- * Fonts are rasterized at the real screen pixel size and drawn with the
--   inverse scale, so glyphs are never resampled.
-- * Atkinson Hyperlegible (text) uses FreeType's normal hinting, which snaps
--   stems and heights to the pixel grid.
-- * Departure Mono (the "pixel" face, for readouts and the classic sector
--   letters) is a pixel font drawn on an 11 px grid. It is only ever
--   rasterized at whole multiples of 11 px, with 1-bit ("mono") hinting, so
--   every design pixel becomes an exact block of screen pixels with no
--   blur at all.
-- * Every string starts on a whole screen pixel, and vertical centering is
--   worked out in screen pixels from each font's measured cap height, so
--   baselines land on a pixel row instead of being smeared across two.

local theme = require("src.theme")
local sprites = require("src.sprites")

local ui = { W = 720, H = 480, s = 1, ox = 0, oy = 0 }

local FONT_FILES = {
    regular = "assets/fonts/AtkinsonHyperlegible-Regular.ttf",
    bold = "assets/fonts/AtkinsonHyperlegible-Bold.ttf",
    pixel = "assets/fonts/DepartureMono-Regular.otf",
}
local PIXEL_GRID = 11

local cache = {}
local meta = setmetatable({}, { __mode = "k" }) -- [font] = { px, cap }

function ui.resize(w, h)
    ui.s = math.min(w / ui.W, h / ui.H)
    ui.ox = math.floor((w - ui.W * ui.s) / 2)
    ui.oy = math.floor((h - ui.H * ui.s) / 2)
    cache = {}
    sprites.resize(ui.s)
end

local function load(weight, px)
    local file = FONT_FILES[weight]
    local hinting = (weight == "pixel") and "mono" or "normal"
    -- The drawing code works in screen pixels (see love.draw), so fonts are
    -- made at a DPI scale of 1 and px is the real pixel size.
    local ok, f = pcall(love.graphics.newFont, file, px, hinting, 1)
    if not ok then f = love.graphics.newFont(px) end
    if weight == "pixel" then f:setFilter("nearest", "nearest") end
    -- Measure the real cap height at this size from the rasterizer.
    local cap = math.floor(px * 0.7 + 0.5)
    local okr, r = pcall(love.font.newRasterizer, file, px, hinting, 1)
    if okr then cap = r:getGlyphData("H"):getHeight() end
    meta[f] = { px = px, cap = cap }
    return f
end

-- The font for `size` canvas units in `weight` (regular, bold or pixel).
function ui.font(size, weight)
    weight = weight or "regular"
    local px
    if weight == "pixel" then
        px = math.max(1, math.floor(size * ui.s / PIXEL_GRID + 0.5)) * PIXEL_GRID
    else
        px = math.max(6, math.floor(size * ui.s + 0.5))
    end
    local key = weight .. px
    local f = cache[key]
    if not f then
        f = load(weight, px)
        cache[key] = f
    end
    return f
end

function ui.begin()
    love.graphics.push()
    love.graphics.translate(ui.ox, ui.oy)
    love.graphics.scale(ui.s)
end

function ui.finish()
    love.graphics.pop()
end

-- Round a canvas coordinate to a whole screen pixel.
local function snap(v)
    return math.floor(v * ui.s + 0.5) / ui.s
end
ui.snap = snap

function ui.width(str, size, weight)
    return ui.font(size, weight):getWidth(str) / ui.s
end

function ui.lineHeight(size, weight)
    return ui.font(size, weight):getHeight() / ui.s
end

-- Draw text with its top-left at (x, y). With `align` ("left", "center",
-- "right") the text is wrapped and laid out inside `width`.
function ui.text(str, x, y, size, weight, align, width)
    local f = ui.font(size, weight)
    love.graphics.setFont(f)
    local inv = 1 / ui.s
    if align then
        love.graphics.printf(str, snap(x), snap(y), math.floor(width * ui.s), align, 0, inv, inv)
    else
        love.graphics.print(str, snap(x), snap(y), 0, inv, inv)
    end
end

-- Height of `str` wrapped to `width`, and its lines.
function ui.wrap(str, size, weight, width)
    local f = ui.font(size, weight)
    local _, lines = f:getWrap(str, math.floor(width * ui.s))
    return #lines * f:getHeight() / ui.s, lines
end

-- Top of a line of text whose capitals are centered on cy, in canvas units
-- but on a whole screen pixel.
local function capTop(f, cy)
    local m = meta[f]
    local baseline = math.floor(cy * ui.s + m.cap / 2 + 0.5)
    return (baseline - f:getBaseline()) / ui.s
end

-- Draw text so its capitals are vertically centered on cy. align: "left"
-- (x is the left edge), "center" (x is the middle) or "right". Returns the
-- width in canvas units.
function ui.centered(str, x, cy, size, weight, align)
    local f = ui.font(size, weight)
    love.graphics.setFont(f)
    local s = ui.s
    local wpx = f:getWidth(str)
    local left
    if align == "left" then left = x * s
    elseif align == "right" then left = x * s - wpx
    else left = x * s - wpx / 2 end
    love.graphics.print(str, math.floor(left + 0.5) / s, capTop(f, cy), 0, 1 / s, 1 / s)
    return wpx / s
end

-- Colored text: parts is { slot, "text", slot, "text", ... }, laid out from
-- (x, y) and wrapped to width. Returns the height used.
function ui.colored(parts, x, y, size, weight, width, alpha)
    local f = ui.font(size, weight)
    love.graphics.setFont(f)
    local list, plain = {}, {}
    for k = 1, #parts, 2 do
        list[#list + 1] = theme.rgba(parts[k], alpha)
        list[#list + 1] = parts[k + 1]
        plain[#plain + 1] = parts[k + 1]
    end
    love.graphics.setColor(1, 1, 1, 1)
    local inv = 1 / ui.s
    local wpx = math.floor(width * ui.s)
    love.graphics.printf(list, snap(x), snap(y), wpx, "left", 0, inv, inv)
    local _, lines = f:getWrap(table.concat(plain), wpx)
    return #lines * f:getHeight() / ui.s
end

-- Shapes -------------------------------------------------------------------------

-- Axis-aligned rectangles on whole screen pixels: always crisp.
function ui.rect(mode, x, y, w, h)
    local x1, y1 = snap(x), snap(y)
    local x2, y2 = snap(x + w), snap(y + h)
    if mode == "line" then
        local t = 1 / ui.s * math.max(1, math.floor(ui.s + 0.5))
        love.graphics.rectangle("fill", x1, y1, x2 - x1, t)
        love.graphics.rectangle("fill", x1, y2 - t, x2 - x1, t)
        love.graphics.rectangle("fill", x1, y1, t, y2 - y1)
        love.graphics.rectangle("fill", x2 - t, y1, t, y2 - y1)
    else
        love.graphics.rectangle("fill", x1, y1, x2 - x1, y2 - y1)
    end
end

-- A panel: filled, with a one-pixel border.
function ui.panel(x, y, w, h, alpha, fill)
    theme.set(fill or "panel", alpha)
    ui.rect("fill", x, y, w, h)
    theme.set("line", alpha)
    ui.rect("line", x, y, w, h)
end

-- Corner brackets around a box, the way a targeting display marks things.
function ui.brackets(x, y, w, h, len, thick, slot, alpha)
    theme.set(slot or "accent", alpha)
    thick = thick or 2
    ui.rect("fill", x, y, len, thick)
    ui.rect("fill", x, y, thick, len)
    ui.rect("fill", x + w - len, y, len, thick)
    ui.rect("fill", x + w - thick, y, thick, len)
    ui.rect("fill", x, y + h - thick, len, thick)
    ui.rect("fill", x, y + h - len, thick, len)
    ui.rect("fill", x + w - len, y + h - thick, len, thick)
    ui.rect("fill", x + w - thick, y + h - len, thick, len)
end

-- A horizontal bar showing frac (0-1) of its width.
function ui.bar(x, y, w, h, frac, slot, alpha)
    theme.set("raised", alpha)
    ui.rect("fill", x, y, w, h)
    frac = math.max(0, math.min(1, frac))
    if frac > 0 then
        theme.set(slot, alpha)
        ui.rect("fill", x, y, math.max(1, w * frac), h)
    end
end

-- A capsule (rounded ends) from antialiased half discs, d tall.
local pillQuads = {}
function ui.pill(x, cy, w, d, slot, alpha)
    local img, n = sprites.disc(d)
    local s = ui.s
    local inv = 1 / s
    local top = math.floor((cy - d / 2) * s + 0.5)
    local left = math.floor(x * s + 0.5)
    local right = math.floor((x + w) * s + 0.5)
    local half = n / 2
    theme.set(slot, alpha)
    local q = pillQuads[n]
    if not q then
        q = { love.graphics.newQuad(0, 0, half, n, n, n), love.graphics.newQuad(half, 0, half, n, n, n) }
        pillQuads[n] = q
    end
    love.graphics.draw(img, q[1], left * inv, top * inv, 0, inv, inv)
    love.graphics.draw(img, q[2], (right - half) * inv, top * inv, 0, inv, inv)
    if right - left > n then
        love.graphics.rectangle("fill", (left + half) * inv, top * inv, (right - left - n) * inv, n * inv)
    end
end

function ui.disc(cx, cy, d, slot, alpha)
    local img, n = sprites.disc(d)
    local s = ui.s
    theme.set(slot, alpha)
    love.graphics.draw(img, math.floor(cx * s - n / 2 + 0.5) / s, math.floor(cy * s - n / 2 + 0.5) / s, 0, 1 / s, 1 / s)
end

-- Dim the screen and draw a centered card for menus and dialogs.
function ui.card(w, h, p, x, y)
    p = p or 1
    theme.set("scrim", 0.7 * p)
    love.graphics.rectangle("fill", 0, 0, ui.W, ui.H)
    x = x or math.floor((ui.W - w) / 2)
    y = (y or math.floor((ui.H - h) / 2)) + math.floor((1 - p) * 10)
    ui.panel(x, y, w, h, p)
    ui.brackets(x - 1, y - 1, w + 2, h + 2, 10, 2, "accent", 0.9 * p)
    return x, y
end

-- Controller button glyphs ------------------------------------------------------------

local ROUND = { A = true, B = true, X = true, Y = true }

function ui.glyphWidth(label)
    if ROUND[label] then return 20 end
    return math.floor(ui.width(label, 12, "bold") + 14 + 0.5)
end

-- Draws a button glyph with its left edge at x, centered on cy. Returns width.
function ui.glyph(label, x, cy, alpha)
    local w = ui.glyphWidth(label)
    if ROUND[label] then
        ui.disc(x + 10, cy, 20, "chip", alpha)
        theme.set("chipText", alpha)
        ui.centered(label, x + 10, cy, 13, "bold", "center")
    else
        ui.pill(x, cy, w, 20, "chip", alpha)
        theme.set("chipText", alpha)
        ui.centered(label, x + w / 2, cy, 12, "bold", "center")
    end
    return w
end

-- A row of {button, label} pairs. align "left" starts at x, "right" ends at
-- x, "center" is centered on x. size is the label size (default 15).
function ui.hints(list, x, cy, align, alpha, size)
    size = size or 15
    local gap, inner = 16, 6
    local total = 0
    for k, item in ipairs(list) do
        total = total + ui.glyphWidth(item[1]) + inner + ui.width(item[2], size)
        if k < #list then total = total + gap end
    end
    local cx = (align == "right") and (x - total) or (align == "center" and x - total / 2 or x)
    cx = math.floor(cx + 0.5)
    for _, item in ipairs(list) do
        cx = cx + ui.glyph(item[1], cx, cy, alpha) + inner
        theme.set("muted", alpha)
        cx = cx + ui.centered(item[2], cx, cy, size, "regular", "left") + gap
        cx = math.floor(cx + 0.5)
    end
    return total
end

-- Numbers and easing ---------------------------------------------------------------

function ui.ease(t)
    t = math.max(0, math.min(1, t))
    return 1 - (1 - t) ^ 3
end

-- 49151 -> "49,151"
function ui.number(n)
    local neg = n < 0
    local s = tostring(math.floor(math.abs(n) + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (neg and "-" or "") .. out
end

function ui.one(v)
    return string.format("%.1f", v)
end

return ui
