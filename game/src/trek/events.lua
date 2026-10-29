-- Things that happen on their own as time passes, after BSD trek's
-- events.c: supernovas, Klingon tractor beams, attacks on starbases, and
-- Klingons enslaving inhabited systems and building more ships there.

local C = require("src.trek.const")

local NS, NQ = C.NSECTS, C.NQUADS

return function(Game)
    function Game:schedule(kind, delay, data)
        local e = data or {}
        e.kind = kind
        e.date = self.date + delay
        self.events[#self.events + 1] = e
        return e
    end

    function Game:nextEvent()
        local best, bi
        for i, e in ipairs(self.events) do
            if not best or e.date < best.date then best, bi = e, i end
        end
        return best, bi
    end

    local function isHere(self, qx, qy)
        return self.ship.qx == qx and self.ship.qy == qy
    end

    local HANDLERS = {}

    -- A star somewhere goes supernova.
    function HANDLERS.snova(self)
        local rng = self.rng
        self:schedule("snova", rng:expo(C.EVENT_MEAN.snova))
        local qx, qy
        for _ = 1, 30 do
            local x, y = rng:int(NQ), rng:int(NQ)
            local q = self:quad(x, y)
            if not q.nova and q.s > 0 then
                qx, qy = x, y
                break
            end
        end
        if not qx then return end
        if isHere(self, qx, qy) then
            self:say("Science", "A star in this quadrant is going supernova!", "alert")
            self:fx("supernova", {})
        elseif self:radioOK() then
            self:say("Comms", ("Supernova in quadrant %d,%d."):format(qx, qy), "warn")
        end
        self:supernova(qx, qy, false)
        self.interrupt = true
    end

    -- Klingons nearby lock a tractor beam on the ship and pull it in.
    function HANDLERS.tractor(self)
        local rng, s = self.rng, self.ship
        self:schedule("tractor", rng:expo(C.EVENT_MEAN.tractor))
        if #self.kl > 0 or s.docked or (s.cloaked and s.cloakGood) then return end
        local options = {}
        for y = 0, NQ - 1 do
            for x = 0, NQ - 1 do
                local q = self:quad(x, y)
                if q.k > 0 and not q.nova and math.max(math.abs(x - s.qx), math.abs(y - s.qy)) <= 3 then
                    options[#options + 1] = { x, y }
                end
            end
        end
        if #options == 0 then return end
        local o = options[rng:int(#options) + 1]
        self:say("Helm", ("Klingon tractor beam! We're being pulled into quadrant %d,%d!"):format(o[1], o[2]), "alert")
        s.qx, s.qy, s.x, s.y = o[1], o[2], rng:int(NS), rng:int(NS)
        self:initQuad()
        self:fx("enter", { snap = self:snapshot(), heading = s.heading })
        self:lrscan()
        self:arrivalNotes()
        self.interrupt = true
    end

    -- Klingons lay siege to a starbase. If they're still there when time
    -- runs out, the starbase falls.
    function HANDLERS.katsb(self)
        local rng, s = self.rng, self.ship
        self:schedule("katsb", rng:expo(C.EVENT_MEAN.katsb))
        local list = {}
        for _, b in ipairs(self.bases) do
            local q = self:quad(b.x, b.y)
            if q.k > 0 and not q.attacked and not isHere(self, b.x, b.y) then list[#list + 1] = b end
        end
        if #list == 0 then
            -- Klingons from next door move in on a starbase
            local start = rng:int(math.max(1, #self.bases))
            for n = 1, #self.bases do
                local b = self.bases[(start + n - 1) % #self.bases + 1]
                local q = self:quad(b.x, b.y)
                if not q.attacked and not isHere(self, b.x, b.y) then
                    for dy = -1, 1 do
                        for dx = -1, 1 do
                            local nq = self:quad(b.x + dx, b.y + dy)
                            if #list == 0 and nq and nq ~= q and nq.k > 0 and not isHere(self, b.x + dx, b.y + dy) then
                                nq.k = nq.k - 1
                                q.k = q.k + 1
                                list[1] = b
                            end
                        end
                    end
                end
                if #list > 0 then break end
            end
        end
        if #list == 0 then return end
        local b = list[rng:int(#list) + 1]
        local q = self:quad(b.x, b.y)
        local hold = 2 + rng:float() * 2.5
        q.attacked = self.date + hold
        self:schedule("kdesb", hold, { qx = b.x, qy = b.y })
        if self:radioOK() then
            q.distress = true
            self:say("Comms", ("The starbase in quadrant %d,%d is under attack! It can hold out until stardate %.1f."):format(
                b.x, b.y, q.attacked), "alert")
            self:fx("sound", { name = "comms" })
            self.interrupt = true
        end
    end

    function HANDLERS.kdesb(self, e)
        local q = self:quad(e.qx, e.qy)
        if q.b == 0 or not q.attacked then return end
        if q.k == 0 then
            q.attacked, q.distress = nil, nil
            return
        end
        if isHere(self, e.qx, e.qy) then
            -- the ship is here fighting, so the starbase holds on
            q.attacked = self.date + 0.5
            self:schedule("kdesb", 0.5, { qx = e.qx, qy = e.qy })
            return
        end
        self:removeBase(e.qx, e.qy)
        self.stats.basesLost = self.stats.basesLost + 1
        if self:radioOK() then
            self:say("Comms", ("The starbase in quadrant %d,%d has been destroyed."):format(e.qx, e.qy), "bad")
            self.interrupt = true
        end
    end

    -- Klingons enslave an inhabited system and start building ships there.
    function HANDLERS.enslave(self)
        local rng = self.rng
        self:schedule("enslave", rng:expo(C.EVENT_MEAN.enslave))
        local list = {}
        for y = 0, NQ - 1 do
            for x = 0, NQ - 1 do
                local q = self:quad(x, y)
                if q.sys and q.k > 0 and not q.enslaved and not isHere(self, x, y) then
                    list[#list + 1] = { x, y }
                end
            end
        end
        if #list == 0 then return end
        local o = list[rng:int(#list) + 1]
        local q = self:quad(o[1], o[2])
        q.enslaved = true
        self:schedule("repro", 1.5 + rng:float() * 2, { qx = o[1], qy = o[2] })
        if self:radioOK() then
            q.distress = true
            self:say("Comms", ("Distress call from %s in quadrant %d,%d: Klingons are enslaving the people!"):format(
                q.sys, o[1], o[2]), "alert")
            self:fx("sound", { name = "comms" })
            self.interrupt = true
        end
    end

    -- An enslaved system builds another Klingon ship.
    function HANDLERS.repro(self, e)
        local q = self:quad(e.qx, e.qy)
        if not q.enslaved then return end
        if q.k == 0 or not q.sys then
            q.enslaved, q.distress = nil, nil
            return
        end
        self:schedule("repro", 1.5 + self.rng:float() * 2, { qx = e.qx, qy = e.qy })
        if isHere(self, e.qx, e.qy) or q.k >= C.MAXKLQUAD then return end
        q.k = q.k + 1
        self.klings = self.klings + 1
        self:updateTime()
        if q.distress and self:radioOK() then
            self:say("Comms", ("Klingons at %s (quadrant %d,%d) have built another ship."):format(q.sys, e.qx, e.qy), "warn")
        end
    end

    function Game:handleEvent(e)
        local h = HANDLERS[e.kind]
        if h then h(self, e) end
    end
end
