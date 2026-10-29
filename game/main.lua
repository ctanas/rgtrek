-- rgTrek: BSD trek for muOS (MustardOS)
-- Entry point: owns the scene stack, settings, records and saving.

local ui = require("src.ui")
local theme = require("src.theme")
local input = require("src.input")
local sound = require("src.sound")
local storage = require("src.storage")
local Game = require("src.trek.game")

local VERSION = "1.0.0"

local SCENES = {
    title = require("src.scenes.title"),
    newgame = require("src.scenes.newgame"),
    play = require("src.scenes.play"),
    chart = require("src.scenes.chart"),
    orders = require("src.scenes.orders"),
    phasers = require("src.scenes.phasers"),
    shipmenu = require("src.scenes.shipmenu"),
    rest = require("src.scenes.rest"),
    damage = require("src.scenes.damage"),
    log = require("src.scenes.log"),
    confirm = require("src.scenes.confirm"),
    settings = require("src.scenes.settings"),
    records = require("src.scenes.records"),
    help = require("src.scenes.help"),
    gameover = require("src.scenes.gameover"),
}

local app = {
    version = VERSION,
    stack = {},
    fade = 0,
    focused = true,
    redrawRequested = true,
    activeUntil = 0,
    framesDrawn = 0,
}
_G.app = app

-- Scene stack ---------------------------------------------------------------

