-- Combat and catastrophes: Klingon attacks and movement, damage to the
-- ship, novas, supernovas, ramming and black holes. After BSD trek's
-- attack.c, klmove.c, nova.c, snova.c and ram.c.

local C = require("src.trek.const")

local NS, NQ = C.NSECTS, C.NQUADS
local floor, sqrt = math.floor, math.sqrt

local NAMES = {
    [C.STAR] = "A star", [C.BASE] = "The starbase", [C.KLINGON] = "A Klingon",
    [C.INHABIT] = "A planet", [C.HOLE] = "A black hole",
}

return function(Game)
    local round = Game.round

    Game.OBJECT_NAMES = NAMES

    -- Damage ------------------------------------------------------------------

    function Game:damageDevice(key, days)
        local s = self.ship
        if key == "cloak" and not s.hasCloak then return end
        self.dmg[key] = self.dmg[key] + math.max(0.1, days)
        self:say("Engineering", ("%s damaged. Repairs: %.1f days."):format(C.DEVICE[key].name, self.dmg[key]), "bad")
        if key == "shield" and s.up then
            s.up = false
            self:say("Tactical", "Shields are down!", "bad")
            self:fx("shields", { up = false, stats = self:shipStats() })
        elseif key == "cloak" and s.cloaked then
            s.cloaked, s.cloakGood = false, false
            self:say("Helm", "We've lost the cloak!", "bad")
            self:fx("cloak", { on = false, stats = self:shipStats() })
        end
    end

    -- Pick a device by the critical-hit probabilities.
    function Game:randomDevice()
        local roll = self.rng:int(1000)
        for _, d in ipairs(C.DEVICES) do
            roll = roll - d.prob
            if roll < 0 then return d.key end
        end
        return "shield"
    end

    -- Shields soak up part of a hit in proportion to their charge (less
    -- while they're being raised or lowered). Returns what gets through
    -- and what the shields took.
    function Game:absorb(hit, chg)
        local s = self.ship
        if not (s.up or self.shieldChange) then return hit, 0 end
        local absorbed = (s.shield / self.p.shield) * (chg or 1) * hit
        if absorbed > s.shield then absorbed = s.shield end
        s.shield = s.shield - absorbed
        return hit - absorbed, absorbed
    end

    -- Klingons ------------------------------------------------------------------

    -- Every Klingon in the quadrant with power left fires at the ship.
    function Game:klingonsAttack()
        if #self.kl == 0 or self.over then return end
        local s, rng, p = self.ship, self.rng, self.p
        if s.cloaked and s.cloakGood then
            self:klingonsMove(false)
            return
        end
        self:klingonsMove(true)
        if s.docked then
            self:say("Tactical", "The starbase's shields protect us.")
            return
        end
        local chg = self.shieldChange and (0.25 + 0.5 * rng:float()) or 1
        local maxhit, total = 0, 0
        for _, k in ipairs(self.kl) do
            if k.power >= 20 then
                local d = self:dist(k.x, k.y)
                local hit = floor(k.power * (0.90 + 0.01 * rng:float()) ^ d * 0.5)
                k.power = k.power * 0.8 * (1 + (rng:float() - 0.5) * 0.2)
                local eff, absorbed = self:absorb(hit, chg)
                eff = floor(eff + 0.5)
                s.energy = s.energy - eff
                self:fx("kfire", { x = k.x, y = k.y, hit = hit, eff = eff, stats = self:shipStats() })
                local text = ("Hit from %d,%d: %d units"):format(k.x, k.y, hit)
                if absorbed > 0 and eff > 0 then
                    text = text .. (". Shields took %d."):format(floor(absorbed + 0.5))
                elseif absorbed > 0 then
                    text = text .. ", all absorbed by shields."
                else
                    text = text .. "."
                end
                self:say("Tactical", text, eff > 0 and "bad" or "warn")
                if eff >= (15 - self.skill) * (25 - rng:int(12)) then
                    self:say("Tactical", "Critical hit!", "alert")
                    self:fx("shake", { amount = 5 })
                    local key = self:randomDevice()
                    self:damageDevice(key, eff * p.damfac / (75 + rng:int(25)) + 0.5)
                end
                total = total + eff
                if eff > maxhit then maxhit = eff end
                if s.energy <= 0 then return self:lose("destroyed") end
            end
        end
        if maxhit >= 200 or total >= 500 then
            local cas = floor(total * 0.015 * rng:float())
            if cas >= 2 then
                s.crew = s.crew - cas
                self.stats.deaths = self.stats.deaths + cas
                self:say("Medical", ("We suffered %d casualties in that attack."):format(cas), "bad")
                if s.crew <= 0 then return self:lose("crew") end
            end
        end
        self:klingonsMove(false)
    end

    -- Klingons close in before firing and move about afterwards. Badly
    -- hurt ones may run for it.
    function Game:klingonsMove(before)
        local s, rng = self.ship, self.rng
        local hidden = s.cloaked and s.cloakGood
        for i = #self.kl, 1, -1 do
            local k = self.kl[i]
            local prob = before and 0.4 or (0.25 + 0.05 * self.skill)
            if k and rng:float() < prob then
                local dx, dy, steps
                local flee = not before and k.power < self.p.klingpwr * 0.25 and rng:float() < 0.35
                if flee and not hidden then
                    dx, dy, steps = k.x - s.x, k.y - s.y, 4 + rng:int(3)
                elseif before and not hidden then
                    dx, dy = s.x - k.x, s.y - k.y
                    steps = math.min(rng:int(2) + 1, floor(self:dist(k.x, k.y)) - 1)
                else
                    local a = rng:float() * 2 * math.pi
                    dx, dy, steps = math.cos(a), math.sin(a), rng:int(3) + 1
                end
                if steps > 0 then self:klingonStep(k, i, dx, dy, steps, flee) end
            end
        end
    end

    -- Walk Klingon k up to `steps` sectors along (dx, dy), stopping before
    -- anything in the way. A fleeing Klingon that reaches the edge leaves.
    function Game:klingonStep(k, i, dx, dy, steps, flee)
        local len = sqrt(dx * dx + dy * dy)
        if len < 1e-6 then return end
        dx, dy = dx / len, dy / len
        local bx, by = k.x, k.y
        for t = 0.25, steps, 0.25 do
            local nx, ny = round(k.x + dx * t), round(k.y + dy * t)
            if nx ~= bx or ny ~= by then
                if nx < 0 or ny < 0 or nx >= NS or ny >= NS then
                    if flee and self:klingonLeaves(k, i, bx, by, nx, ny) then return end
                    break
                end
                if self:at(nx, ny) ~= C.EMPTY then break end
                bx, by = nx, ny
            end
        end
        if bx ~= k.x or by ~= k.y then
            self:fx("kmove", { x = k.x, y = k.y, tx = bx, ty = by })
            self:put(k.x, k.y, C.EMPTY)
            self:put(bx, by, C.KLINGON)
            k.x, k.y = bx, by
        end
    end

    -- A Klingon at the edge of the quadrant escapes into the next one.
    function Game:klingonLeaves(k, i, ex, ey, ox, oy)
        local s = self.ship
        local qx = s.qx + (ox < 0 and -1 or (ox >= NS and 1 or 0))
        local qy = s.qy + (oy < 0 and -1 or (oy >= NS and 1 or 0))
        local q = self:quad(qx, qy)
        if not q or q.nova or q.k >= C.MAXKLQUAD then return false end
        self:fx("kmove", { x = k.x, y = k.y, tx = ex, ty = ey, leave = true })
        self:put(k.x, k.y, C.EMPTY)
        table.remove(self.kl, i)
        local here = self:here()
        here.k = here.k - 1
        q.k = q.k + 1
        self:say("Science", ("The Klingon at %d,%d fled to quadrant %d,%d."):format(k.x, k.y, qx, qy), "warn")
        if here.k == 0 then self:quadrantCleared() end
        return true
    end

    -- Remove a Klingon. how: nil (destroyed), "captured", or "quiet" when the
    -- caller has already said what happened.
    function Game:killKlingon(k, how)
        local _, i = self:klingonAt(k.x, k.y)
        if not i then return end
        table.remove(self.kl, i)
        local q = self:here()
        q.k = q.k - 1
        self.klings = self.klings - 1
        if how == "captured" then
            self.stats.captured = self.stats.captured + 1
            self:fx("beam", { x = k.x, y = k.y })
        else
            self.stats.killed = self.stats.killed + 1
            self:fx("boom", { x = k.x, y = k.y, size = 1 })
            if how ~= "quiet" then
                self:say("Tactical", ("Klingon at %d,%d destroyed."):format(k.x, k.y), "good")
            end
        end
        self:set(k.x, k.y, C.EMPTY)
        self:updateTime()
        if q.k == 0 then self:quadrantCleared() end
        if self.klings <= 0 then self:win() end
    end

    -- The last Klingon here is gone: sieges and enslavements end.
    function Game:quadrantCleared()
        local q = self:here()
        if q.attacked then
            q.attacked, q.distress = nil, nil
            self:say("Comms", "The starbase thanks us. The siege is broken.", "good")
        end
        if q.enslaved then
            q.enslaved, q.distress = nil, nil
            self:say("Comms", ("%s is free!"):format(q.sys or "The planet"), "good")
        end
        if self.klings > 0 then self:fx("sound", { name = "clear" }) end
    end

    -- Starbases and planets --------------------------------------------------------

    function Game:removeBase(qx, qy)
        for i, b in ipairs(self.bases) do
            if b.x == qx and b.y == qy then
                table.remove(self.bases, i)
                break
            end
        end
        local q = self:quad(qx, qy)
        q.b, q.attacked, q.distress = 0, nil, (q.enslaved and q.distress) or nil
        if q.known then q.known.b = 0 end
    end

    function Game:destroyBase(x, y, byUs)
        local s = self.ship
        self:fx("boom", { x = x, y = y, size = 2 })
        self:set(x, y, C.EMPTY)
        self:removeBase(s.qx, s.qy)
        if byUs then
            self.stats.basesKilled = self.stats.basesKilled + 1
            self:say("Tactical", "We destroyed the starbase!", "bad")
        else
            self.stats.basesLost = self.stats.basesLost + 1
            self:say("Tactical", "The starbase has been destroyed.", "bad")
        end
        if s.docked then s.docked = false end
    end

    function Game:destroySystem(x, y)
        local q = self:here()
        self:fx("boom", { x = x, y = y, size = 2 })
        self:set(x, y, C.EMPTY)
        self.stats.inhab = self.stats.inhab + 1
        self:say("Science", ("We destroyed the inhabited system %s!"):format(q.sys or ""), "bad")
        q.sys, q.enslaved, q.distress = nil, nil, (q.attacked and q.distress) or nil
    end

    -- Novas and supernovas ------------------------------------------------------------

    -- A star hit by a torpedo novas, destroying what's next to it. Stars
    -- next to it nova too.
    function Game:nova(x, y, depth)
        depth = depth or 0
        local rng = self.rng
        if rng:float() < 0.15 then
            self:say("Science", ("The star at %d,%d failed to nova."):format(x, y))
            return
        end
        if depth == 0 and rng:float() < 0.057 then
            self:say("Science", ("The star at %d,%d is going supernova!"):format(x, y), "alert")
            self:fx("supernova", { x = x, y = y })
            return self:supernova(self.ship.qx, self.ship.qy, true)
        end
        self:say("Science", ("The star at %d,%d novas!"):format(x, y), "warn")
        self:fx("nova", { x = x, y = y })
        self:set(x, y, C.EMPTY)
        local q = self:here()
        q.s = q.s - 1
        self.stats.stars = self.stats.stars + 1
        for dy = -1, 1 do
            for dx = -1, 1 do
                if (dx ~= 0 or dy ~= 0) and not self.over then
                    local nx, ny = x + dx, y + dy
                    local obj = self:at(nx, ny)
                    if obj == C.STAR then
                        self:nova(nx, ny, depth + 1)
                    elseif obj == C.KLINGON then
                        self:say("Science", ("The nova destroyed the Klingon at %d,%d."):format(nx, ny), "good")
                        self:killKlingon(self:klingonAt(nx, ny), "quiet")
                    elseif obj == C.BASE then
                        self:destroyBase(nx, ny, true)
                    elseif obj == C.INHABIT then
                        self:destroySystem(nx, ny)
                    elseif obj == C.SHIP or obj == C.QUEENE then
                        self:novaHitsShip(dx, dy)
                    end
                end
            end
        end
    end

    -- The ship takes a nova blast and is pushed one sector away.
    function Game:novaHitsShip(dx, dy)
        local s, rng = self.ship, self.rng
        local hit = 200 + rng:int(300)
        local eff = floor(self:absorb(hit) + 0.5)
        s.energy = s.energy - eff
        self:fx("shake", { amount = 7 })
        self:say("Tactical", ("The nova hit us for %d units."):format(eff), "bad")
        if s.energy <= 0 then return self:lose("suicide") end
        self:damageDevice(self:randomDevice(), 0.5 + rng:float() * 2)
        local nx, ny = s.x + dx, s.y + dy
        if self:at(nx, ny) == C.EMPTY then
            self:fx("move", { x = s.x, y = s.y, tx = nx, ty = ny, heading = s.heading, push = true })
            self:put(s.x, s.y, C.EMPTY)
            s.x, s.y = nx, ny
            self:put(nx, ny, s.kind)
        end
    end

    -- Everything in quadrant (qx, qy) is destroyed and the quadrant can't be
    -- entered again. byUs gives credit (and blame) to the captain.
    function Game:supernova(qx, qy, byUs)
        local q = self:quad(qx, qy)
        local s, st = self.ship, self.stats
        local here = (qx == s.qx and qy == s.qy)
        if q.k > 0 then
            self.klings = self.klings - q.k
            if byUs then st.killed = st.killed + q.k end
            q.k = 0
        end
        if q.b > 0 then
            self:removeBase(qx, qy)
            if byUs then st.basesKilled = st.basesKilled + 1 else st.basesLost = st.basesLost + 1 end
            if here or self:radioOK() then
                self:say("Comms", ("The starbase in quadrant %d,%d was lost in the supernova."):format(qx, qy), "bad")
            end
        end
        if q.sys and byUs then st.inhab = st.inhab + 1 end
        q.sys, q.enslaved, q.attacked, q.distress = nil, nil, nil, nil
        q.nova, q.s, q.h = true, 0, 0
        if q.known then self:remember(qx, qy) end
        self:updateTime()
        if here then
            self.kl = {}
            for i = 1, NS * NS do
                if self.sect[i] ~= s.kind then self.sect[i] = C.EMPTY end
            end
            self:fx("sync", { snap = self:snapshot() })
            if s.docked then s.docked = false end
            self:emergencyEscape()
        end
        if self.klings <= 0 then self:win() end
    end

    -- The computer hurls the ship out of a supernova, if the warp drive works.
    function Game:emergencyEscape()
        local s, rng = self.ship, self.rng
        self:say("Helm", "Emergency override: the computer is engaging the warp drive!", "alert")
        if self:damaged("warp") then return self:lose("snova") end
        local options = {}
        for dy = -1, 1 do
            for dx = -1, 1 do
                local q = self:quad(s.qx + dx, s.qy + dy)
                if (dx ~= 0 or dy ~= 0) and q and not q.nova then options[#options + 1] = { s.qx + dx, s.qy + dy } end
            end
        end
        if #options == 0 then return self:lose("snova") end
        local o = options[rng:int(#options) + 1]
        s.energy = s.energy - (200 + rng:int(300))
        if s.energy <= 0 then return self:lose("snova") end
        s.qx, s.qy, s.x, s.y = o[1], o[2], rng:int(NS), rng:int(NS)
        self:initQuad()
        self:fx("enter", { snap = self:snapshot(), heading = s.heading })
        self:say("Helm", ("We escaped to quadrant %d,%d."):format(s.qx, s.qy), "warn")
        self:damageDevice(self:randomDevice(), 0.5 + rng:float() * 2)
        self:lrscan()
        self:arrivalNotes()
    end

    -- Collisions ---------------------------------------------------------------------

    -- Without the computer, the ship flies into whatever is in its way.
    function Game:ram(x, y, obj)
        local s, rng = self.ship, self.rng
        self:say("Helm", "Collision! Brace for impact!", "alert")
        self:fx("shake", { amount = 8 })
        if obj == C.KLINGON then
            self:say("Tactical", ("We rammed the Klingon at %d,%d."):format(x, y))
            self:killKlingon(self:klingonAt(x, y), "quiet")
        elseif obj == C.STAR or obj == C.INHABIT then
            return self:lose("star")
        elseif obj == C.BASE then
            self:destroyBase(x, y, true)
        end
        if self.over then return end
        local cas = 10 + rng:int(20)
        s.crew = s.crew - cas
        self.stats.deaths = self.stats.deaths + cas
        self:say("Medical", ("%d casualties from the collision."):format(cas), "bad")
        s.energy = s.energy - (150 + rng:int(250))
        for _ = 1, 1 + rng:int(3) do self:damageDevice(self:randomDevice(), 1 + rng:float() * 3) end
        if s.crew <= 0 then return self:lose("crew") end
        if s.energy <= 0 then return self:lose("destroyed") end
    end

    -- A black hole throws the ship out somewhere else in the galaxy.
    function Game:blackHole()
        local s, rng = self.ship, self.rng
        self:say("Helm", "We've been caught by a black hole!", "alert")
        local qx, qy
        repeat
            qx, qy = rng:int(NQ), rng:int(NQ)
        until not self:quad(qx, qy).nova
        s.qx, s.qy, s.x, s.y = qx, qy, rng:int(NS), rng:int(NS)
        self:initQuad()
        self:fx("enter", { snap = self:snapshot(), heading = s.heading })
        self:say("Helm", ("It threw us out in quadrant %d,%d."):format(qx, qy), "warn")
        self:lrscan()
        self:arrivalNotes()
    end
end
