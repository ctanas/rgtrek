-- How to play, a few pages long.

local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")
local starfield = require("src.starfield")

local Help = {}
Help.__index = Help

local PAGES = {
    { title = "The mission", text = {
        "Klingons are invading the Federation. Destroy every one of them before time runs out.",
        "The galaxy is 8 by 8 quadrants, and each quadrant is 10 by 10 sectors. The bridge shows the quadrant you're in; the star chart (Select) shows the galaxy as far as your scanners have seen it.",
        "Time is tight, but every Klingon you destroy buys more of it. Klingons who enslave a planet build new ships there, which costs time. Answer distress calls when you can.",
        "Starbases refill energy, shields and torpedoes, and repairs go twice as fast while docked.",
    } },
    { title = "Controls", rows = {
        { "D-pad", "Move the cursor over the sector grid" },
        { "A", "Orders for what's under the cursor: move, fire, dock..." },
        { "Y", "Fire a photon torpedo at the cursor" },
        { "X", "Fire phasers" },
        { "L1 / R1", "Jump the cursor between Klingons and other targets" },
        { "B", "Cursor back to the ship" },
        { "Select", "Star chart: pick a quadrant and warp there" },
        { "Start", "Ship menu: shields, rest, cloak, reports, emergencies" },
        { "Any button", "Skips animations" },
    } },
    { title = "Combat", text = {
        "Torpedoes usually destroy a Klingon outright, but you only carry ten and they can stray, more so with the shields up. A torpedo into a star can make it nova, destroying everything next to it.",
        "Phasers spend energy and grow weaker with distance. They can't fire through the shields, so the shields drop for the volley and come back up, weaker for that turn.",
        "Every Klingon in the quadrant fires back after each of your actions. Full shields absorb a hit completely; weaker shields let part of it through to your energy. Heavy hits damage systems. Each shot also drains the Klingon, and badly hurt ones may run or surrender.",
    } },
    { title = "Travel", text = {
        "Moving costs energy and time. Warp energy grows with the cube of the warp factor and doubles with the shields up; time shrinks with its square. Above warp 6 the drive may overheat.",
        "The computer steers around obstacles and stops short of anything it can't avoid. If the computer is damaged, the ship flies straight into whatever is in the way.",
        "With the warp drive damaged only the impulse engines are left: cheap but very slow. Resting lets the crew repair damage, but not with Klingons nearby.",
    } },
    { title = "Hazards", text = {
        "Black holes throw ships somewhere else in the galaxy. Supernovas destroy whole quadrants and leave them impassable. Klingon tractor beams can drag you into a fight.",
        "If life support fails, the reserves last only a few days away from a starbase. In an emergency (Start, then Emergency) you can call a starbase to beam the crew home, abandon ship for the Faire Queene, or self-destruct.",
        "You score for every Klingon destroyed or captured and for how fast you destroy them. You lose points for calls for help, lost starbases, destroyed stars and planets, and casualties.",
    } },
}

function Help.new(app)
    return setmetatable({ app = app, t = 0, page = 1 }, Help)
end

function Help:update(dt)
    self.t = self.t + dt
end

function Help:action(a)
    if a == "right" or a == "r1" or a == "a" then
        if self.page < #PAGES then
            self.page = self.page + 1
            sound.play("menu")
        elseif a == "a" then
            sound.play("close")
            self.app.pop()
        end
    elseif a == "left" or a == "l1" then
        if self.page > 1 then
            self.page = self.page - 1
            sound.play("menu")
        end
    elseif a == "b" or a == "start" then
        sound.play("close")
        self.app.pop()
    end
end

function Help:draw()
    starfield.draw(0.4)
    local page = PAGES[self.page]
    theme.set("text")
    ui.centered(page.title, 64, 52, 30, "bold", "left")
    theme.set("dim")
    ui.centered(("%d / %d"):format(self.page, #PAGES), 656, 54, 11, "pixel", "right")

    local y = 92
    if page.text then
        for _, para in ipairs(page.text) do
            theme.set("muted")
            ui.text(para, 64, y, 17, "regular", "left", 592)
            y = y + ui.wrap(para, 17, "regular", 592) + 14
        end
    else
        for _, row in ipairs(page.rows) do
            local cy = y + 12
            local label = row[1]
            if label == "A" or label == "B" or label == "X" or label == "Y"
                or label == "Select" or label == "Start" then
                ui.glyph(label, 64, cy, 1)
            else
                theme.set("text")
                ui.centered(label, 64, cy, 16, "bold", "left")
            end
            theme.set("muted")
            ui.centered(row[2], 180, cy, 17, "regular", "left")
            y = y + 36
        end
    end
    ui.hints({ { "B", "Close" }, { "L1", "Back" }, { "R1", "Next" } }, 696, 456, "right")
end

return Help
