-- Sound effects synthesized at startup, so the game ships no audio files.
-- If audio isn't available the game stays silent.

local sound = { enabled = true }

local RATE = 22050
local sources = {}

-- Build a sound from a list of tones:
--   { freq, start, length, volume, shape, endFreq }
-- shape: sine, soft, tri, square, saw or noise (noise uses freq as the
-- cutoff of a simple low-pass filter). endFreq sweeps the pitch.
local function synth(tones, length)
    local samples = math.floor(length * RATE)
    local data = love.sound.newSoundData(samples, RATE, 16, 1)
    local buffer = {}
    for n = 0, samples - 1 do buffer[n] = 0 end
    local rng = love.math.newRandomGenerator(7)
    for _, tone in ipairs(tones) do
        local f0, start, len, vol = tone[1], tone[2], tone[3], tone[4]
        local shape, f1 = tone[5] or "sine", tone[6] or tone[1]
        local s0 = math.floor(start * RATE)
        local count = math.floor(len * RATE)
        local attack = math.max(1, math.floor(0.004 * RATE))
        local phase, lp = 0, 0
        for k = 0, count - 1 do
            local n = s0 + k
            if n >= samples then break end
            local t = k / RATE
            local p = k / count
            local freq = f0 + (f1 - f0) * p
            local env = math.exp(-t * (5.5 / len))
            if k < attack then env = env * (k / attack) end
            phase = phase + freq / RATE
            local x = phase % 1
            local v
            if shape == "soft" then
                v = math.sin(2 * math.pi * x) * 0.8 + math.sin(4 * math.pi * x) * 0.2
            elseif shape == "tri" then
                v = 1 - 4 * math.abs(x - 0.5)
            elseif shape == "square" then
                v = x < 0.5 and 0.6 or -0.6
            elseif shape == "saw" then
                v = (2 * x - 1) * 0.7
            elseif shape == "noise" then
                local a = math.min(1, 2 * math.pi * freq / RATE)
                lp = lp + a * ((rng:random() * 2 - 1) - lp)
                v = lp * 1.6
            else
                v = math.sin(2 * math.pi * x)
            end
            buffer[n] = buffer[n] + v * env * vol
        end
    end
    for n = 0, samples - 1 do
        data:setSample(n, math.max(-1, math.min(1, buffer[n])))
    end
    return data
end

local DEFS = {
    move   = function() return synth({ { 1320, 0, 0.025, 0.08 } }, 0.03) end,
    menu   = function() return synth({ { 990, 0, 0.035, 0.12 } }, 0.04) end,
    open   = function() return synth({ { 740, 0, 0.05, 0.14, "soft" }, { 1110, 0.025, 0.05, 0.09 } }, 0.08) end,
    close  = function() return synth({ { 1110, 0, 0.05, 0.09 }, { 740, 0.025, 0.05, 0.12, "soft" } }, 0.08) end,
    error  = function() return synth({ { 196, 0, 0.12, 0.22, "tri" }, { 185, 0.05, 0.12, 0.16, "tri" } }, 0.18) end,
    msg    = function() return synth({ { 1760, 0, 0.03, 0.05 } }, 0.04) end,
    comms  = function()
        return synth({ { 1568, 0, 0.08, 0.12 }, { 2093, 0.09, 0.08, 0.12 }, { 1568, 0.18, 0.08, 0.12 } }, 0.3)
    end,
    phaser = function()
        return synth({ { 1500, 0, 0.32, 0.18, "saw", 520 }, { 3000, 0, 0.3, 0.06, "sine", 1040 } }, 0.34)
    end,
    torpedo = function()
        return synth({ { 2400, 0, 0.35, 0.22, "noise", 300 }, { 220, 0, 0.3, 0.25, "soft", 70 } }, 0.38)
    end,
    boom   = function()
        return synth({ { 900, 0, 0.7, 0.45, "noise", 120 }, { 80, 0, 0.5, 0.35, "soft", 38 } }, 0.75)
    end,
    small  = function()
        return synth({ { 1400, 0, 0.3, 0.3, "noise", 300 }, { 140, 0, 0.2, 0.2, "soft", 70 } }, 0.32)
    end,
    nova   = function()
        return synth({ { 600, 0, 1.2, 0.45, "noise", 80 }, { 60, 0, 1.0, 0.35, "soft", 30 }, { 1800, 0, 0.4, 0.08, "sine", 900 } }, 1.25)
    end,
    hit    = function()
        return synth({ { 700, 0, 0.22, 0.32, "noise", 200 }, { 110, 0, 0.18, 0.2, "square", 70 } }, 0.25)
    end,
    kfire  = function() return synth({ { 900, 0, 0.18, 0.12, "square", 300 } }, 0.2) end,
    shieldsUp = function() return synth({ { 300, 0, 0.3, 0.16, "soft", 900 }, { 600, 0.04, 0.26, 0.06, "sine", 1800 } }, 0.32) end,
    shieldsDown = function() return synth({ { 900, 0, 0.3, 0.14, "soft", 280 } }, 0.32) end,
    alert  = function()
        return synth({
            { 520, 0.00, 0.26, 0.16, "square", 820 }, { 520, 0.30, 0.26, 0.16, "square", 820 },
        }, 0.6)
    end,
    warp   = function()
        return synth({ { 110, 0, 0.75, 0.26, "saw", 880 }, { 3000, 0, 0.7, 0.1, "noise", 600 } }, 0.8)
    end,
    impulse = function() return synth({ { 160, 0, 0.35, 0.16, "saw", 240 }, { 900, 0, 0.3, 0.06, "noise", 500 } }, 0.38) end,
    dock   = function()
        return synth({
            { 523, 0.00, 0.30, 0.16, "soft" }, { 659, 0.10, 0.30, 0.16, "soft" },
            { 784, 0.20, 0.45, 0.18, "soft" },
        }, 0.7)
    end,
    beam   = function()
        return synth({ { 1200, 0, 0.6, 0.1, "sine", 2400 }, { 1800, 0.05, 0.55, 0.06, "sine", 3600 }, { 4000, 0, 0.5, 0.05, "noise", 2500 } }, 0.65)
    end,
    clear  = function() return synth({ { 784, 0, 0.18, 0.12, "soft" }, { 1047, 0.09, 0.3, 0.12, "soft" } }, 0.42) end,
    cloak  = function() return synth({ { 400, 0, 0.5, 0.14, "soft", 120 }, { 2000, 0, 0.4, 0.05, "noise", 300 } }, 0.52) end,
    win    = function()
        return synth({
            { 523, 0.00, 0.30, 0.18, "soft" }, { 659, 0.13, 0.30, 0.18, "soft" },
            { 784, 0.26, 0.30, 0.18, "soft" }, { 1047, 0.39, 0.80, 0.20, "soft" },
            { 1319, 0.39, 0.80, 0.08 },
        }, 1.3)
    end,
    lose   = function()
        return synth({
            { 392, 0.00, 0.40, 0.18, "soft" }, { 349, 0.25, 0.40, 0.18, "soft" },
            { 311, 0.50, 0.90, 0.18, "soft" }, { 155, 0.50, 0.90, 0.10, "tri" },
        }, 1.5)
    end,
}

function sound.load()
    local ok = pcall(function()
        for name, make in pairs(DEFS) do
            sources[name] = love.audio.newSource(make(), "static")
        end
    end)
    if not ok then sources = {} end
end

function sound.play(name, volume)
    if not sound.enabled then return end
    local src = sources[name]
    if not src then return end
    pcall(function()
        if src:isPlaying() then src = src:clone() end
        src:setVolume(volume or 1)
        src:play()
    end)
end

return sound
