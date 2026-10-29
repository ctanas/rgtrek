-- The captain's commands. Each returns true if it was carried out (and the
-- Klingons got their turn), or false with a message saying why not.
-- Previews (plan, phaserPlan, captureChance...) let the screen show costs
-- before committing.

local C = require("src.trek.const")

local NS, NQ = C.NSECTS, C.NQUADS
local floor, sqrt = math.floor, math.sqrt

local MAX_PHASER = 1500   -- most energy one phaser volley can carry
local SHIELD_COST = 40    -- energy to raise the shields

return function(Game)
    local round = Game.round
    Game.MAX_PHASER = MAX_PHASER

    local function plural(n, word)
        return n .. " " .. word .. (n == 1 and "" or "s")
    end

    -- Movement ----------------------------------------------------------------------

    -- Walk a straight line from galaxy sector (x0, y0) along (ux, uy) for
    -- `len` sectors, a tenth of a sector at a time. Returns the last free
    -- sector reached and, if something was in the way, what it was ("edge"
    -- or a sector symbol) and where in the quadrant. Only the ship's own
    -- quadrant is checked; the rest of the galaxy is too far to see.
    function Game:trace(x0, y0, ux, uy, len)
        local s = self.ship
        local ox, oy = s.qx * NS, s.qy * NS
        local lastX, lastY = x0, y0
        local t = 0
        while t < len do
            t = math.min(len, t + 0.1)
            local cx, cy = round(x0 + ux * t), round(y0 + uy * t)
            if cx ~= lastX or cy ~= lastY then
                if cx < 0 or cy < 0 or cx >= NQ * NS or cy >= NQ * NS then
                    return lastX, lastY, "edge"
                end
                local lx, ly = cx - ox, cy - oy
                local obj = self:at(lx, ly)
                if obj and obj ~= C.EMPTY and obj ~= s.kind then
                    return lastX, lastY, obj, lx, ly
                end
                lastX, lastY = cx, cy
            end
        end
        return lastX, lastY
    end

    local function clear(self, x0, y0, x1, y1)
        local dx, dy = x1 - x0, y1 - y0
        local len = sqrt(dx * dx + dy * dy)
        if len == 0 then return true end
        local _, _, obj = self:trace(x0, y0, dx / len, dy / len, len)
        return obj == nil
    end

    -- Waypoints from the ship to galaxy sector (gx, gy). When something in
    -- this quadrant blocks the straight course, the computer looks for a
    -- detour through one empty sector. Without the computer or navigation,
    -- or with no way around, it's the straight line.
    function Game:route(gx, gy)
        local s = self.ship
        local x0, y0 = s.qx * NS + s.x, s.qy * NS + s.y
        local direct = { { gx, gy } }
        if clear(self, x0, y0, gx, gy) or self:damaged("computer") or self:damaged("sins") then
            return direct
        end
        local best, bw
        for y = 0, NS - 1 do
            for x = 0, NS - 1 do
                if self:at(x, y) == C.EMPTY then
                    local wx, wy = s.qx * NS + x, s.qy * NS + y
                    local d = sqrt((wx - x0) ^ 2 + (wy - y0) ^ 2) + sqrt((gx - wx) ^ 2 + (gy - wy) ^ 2)
                    if (not best or d < best) and clear(self, x0, y0, wx, wy) and clear(self, wx, wy, gx, gy) then
                        best, bw = d, { wx, wy }
                    end
                end
            end
        end
        if bw then return { bw, { gx, gy } } end
        return direct
    end

    -- How the ship would get to galaxy sector (gx, gy) at the current warp
    -- factor: route, engine, distance (quadrants), course, energy, time, and
    -- a reason if it can't go.
    function Game:plan(gx, gy)
        local s = self.ship
        local x0, y0 = s.qx * NS + s.x, s.qy * NS + s.y
        local info = { course = Game.course(gx - x0, gy - y0) }
        local tq = self:quad(floor(gx / NS), floor(gy / NS))
        if not tq or gx < 0 or gy < 0 then
            info.reason = "That's outside the galaxy."
            return info
        end
        if gx == x0 and gy == y0 then
            info.reason = "We're already there."
            return info
        end
        info.route = self:route(gx, gy)
        local d, px, py = 0, x0, y0
        for _, wp in ipairs(info.route) do
            d = d + sqrt((wp[1] - px) ^ 2 + (wp[2] - py) ^ 2)
            px, py = wp[1], wp[2]
        end
        d = d / NS
        info.dist = d
        info.detour = #info.route > 1
        if not self:damaged("warp") then
            local w = s.warp
            info.engine = "warp"
            info.energy = floor(d * w * w * w * (s.up and 2 or 1) + 0.5)
            info.time = 10 * d / (w * w)
            if w > 6 then info.strain = 0.04 * (w - 6) ^ 2 end
        elseif not self:damaged("impulse") then
            info.engine = "impulse"
            info.energy = floor(20 + 100 * d + 0.5)
            info.time = d / 0.095
        else
            info.reason = "The warp drive and impulse engines are both damaged."
            return info
        end
        if s.cloaked then info.energy = info.energy + floor(info.time * 1000) end
        if info.energy >= s.energy then
            info.reason = ("Not enough energy. That needs %d."):format(info.energy)
        elseif tq.nova and not self:damaged("computer") then
            info.reason = "That quadrant is a supernova remnant."
        end
        info.ok = info.reason == nil
        return info
    end

    -- Fly to galaxy sector (gx, gy), leg by leg.
    function Game:navigate(gx, gy)
        local s, rng = self.ship, self.rng
        local info = self:plan(gx, gy)
        if not info.ok then return self:refuse("Helm", info.reason) end
        local x0, y0 = s.qx * NS + s.x, s.qy * NS + s.y
        local computer = not self:damaged("computer")
        local strained = info.strain and rng:float() < info.strain
        local strainAt = strained and info.dist * NS * (0.3 + 0.5 * rng:float())

        if info.detour then
            local w = info.route[1]
            self:say("Helm", ("Plotting a course around the obstacle, by way of %d,%d."):format(w[1] - s.qx * NS, w[2] - s.qy * NS))
        end
        local moved, blocked, bx, by = 0, nil, nil, nil
        local px, py = x0, y0
        for _, wp in ipairs(info.route) do
            local dx, dy = wp[1] - px, wp[2] - py
            local len = sqrt(dx * dx + dy * dy)
            local course = Game.course(dx, dy)
            if self:damaged("sins") then
                local err = (rng:float() - 0.5) * (info.engine == "warp" and 14 or 7)
                course = course + err
                self:say("Helm", ("Navigation is damaged. Course is off by %.1f degrees."):format(err), "warn")
            end
            if strainAt and moved + len > strainAt then len = math.max(0, strainAt - moved) end
            local rad = math.rad(course)
            local lx, ly
            lx, ly, blocked, bx, by = self:trace(px, py, math.sin(rad), -math.cos(rad), len)
            moved = moved + sqrt((lx - px) ^ 2 + (ly - py) ^ 2)
            s.heading = course
            self:moveShipTo(lx, ly, course)
            px, py = lx, ly
            if blocked or self.over or (strainAt and moved >= strainAt - 0.05) then break end
        end

        local frac = math.min(1, moved / (info.dist * NS))
        s.energy = s.energy - info.energy * frac
        if blocked and computer then
            if blocked == "edge" then
                self:say("Helm", "Negative energy barrier ahead. All stop.", "warn")
            else
                self:say("Helm", ("%s at %d,%d is in the way. All stop."):format(Game.OBJECT_NAMES[blocked], bx, by), "warn")
            end
            if moved == 0 then
                self:fx("sound", { name = "error" })
                return false
            end
        end
        if s.docked and moved > 0 then
            s.docked = false
            self:say("Helm", "Undocked from the starbase.")
        end
        if strained then
            self:say("Engineering", "The warp drive overheated! We dropped out of warp.", "bad")
            self:damageDevice("warp", 0.5 + rng:float() * 2)
        end
        if blocked and not computer and not self.over then
            if blocked == "edge" then
                self:lose("negenb")
            elseif blocked == C.HOLE then
                self:blackHole()
            else
                self:ram(bx, by, blocked)
            end
        end
        self:endTurn(info.time * math.max(frac, 0.1))
        return true
    end

    -- Put the ship at galaxy sector (gx, gy), entering a new quadrant if needed.
    function Game:moveShipTo(gx, gy, course)
        local s = self.ship
        local nqx, nqy = floor(gx / NS), floor(gy / NS)
        local nx, ny = gx - nqx * NS, gy - nqy * NS
        if nqx == s.qx and nqy == s.qy then
            if nx ~= s.x or ny ~= s.y then
                self:fx("move", { x = s.x, y = s.y, tx = nx, ty = ny, heading = course })
                self:put(s.x, s.y, C.EMPTY)
                s.x, s.y = nx, ny
                self:put(nx, ny, s.kind)
            end
            return
        end
        s.qx, s.qy, s.x, s.y = nqx, nqy, nx, ny
        self:initQuad()
        self:fx("enter", { snap = self:snapshot(), heading = course })
        local q = self:here()
        self:say("Helm", ("Entering quadrant %d,%d%s."):format(nqx, nqy, q.sys and (", the " .. q.sys .. " system") or ""))
        self:lrscan()
        if q.nova then
            self:say("Science", "This quadrant is a supernova remnant!", "alert")
            return self:emergencyEscape()
        end
        self:arrivalNotes()
    end

    -- What the crew points out on arriving in a quadrant.
    function Game:arrivalNotes()
        local q = self:here()
        local n = #self.kl
        if n > 0 then
            self:say("Tactical", ("Red alert! %s in this quadrant."):format(plural(n, "Klingon")), "alert")
            self:fx("sound", { name = "alert" })
        end
        if q.enslaved then
            self:say("Science", ("%s has been enslaved. Destroy the Klingons here to free it."):format(q.sys or "The planet"), "warn")
        end
        if q.attacked then
            self:say("Comms", "The starbase here is under siege.", "warn")
        end
    end

    -- Move within the quadrant.
    function Game:cmdMove(x, y)
        local s = self.ship
        return self:navigate(s.qx * NS + x, s.qy * NS + y)
    end

    -- Warp to another quadrant, arriving at the same sector we're in now.
    function Game:cmdWarp(qx, qy)
        local s = self.ship
        if qx == s.qx and qy == s.qy then return self:refuse("Helm", "We're in that quadrant now.") end
        return self:navigate(qx * NS + s.x, qy * NS + s.y)
    end

    -- The empty sector next to (x, y) that's closest to the ship.
    function Game:approachSector(x, y)
        local best, bx, by
        for dy = -1, 1 do
            for dx = -1, 1 do
                local nx, ny = x + dx, y + dy
                local obj = self:at(nx, ny)
                if obj == self.ship.kind and (dx ~= 0 or dy ~= 0) then return nx, ny end
                if obj == C.EMPTY then
                    local d = self:dist(nx, ny)
                    if not best or d < best then best, bx, by = d, nx, ny end
                end
            end
        end
        return bx, by
    end

    -- Fly up next to (x, y). Docks when that's a starbase.
    function Game:cmdApproach(x, y)
        local s = self.ship
        local ax, ay = self:approachSector(x, y)
        if not ax then return self:refuse("Helm", "There's no room to come alongside.") end
        local isBase = self:at(x, y) == C.BASE
        if ax ~= s.x or ay ~= s.y then
            if not self:cmdMove(ax, ay) then return false end
        end
        if isBase and not self.over and not s.docked and self:adjacentBase() then
            self:cmdDock()
        end
        return true
    end

    function Game:setWarp(w)
        self.ship.warp = math.max(1, math.min(9, w))
    end

    -- Weapons -------------------------------------------------------------------------

    function Game:phaserCheck()
        local s = self.ship
        if s.docked then return "Phasers can't fire through the starbase's shields." end
        if s.cloaked then return "We can't fire while cloaked." end
        if self:damaged("phaser") then return "Phasers are damaged." end
        if #self.kl == 0 then return "There are no Klingons in this quadrant." end
    end

    -- Energy that is sure to destroy Klingon k with phasers.
    function Game:phaserNeed(k)
        local d = self:dist(k.x, k.y)
        return math.ceil(k.power / (0.95 * 0.9 ^ d) / 10) * 10
    end

    -- Split `units` among the Klingons: all on `focus` if given, otherwise
    -- enough for each in turn, weakest first, so as many as possible go
    -- down. Leftover energy is shared out. Returns { {k, units, need} }.
    function Game:phaserPlan(units, focus)
        local list = {}
        for _, k in ipairs(self.kl) do
            if not focus or k == focus then
                list[#list + 1] = { k = k, need = self:phaserNeed(k), units = 0 }
            end
        end
        table.sort(list, function(a, b) return a.need < b.need end)
        local left = units
        for _, e in ipairs(list) do
            local u = math.min(e.need, left)
            e.units = u
            left = left - u
        end
        if left > 0 and #list > 0 then
            for _, e in ipairs(list) do e.units = e.units + left / #list end
        end
        return list
    end

    -- Fire phasers with `units` of energy, at the Klingon at (fx, fy) or at
    -- all of them. Phasers can't fire through shields, so the shields drop
    -- for the volley and come back up after, weaker for this turn.
    function Game:cmdPhasers(units, fx, fy)
        local why = self:phaserCheck()
        if why then return self:refuse("Tactical", why) end
        local s, rng = self.ship, self.rng
        units = math.min(floor(units), MAX_PHASER)
        if units <= 0 then return self:refuse("Tactical", "Set the phaser energy first.") end
        if units >= s.energy then return self:refuse("Engineering", "We don't have that much energy.") end
        local focus = fx and self:klingonAt(fx, fy)

        local wasUp = s.up
        if wasUp then
            s.up, self.shieldChange = false, true
            self:say("Tactical", "Lowering shields to fire.")
            self:fx("shields", { up = false, stats = self:shipStats() })
        end
        s.energy = s.energy - units
        for _, e in ipairs(self:phaserPlan(units, focus)) do
            local k = e.k
            if e.units > 0 and not self.over then
                local d = self:dist(k.x, k.y)
                local hit = floor(e.units * 0.9 ^ d * (0.95 + 0.1 * rng:float()))
                self:fx("phaser", { x = k.x, y = k.y, hit = hit, stats = self:shipStats() })
                k.power = k.power - hit
                if k.power <= 0 then
                    self:say("Tactical", ("Phasers hit the Klingon at %d,%d for %d. Destroyed!"):format(k.x, k.y, hit), "good")
                    self:killKlingon(k, "quiet")
                else
                    self:say("Tactical", ("Phasers hit the Klingon at %d,%d for %d."):format(k.x, k.y, hit))
                end
            end
        end
        if self.over then return true end
        if units > 1000 and rng:float() < (units - 1000) / 2000 then
            self:say("Engineering", "The phaser banks overheated.", "warn")
            self:damageDevice("phaser", 0.5 + rng:float() * 1.5)
        end
        if wasUp and not self:damaged("shield") and s.energy > SHIELD_COST then
            s.energy = s.energy - SHIELD_COST
            s.up = true
            self:say("Tactical", "Shields back up.")
            self:fx("shields", { up = true, stats = self:shipStats() })
        end
        self:endTurn(0)
        return true
    end

    function Game:torpedoCheck()
        local s = self.ship
        if s.docked then return "We can't fire while docked." end
        if s.cloaked then return "We can't fire while cloaked." end
        if self:damaged("torped") then return "The photon tubes are damaged." end
        if s.torps <= 0 then return "We're out of photon torpedoes." end
    end

    -- How far a torpedo can stray, in degrees: more with the shields up.
    function Game:torpedoSpread()
        return self.ship.up and 3 or 1.5
    end

    -- Fire a photon torpedo toward sector (tx, ty). It flies until it hits
    -- something or leaves the quadrant.
    function Game:cmdTorpedo(tx, ty)
        local why = self:torpedoCheck()
        if why then return self:refuse("Tactical", why) end
        local s, rng = self.ship, self.rng
        if tx == s.x and ty == s.y then return self:refuse("Tactical", "Pick a target first.") end
        s.torps = s.torps - 1
        local course = Game.course(tx - s.x, ty - s.y)
        s.heading = course
        if rng:float() < 0.02 then
            self:fx("turn", { heading = course })
            self:say("Tactical", "The torpedo misfired!", "warn")
            self:fx("sound", { name = "error" })
            if rng:float() < 0.5 then self:damageDevice("torped", 0.5 + rng:float()) end
            self:endTurn(0)
            return true
        end
        course = course + (rng:float() * 2 - 1) * self:torpedoSpread()
        local rad = math.rad(course)
        local ux, uy = math.sin(rad), -math.cos(rad)
        local hx, hy, obj
        local t, px, py = 0, s.x, s.y
        while true do
            t = t + 0.1
            px, py = s.x + ux * t, s.y + uy * t
            local cx, cy = round(px), round(py)
            if cx < 0 or cy < 0 or cx >= NS or cy >= NS then break end
            if cx ~= s.x or cy ~= s.y then
                local o = self:at(cx, cy)
                if o ~= C.EMPTY then
                    hx, hy, obj = cx, cy, o
                    break
                end
            end
        end
        self:fx("torpedo", {
            heading = s.heading, tx = hx or px, ty = hy or py, hit = obj ~= nil,
            stats = self:shipStats(),
        })
        if not obj then
            self:say("Tactical", "The torpedo missed.")
        elseif obj == C.KLINGON then
            local k = self:klingonAt(hx, hy)
            k.power = k.power - (500 + rng:int(501))
            if k.power <= 0 then
                self:say("Tactical", ("Torpedo hit! Klingon at %d,%d destroyed."):format(hx, hy), "good")
                self:killKlingon(k, "quiet")
            else
                self:fx("boom", { x = hx, y = hy, size = 0 })
                self:say("Tactical", ("Torpedo hit the Klingon at %d,%d. It's badly damaged."):format(hx, hy))
            end
        elseif obj == C.STAR then
            self:say("Tactical", ("The torpedo hit the star at %d,%d."):format(hx, hy), "warn")
            self:nova(hx, hy)
        elseif obj == C.BASE then
            self:say("Tactical", "The torpedo hit the starbase!", "bad")
            self:destroyBase(hx, hy, true)
        elseif obj == C.INHABIT then
            self:destroySystem(hx, hy)
        elseif obj == C.HOLE then
            self:say("Tactical", "The torpedo vanished into a black hole.")
        end
        self:endTurn(0)
        return true
    end

    -- Ship systems ----------------------------------------------------------------------

    function Game:cmdShields(up)
        local s = self.ship
        if up == nil then up = not s.up end
        if up == s.up then return false end
        if up then
            if self:damaged("shield") then return self:refuse("Tactical", "Shield control is damaged.") end
            if s.energy <= SHIELD_COST then return self:refuse("Engineering", "Not enough energy to raise the shields.") end
            s.energy = s.energy - SHIELD_COST
        end
        s.up, self.shieldChange = up, true
        self:say("Tactical", up and "Shields up." or "Shields down.")
        self:fx("shields", { up = up, stats = self:shipStats() })
        self:endTurn(0)
        return true
    end

    function Game:resupply()
        local s, p = self.ship, self.p
        s.energy = math.max(s.energy, p.energy)
        s.shield = p.shield
        s.torps = p.torps
        s.reserves = p.reserves
        if s.brig > 0 then
            self:say("Comms", ("%d captives handed over to the starbase."):format(s.brig))
            s.brig = 0
        end
    end

    function Game:cmdDock()
        local s = self.ship
        if s.docked then return self:refuse("Helm", "We're already docked.") end
        if not self:adjacentBase() then return self:refuse("Helm", "We need to be next to a starbase to dock.") end
        if s.cloaked then
            s.cloaked, s.cloakGood = false, false
            self:say("Helm", "Dropping the cloak to dock.")
        end
        s.docked = true
        self:resupply()
        self:say("Helm", "Docked. Energy, shields and torpedoes replenished.", "good")
        self:fx("dock", { stats = self:shipStats() })
        self:endTurn(0)
        return true
    end

    function Game:restCheck()
        if #self.kl > 0 and not self.ship.docked then
            return "We can't rest with Klingons in the quadrant."
        end
    end

    -- Let time pass for repairs. Stops early if something needs the captain.
    function Game:cmdRest(days)
        local why = self:restCheck()
        if why then return self:refuse("Tactical", why) end
        days = math.max(0.1, days)
        local start = self.date
        self:say("Helm", ("Resting for %.1f days."):format(days))
        self.interrupt = false
        self:advance(days, true)
        if self.over then return true end
        local rested = self.date - start
        if rested < days - 0.01 then
            self:say("Helm", ("Rest interrupted after %.1f days."):format(rested), "warn")
        end
        self:fx("sync", { stats = self:shipStats() })
        self:endTurn(0)
        return true
    end

    -- Chance that the Klingon at (x, y) gives up: low at full power, high
    -- when it's nearly beaten.
    function Game:captureChance(k)
        local ratio = k.power / self.p.klingpwr
        return math.max(0.05, math.min(0.9, 1.15 - ratio * 1.1))
    end

    function Game:captureCheck()
        local s = self.ship
        if s.cloaked then return "They can't see us while we're cloaked." end
        if self:damaged("radio") then return "The subspace radio is damaged. We can't hail them." end
        if self:damaged("xporter") then return "The transporter is damaged. We couldn't take prisoners." end
    end

    function Game:cmdCapture(x, y)
        local k = self:klingonAt(x, y)
        if not k then return self:refuse("Comms", "There's no Klingon there.") end
        local why = self:captureCheck()
        if why then return self:refuse("Comms", why) end
        local s, rng = self.ship, self.rng
        self:say("Comms", ("Hailing the Klingon at %d,%d to surrender..."):format(x, y))
        if rng:float() < self:captureChance(k) then
            local crew = floor(self.p.klingcrew * (0.25 + 0.75 * rng:float()))
            local taken = math.min(crew, self.p.brig - s.brig)
            s.brig = s.brig + taken
            self.stats.captives = self.stats.captives + taken
            self:say("Comms", ("The Klingon surrenders! %d captives beamed aboard."):format(taken), "good")
            if taken < crew then
                self:say("Comms", ("The brig is full. %d prisoners were left in their ship's lifeboats."):format(crew - taken))
            end
            self:killKlingon(k, "captured")
        else
            self:say("Comms", "They refuse to surrender.", "warn")
        end
        self:endTurn(0)
        return true
    end

    function Game:cmdCloak(on)
        local s = self.ship
        if on == nil then on = not s.cloaked end
        if on == s.cloaked then return false end
        if on then
            if not s.hasCloak then return self:refuse("Engineering", "This ship has no cloaking device.") end
            if self:damaged("cloak") then return self:refuse("Engineering", "The cloaking device is damaged.") end
            if s.docked then return self:refuse("Helm", "We can't cloak while docked.") end
            s.cloaked, s.cloakGood = true, false
            self:say("Helm", "Cloaking device on. It takes effect after this turn and uses 1000 energy a day.")
        else
            s.cloaked, s.cloakGood = false, false
            self:say("Helm", "Cloaking device off.")
        end
        self:fx("cloak", { on = on, stats = self:shipStats() })
        self:endTurn(0)
        return true
    end

    -- Emergencies -------------------------------------------------------------------------

    -- Move the ship next to the starbase in the current quadrant.
    function Game:placeAtBase()
        local s = self.ship
        for y = 0, NS - 1 do
            for x = 0, NS - 1 do
                if self:at(x, y) == C.BASE then
                    local best, bx, by
                    for dy = -1, 1 do
                        for dx = -1, 1 do
                            local nx, ny = x + dx, y + dy
                            if self:at(nx, ny) == C.EMPTY or (nx == s.x and ny == s.y) then
                                local d = math.abs(dx) + math.abs(dy)
                                if not best or d < best then best, bx, by = d, nx, ny end
                            end
                        end
                    end
                    if bx then
                        self:put(s.x, s.y, C.EMPTY)
                        s.x, s.y = bx, by
                        self:put(bx, by, s.kind)
                    end
                    return
                end
            end
        end
    end

    -- Chance per attempt that a rescue transport fails, by distance.
    function Game:helpFailChance()
        local b, d = self:nearestBase()
        if not b then return nil end
        return math.min(0.6, 0.1 + 0.07 * d), b
    end

    function Game:helpCheck()
        local s = self.ship
        if s.docked then return "We're already docked." end
        if self:damaged("radio") then return "The subspace radio is damaged." end
        if #self.bases == 0 then return "There are no starbases left." end
    end

    -- Call the nearest starbase to beam the ship's crew home. Three tries;
    -- if all three fail, the crew is lost.
    function Game:cmdHelp()
        local why = self:helpCheck()
        if why then return self:refuse("Comms", why) end
        local s, rng = self.ship, self.rng
        local fail, b = self:helpFailChance()
        self.stats.helps = self.stats.helps + 1
        self:say("Comms", ("Calling the starbase in quadrant %d,%d for help..."):format(b.x, b.y))
        for attempt = 1, 3 do
            if rng:float() >= fail then
                if s.cloaked then s.cloaked, s.cloakGood = false, false end
                s.qx, s.qy = b.x, b.y
                self:initQuad()
                self:placeAtBase()
                s.docked = true
                self:resupply()
                self:fx("enter", { snap = self:snapshot(), heading = s.heading, beam = true })
                self:say("Engineering", ("Rematerialized at the starbase on attempt %d."):format(attempt), "good")
                self:lrscan()
                self:endTurn(0.3)
                return true
            end
            self:say("Engineering", ("Attempt %d to rematerialize failed."):format(attempt), "bad")
        end
        self:lose("nohelp")
        return true
    end

    function Game:abandonCheck()
        if self.ship.kind == C.QUEENE then return "Regulations forbid abandoning the Faire Queene." end
        if #self.bases == 0 then return "There's no starbase the shuttlecraft could reach." end
    end

    -- Leave the Enterprise for the shuttlecraft. The crew reaches the
    -- nearest starbase and takes over the Faire Queene, which has no cloak.
    function Game:cmdAbandon()
        local why = self:abandonCheck()
        if why then return self:refuse("Helm", why) end
        local s, p, rng = self.ship, self.p, self.rng
        local b, d = self:nearestBase()
        self:say("Helm", "Abandon ship! The crew is boarding the shuttlecraft.", "alert")
        self.stats.shipLost = true
        s.kind, s.name, s.hasCloak = C.QUEENE, "Faire Queene", false
        s.cloaked, s.cloakGood, s.up = false, false, true
        s.energy = p.energy
        for key in pairs(self.dmg) do self.dmg[key] = 0 end
        s.qx, s.qy = b.x, b.y
        self:initQuad()
        self:placeAtBase()
        s.docked = true
        self:resupply()
        self:fx("enter", { snap = self:snapshot(), heading = 0, beam = true })
        self:say("Helm", ("The crew reached the starbase in quadrant %d,%d and took command of the Faire Queene."):format(b.x, b.y), "good")
        self:lrscan()
        self:endTurn(0.5 + d * 0.25 + rng:float() * 0.2)
        return true
    end

    -- Blow up the ship, taking nearby Klingons with it.
    function Game:cmdDestruct()
        local s = self.ship
        self:say("Computer", "Self-destruct in 3... 2... 1...", "alert")
        self:fx("boom", { x = s.x, y = s.y, size = 3 })
        self:fx("shake", { amount = 10 })
        self:set(s.x, s.y, C.EMPTY)
        local targets = {}
        for _, k in ipairs(self.kl) do
            if self:dist(k.x, k.y) <= 6 then targets[#targets + 1] = k end
        end
        for _, k in ipairs(targets) do
            if not self.over then
                self:say("Tactical", ("The blast destroyed the Klingon at %d,%d."):format(k.x, k.y), "good")
                self:killKlingon(k, "quiet")
            end
        end
        if self.over and self.over.won then
            self.over = {
                won = false, reason = "destruct",
                text = "The blast took the last Klingons with it. The Federation is safe, but the ship is gone.",
            }
        else
            self:lose("destruct")
        end
        return true
    end
end