function app.top()
    return app.stack[#app.stack]
end

function app.find(name)
    for k = #app.stack, 1, -1 do
        if app.stack[k].name == name then return app.stack[k] end
    end
end

local function create(name, ...)
    local scene = SCENES[name].new(app, ...)
    scene.name = name
    return scene
end

-- Replace everything with a new full-screen scene.
function app.setScene(name, ...)
    for k = #app.stack, 1, -1 do
        local s = app.stack[k]
        if s.leave then s:leave() end
    end
    app.stack = { create(name, ...) }
    app.fade = 1
    input.reset()
    local s = app.top()
    if s.enter then s:enter() end
end

-- Open a scene on top of the current one (menus, dialogs).
function app.push(name, ...)
    local scene = create(name, ...)
    app.stack[#app.stack + 1] = scene
    input.reset()
    if scene.enter then scene:enter() end
    return scene
end

function app.pop()
    local s = table.remove(app.stack)
    if s and s.leave then s:leave() end
    input.reset()
    local top = app.top()
    if top and top.resume then top:resume() end
end

-- Pop overlays until `name` is on top.
function app.popTo(name)
    while #app.stack > 1 and app.top().name ~= name do app.pop() end
end

-- Games and saving ------------------------------------------------------------

function app.hasGame()
    return app.game ~= nil and not app.game.over
end

function app.saveGame()
    if app.game and not app.game.over then
        storage.saveGame(app.game:serialize())
    else
        storage.clearGame()
    end
end

function app.newGame(skill, length)
    app.settings.skill, app.settings.length = skill, length
    app.saveSettings()
    local seed = os.time() * 1000 + math.floor((love.timer.getTime() % 1) * 1000)
    app.game = Game.new({ skill = skill, length = length, seed = seed })
    app.saveGame()
    app.setScene("play")
end

-- Record a finished game. Returns its place in the records, if it made it.
function app.recordGame()
    local g = app.game
    local total = g:score()
    local place = storage.addRecord(app.records, {
        score = total, won = g.over.won, skill = g.skill, length = g.length,
        date = os.date("%Y-%m-%d"), reason = g.over.reason,
        killed = g.stats.killed + g.stats.captured, klingons = g.p.klings,
    })
    storage.saveRecords(app.records)
    storage.clearGame()
    return place
end

function app.saveSettings()
    storage.saveSettings(app.settings)
end

function app.applySettings()
    theme.use(app.settings.theme)
    sound.enabled = app.settings.sound
end

function app.quit()
    if app.game then app.saveGame() end
    love.event.quit()
end

-- Idle rendering -------------------------------------------------------------
-- Most of the time the screen is a still picture, so it is only redrawn
-- when something changed: after input (plus a short window for menu
-- animations), while the top scene reports busy(), or when a scene asks via
-- app.requestRedraw(). Otherwise the loop sleeps and checks for input 60
-- times a second, so buttons respond just as quickly.

local AFTER_INPUT = 0.45   -- keep drawing this long after any input
local IDLE_SLEEP = 1 / 60  -- how often to check for input while idle

function app.requestRedraw()
    app.redrawRequested = true
end

function app.wake()
    app.redrawRequested = true
    app.activeUntil = love.timer.getTime() + AFTER_INPUT
end

function app.needsFrame()
    if app.redrawRequested or app.fade > 0 then return true end
    if love.timer.getTime() < app.activeUntil then return true end
    for k = #app.stack, 1, -1 do
        local s = app.stack[k]
        if s.busy and s:busy() then return true end
        if not s.overlay then break end
    end
    return false
end

-- Stick movement only matters once it crosses the threshold, and then
-- input.lua fires an action, which wakes the screen itself.
local QUIET_EVENTS = { gamepadaxis = true, joystickaxis = true }

function love.run()
    love.load(love.arg.parseGameArguments(arg), arg)
    love.timer.step()
    local dt = 0
    return function()
        love.event.pump()
        for name, a, b, c, d, e, f in love.event.poll() do
            if name == "quit" then
                if not love.quit() then return a or 0 end
            end
            love.handlers[name](a, b, c, d, e, f)
            if not QUIET_EVENTS[name] then app.wake() end
        end

        dt = love.timer.step()
        love.update(dt)

        if love.graphics.isActive() and app.needsFrame() then
            app.redrawRequested = false
            love.graphics.origin()
            love.draw()
            love.graphics.present()
            app.framesDrawn = app.framesDrawn + 1
            love.timer.sleep(0.001)
        else
            love.timer.sleep(IDLE_SLEEP)
        end
    end
end

-- LÖVE callbacks --------------------------------------------------------------

local function parseResolution(args)
    for _, a in ipairs(args or {}) do
        local w, h = tostring(a):match("^(%d+)x(%d+)$")
        if w then return tonumber(w), tonumber(h) end
    end
end

function love.load(args)
    love.graphics.setDefaultFilter("linear", "linear")
    love.graphics.setLineStyle("smooth")

    local w, h = parseResolution(args)
    if w and h and (w ~= love.graphics.getWidth() or h ~= love.graphics.getHeight()) then
        love.window.setMode(w, h, { vsync = 1, highdpi = os.getenv("RGTREK_LOWDPI") == nil })
    end
    ui.resize(love.graphics.getPixelWidth(), love.graphics.getPixelHeight())

    app.settings = storage.loadSettings()
    app.records = storage.loadRecords()
    app.applySettings()
    sound.load()

    local saved = storage.loadGame()
    if saved then
        app.game = Game.deserialize(saved)
        if not app.game then storage.clearGame() end
    end

    input.handler = function(action)
        app.wake()
        local s = app.top()
        if s and s.action then s:action(action) end
    end

    app.setScene("title")
    app.fade = 0

    if os.getenv("RGTREK_AUTOSHOT") then
        require("dev.autoshot").start(app)
    elseif os.getenv("RGTREK_FUZZ") then
        require("dev.fuzz").start(app, os.getenv("RGTREK_FUZZ"))
    elseif os.getenv("RGTREK_IDLETEST") then
        require("dev.idletest").start(app)
    end
end

function love.update(dt)
    dt = math.min(dt, 1 / 15)
    input.update(dt)
    -- every scene updates, so animations under an overlay keep going
    for k = 1, #app.stack do
        local s = app.stack[k]
        if s.update then s:update(dt, k == #app.stack) end
    end
    if app.fade > 0 then app.fade = math.max(0, app.fade - dt * 6) end
end

function love.draw()
    local bg = theme.get("bg")
    love.graphics.clear(bg[1], bg[2], bg[3], 1)

    -- Draw from the topmost full-screen scene upward, so overlays show
    -- the scene beneath them.
    local first = 1
    for k = #app.stack, 1, -1 do
        if not app.stack[k].overlay then
            first = k
            break
        end
    end

    -- Work in screen pixels: on a Retina Mac the window is scaled 2x.
    love.graphics.push()
    love.graphics.scale(1 / love.window.getDPIScale())
    ui.begin()
    for k = first, #app.stack do
        love.graphics.setColor(1, 1, 1, 1)
        app.stack[k]:draw()
    end
    if app.fade > 0 then
        theme.set("bg", app.fade)
        love.graphics.rectangle("fill", 0, 0, ui.W, ui.H)
    end
    ui.finish()
    love.graphics.pop()
end

function love.keypressed(key, scancode, isrepeat)
    input.keypressed(key, isrepeat)
end

function love.keyreleased(key)
    input.keyreleased(key)
end

function love.gamepadpressed(js, button)
    input.gamepadpressed(js, button)
end

function love.gamepadreleased(js, button)
    input.gamepadreleased(js, button)
end

function love.gamepadaxis(js, axis, value)
    input.gamepadaxis(js, axis, value)
end

function love.resize()
    ui.resize(love.graphics.getPixelWidth(), love.graphics.getPixelHeight())
end

function love.focus(f)
    app.focused = f
    if not f and app.game then app.saveGame() end
end

function love.quit()
    if app.game then app.saveGame() end
    return false
end
