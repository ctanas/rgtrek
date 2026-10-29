function love.conf(t)
    t.version = "11.5"
    t.identity = "rgtrek"
    t.console = false

    t.window.title = "rgTrek"
    t.window.width = 720
    t.window.height = 480
    t.window.resizable = false
    t.window.vsync = 1
    -- Sharp text on Retina Macs; no effect on handhelds. RGTREK_LOWDPI=1
    -- renders at the device's real 720x480, for checking pixel alignment.
    t.window.highdpi = os.getenv("RGTREK_LOWDPI") == nil

    t.modules.joystick = true
    t.modules.audio = true
    t.modules.sound = true
    t.modules.mouse = false
    t.modules.touch = false
    t.modules.physics = false
    t.modules.video = false
    t.modules.thread = false
end
