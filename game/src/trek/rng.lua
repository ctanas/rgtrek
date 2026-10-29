-- A small seeded random number generator (Park-Miller "minimal standard").
-- The state is one number, so it saves with the game, and the arithmetic is
-- exact in both LuaJIT (doubles) and Lua 5.4 (integers), so tests and the
-- device give the same results for the same seed.

local Rng = {}
Rng.__index = Rng

local M = 2147483647

function Rng.new(seed)
    local s = math.floor(tonumber(seed) or 1) % M
    if s <= 0 then s = s + M - 1 end
    return setmetatable({ s = s }, Rng)
end

-- Float in [0, 1).
function Rng:float()
    self.s = (self.s * 16807) % M
    return (self.s - 1) / (M - 1)
end

-- Integer in 0 .. n-1, like BSD trek's ranf(n).
function Rng:int(n)
    if n <= 1 then return 0 end
    return math.floor(self:float() * n)
end

-- Exponentially distributed value with the given mean, like expran().
function Rng:expo(mean)
    return -mean * math.log(1 - self:float() * 0.999)
end

function Rng:chance(p)
    return self:float() < p
end

return Rng
