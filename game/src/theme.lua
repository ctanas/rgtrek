-- Color themes. Deep Space is the default: near-black navy with an amber
-- cursor (a nod to MustardOS). Phosphor and Amber are monochrome, after the
-- terminals BSD trek was first played on.

local theme = {}

local function hex(s)
    s = s:gsub("#", "")
    return {
        tonumber(s:sub(1, 2), 16) / 255,
        tonumber(s:sub(3, 4), 16) / 255,
        tonumber(s:sub(5, 6), 16) / 255,
    }
end

local PALETTES = {
    space = {
        name = "Deep Space",
        bg = "#070B16",        -- screen background
        panel = "#0E1528",     -- panels and cards
        raised = "#16213D",    -- selected rows
        line = "#22305A",      -- panel borders
        grid = "#141D36",      -- sector grid lines
        dot = "#2C3C66",       -- empty sector dots
        text = "#E6ECF7",
        muted = "#8C9CC2",
        dim = "#56658C",
        accent = "#FFC24B",    -- cursor, selections
        accentText = "#1A1200",
        good = "#4FD98A",
        warn = "#FFC24B",
        bad = "#FF5A5F",
        info = "#5CC8FF",
        ship = "#E6ECF7",
        klingon = "#FF5A5F",
        base = "#5CC8FF",
        star = "#FFE2A0",
        planet = "#55D6A8",
        hole = "#A07CFF",
        phaser = "#FFB547",
        torpedo = "#FF9A4D",
        kfire = "#FF4D6A",
        shield = "#5CC8FF",
        scrim = "#02040A",
        chip = "#24314F",      -- button glyph fill
        chipText = "#E6ECF7",
        helm = "#5CC8FF",
        tactical = "#FF8A65",
        science = "#B39DFF",
        comms = "#4FD98A",
        engineering = "#FFC24B",
        medical = "#FF7FA8",
        computer = "#E6ECF7",
    },
    phosphor = {
        name = "Phosphor",
        bg = "#020804",
        panel = "#051209",
        raised = "#0A2212",
        line = "#124A22",
        grid = "#0A2111",
        dot = "#155C2B",
        text = "#8CFFA8",
        muted = "#4FB86A",
        dim = "#2E7A44",
        accent = "#D8FFE1",
        accentText = "#031006",
        good = "#B4FFC6",
        warn = "#D8FFE1",
        bad = "#F2FFF5",
        info = "#8CFFA8",
        ship = "#D8FFE1",
        klingon = "#F2FFF5",
        base = "#8CFFA8",
        star = "#4FB86A",
        planet = "#6BE08A",
        hole = "#2E7A44",
        phaser = "#D8FFE1",
        torpedo = "#B4FFC6",
        kfire = "#F2FFF5",
        shield = "#8CFFA8",
        scrim = "#010402",
        chip = "#0F3A1C",
        chipText = "#B4FFC6",
        helm = "#B4FFC6",
        tactical = "#D8FFE1",
        science = "#8CFFA8",
        comms = "#B4FFC6",
        engineering = "#D8FFE1",
        medical = "#8CFFA8",
        computer = "#F2FFF5",
    },
    amber = {
        name = "Amber",
        bg = "#0A0600",
        panel = "#140C02",
        raised = "#261705",
        line = "#4D300A",
        grid = "#241603",
        dot = "#5C3B0E",
        text = "#FFC56B",
        muted = "#B8863A",
        dim = "#7A5420",
        accent = "#FFE9BF",
        accentText = "#140C02",
        good = "#FFD999",
        warn = "#FFE9BF",
        bad = "#FFF6E5",
        info = "#FFC56B",
        ship = "#FFE9BF",
        klingon = "#FFF6E5",
        base = "#FFC56B",
        star = "#B8863A",
        planet = "#E0A852",
        hole = "#7A5420",
        phaser = "#FFE9BF",
        torpedo = "#FFD999",
        kfire = "#FFF6E5",
        shield = "#FFC56B",
        scrim = "#050300",
        chip = "#4D300A",
        chipText = "#FFD999",
        helm = "#FFD999",
        tactical = "#FFE9BF",
        science = "#FFC56B",
        comms = "#FFD999",
        engineering = "#FFE9BF",
        medical = "#FFC56B",
        computer = "#FFF6E5",
    },
}

theme.ORDER = { "space", "phosphor", "amber" }

local compiled = {}
for key, palette in pairs(PALETTES) do
    local c = { name = palette.name }
    for k, v in pairs(palette) do
        if k ~= "name" then c[k] = hex(v) end
    end
    compiled[key] = c
end

theme.current = compiled.space
theme.key = "space"

function theme.use(key)
    if compiled[key] then
        theme.current = compiled[key]
        theme.key = key
    end
end

function theme.name(key)
    return compiled[key] and compiled[key].name or key
end

-- Set the draw color from a theme slot, with optional alpha.
function theme.set(slot, alpha)
    local c = theme.current[slot]
    love.graphics.setColor(c[1], c[2], c[3], alpha or 1)
end

-- Blend two theme slots (t = 0 gives a, 1 gives b).
function theme.mix(a, b, t, alpha)
    local ca, cb = theme.current[a], theme.current[b]
    love.graphics.setColor(
        ca[1] + (cb[1] - ca[1]) * t,
        ca[2] + (cb[2] - ca[2]) * t,
        ca[3] + (cb[3] - ca[3]) * t,
        alpha or 1)
end

function theme.get(slot)
    return theme.current[slot]
end

-- A slot's color as a {r, g, b, a} table, for colored text.
function theme.rgba(slot, alpha)
    local c = theme.current[slot]
    return { c[1], c[2], c[3], alpha or 1 }
end

return theme
