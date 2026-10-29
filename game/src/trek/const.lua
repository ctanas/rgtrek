-- Fixed tables for the game rules: sizes, sector symbols, devices, names.
-- Values follow BSD trek (4.2BSD, Eric Allman) where it had them.

local C = {}

C.NSECTS = 10      -- sectors per quadrant side
C.NQUADS = 8       -- quadrants per galaxy side
C.MAXKLQUAD = 9    -- most Klingons in one quadrant

-- Sector contents, as BSD trek printed them
C.EMPTY = "."
C.STAR = "*"
C.BASE = "#"
C.SHIP = "E"       -- the Enterprise
C.QUEENE = "Q"     -- the Faire Queene, after abandoning ship
C.KLINGON = "K"
C.INHABIT = "@"
C.HOLE = " "

C.SKILLS = { "Novice", "Fair", "Good", "Expert", "Commodore", "Impossible" }
-- A win at a skill level earns the rank after it.
C.RANKS = { "Lieutenant Commander", "Commander", "Captain", "Commodore", "Rear Admiral", "Admiral", "Fleet Admiral" }
C.LENGTHS = { { key = 1, name = "Short" }, { key = 2, name = "Medium" }, { key = 4, name = "Long" } }

-- Devices that can be damaged. prob is the chance (out of 1000) that a
-- critical hit lands on it.
C.DEVICES = {
    { key = "warp", name = "Warp drive", prob = 70 },
    { key = "srscan", name = "Short-range scanners", prob = 110 },
    { key = "lrscan", name = "Long-range scanners", prob = 110 },
    { key = "phaser", name = "Phasers", prob = 125 },
    { key = "torped", name = "Photon tubes", prob = 125 },
    { key = "impulse", name = "Impulse engines", prob = 75 },
    { key = "shield", name = "Shield control", prob = 150 },
    { key = "computer", name = "Computer", prob = 20 },
    { key = "radio", name = "Subspace radio", prob = 35 },
    { key = "lifesup", name = "Life support", prob = 30 },
    { key = "sins", name = "Navigation", prob = 20 },
    { key = "cloak", name = "Cloaking device", prob = 50 },
    { key = "xporter", name = "Transporter", prob = 80 },
}
C.DEVICE = {}
for _, d in ipairs(C.DEVICES) do C.DEVICE[d.key] = d end

-- Inhabited star systems. Klingons can enslave them.
C.SYSTEMS = {
    "Rigel III", "Deneb VII", "Canopus V", "Procyon IV", "Altair II",
    "Vega IX", "Antares IV", "Sirius II", "Aldebaran V", "Capella III",
    "Arcturus VI", "Polaris II", "Mira IV", "Tau Ceti III", "Eridani IV",
    "Bellatrix II", "Fomalhaut V", "Achernar III", "Spica II", "Regulus IV",
    "Castor VI", "Pollux II", "Alnilam I", "Mizar V", "Alcor II",
    "Hadar III", "Shaula II", "Kochab IV", "Wezen I", "Alpheratz II",
    "Markab V",
}

-- Average days between random events.
C.EVENT_MEAN = {
    snova = 6.0,     -- a star somewhere goes supernova
    tractor = 9.0,   -- Klingon long-range tractor beam
    katsb = 3.5,     -- Klingons attack a starbase
    enslave = 4.0,   -- Klingons enslave an inhabited system
}

C.LOSS = {
    time = "You ran out of time. The Klingons have overrun the Federation.",
    energy = "The ship ran out of energy and drifts, dead in space.",
    destroyed = "The ship has been destroyed.",
    negenb = "The ship hit the negative energy barrier at the edge of the galaxy.",
    suicide = "The ship was caught in the blast of the nova it caused.",
    snova = "The ship was caught in a supernova.",
    nolife = "Life support failed and the crew suffocated.",
    nohelp = "The transporter could not rematerialize the crew.",
    star = "The ship flew into a star and burned up.",
    destruct = "The ship self-destructed.",
    crew = "The last of the crew has died.",
    stranded = "With no starbase left, the crew was stranded in space.",
}

return C
