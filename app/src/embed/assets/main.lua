local TILE_SIZE = 40
local GRID_W, GRID_H = 15, 15
local LERP_SPEED = 15
local OFFSET_X, OFFSET_Y = 0, 0

-- НОВОЕ: Состояние игры и параметры меню
local gameState = "menu"
local menuCube = { sx = 1, sy = 1, press = 0 }
local playBtn = { x = 0, y = 0, w = 200, h = 60, hover = false }

local player = { x = 2, y = 2, rx = 2, ry = 2, sx = 1, sy = 1, vx = 0, vy = 0, angle = 0, dead = false }
local exit = { x = 14, y = 14 }
local enemies, walls = {}, {}
local roomCount = 1
local gameOver = false

local shakeIntensity = 0
local deathTimer = 0
local deathFade = 0
local winTimer = 0 
local fragments = {}
local bigCube = { y = -100, shake = 0, cracked = false, scale = 1 }
local restartBtn = { x = 0, y = 0, w = 180, h = 50, hover = false }

local touchStartX, touchStartY = 0, 0
local swipeThreshold = 30

local sounds = {}

local function createSfx(freq, duration, type)
    local rate = 44100
    local length = math.floor(rate * duration)
    local data = love.sound.newSoundData(length, rate, 16, 1)
    for i = 0, length - 1 do
        local t = i / rate
        local val = 0
        if type == "sine" then
            val = math.sin(t * freq * math.pi * 2) * math.exp(-t * 10)
        elseif type == "noise" then
            val = (math.random() * 2 - 1) * math.exp(-t * 20)
        elseif type == "thump" then
            val = math.sin(t * freq * (1 - t) * math.pi * 2) * math.exp(-t * 5)
        end
        data:setSample(i, val * 0.5)
    end
    return love.audio.newSource(data)
end

function updateLayout()
    local sw, sh = love.graphics.getDimensions()
    local padding = 20
    local availableW = sw - padding * 2
    local availableH = sh - padding * 3 - 50 
    
    TILE_SIZE = math.min(availableW / GRID_W, availableH / GRID_H)
    OFFSET_X = (sw - (GRID_W * TILE_SIZE)) / 2
    OFFSET_Y = (sh - (GRID_H * TILE_SIZE)) / 2
    
    -- Центрируем кнопку Play
    playBtn.x = sw/2 - playBtn.w/2
    playBtn.y = sh/2 + 120
end

function love.load()
    love.window.setMode(0, 0, {fullscreen = true, resizable = true})
    updateLayout()
    
    sounds.move = createSfx(600, 0.1, "sine")
    sounds.deathHit = createSfx(100, 0.4, "thump")
    sounds.shatter = createSfx(800, 0.3, "noise")
    
    generateRoom()
end

function love.resize(w, h)
    updateLayout()
end

function triggerDeath(enemy)
    if player.dead or winTimer > 0 then return end
    player.dead = true
    shakeIntensity = 15
    sounds.deathHit:play()
    enemy.x, enemy.y = player.x, player.y
    local dx = player.x - enemy.rx
    local dy = player.y - enemy.ry
    if dx == 0 and dy == 0 then dy = -1 end 
    player.vx, player.vy = dx * 900, dy * 900
end

function generateRoom()
    walls, enemies = {}, {}
    player.dead, gameOver = false, false
    player.vx, player.vy, player.angle = 0, 0, 0
    player.x, player.y, player.rx, player.ry = 2, 2, 2, 2
    player.sx, player.sy = 1, 1
    deathFade, deathTimer, winTimer = 0, 0, 0
    shakeIntensity = 0
    bigCube = { y = -100, shake = 0, cracked = false, scale = 1 }
    fragments = {}
    exit.x, exit.y = GRID_W - 1, GRID_H - 1

    for i = 1, 30 do
        local wx, wy = love.math.random(1, GRID_W), love.math.random(1, GRID_H)
        if (wx ~= player.x or wy ~= player.y) and (wx ~= exit.x or wy ~= exit.y) then
            walls[wx .. "," .. wy] = true
        end
    end

    local count = math.min(math.floor(roomCount / 2) + 2, 10)
    local types = {"chaser", "mimic", "patrol"}
    local spawned = 0
    while spawned < count do
        local ex, ey = love.math.random(1, GRID_W), love.math.random(1, GRID_H)
        local occupied = (ex == player.x and ey == player.y) or (ex == exit.x and ey == exit.y) or walls[ex .. "," .. ey]
        for _, e in ipairs(enemies) do
            if e.x == ex and e.y == ey then occupied = true end
        end
        if not occupied and (math.abs(ex - player.x) > 2 or math.abs(ey - player.y) > 2) then
            table.insert(enemies, { x = ex, y = ey, rx = ex, ry = ey, sx = 1, sy = 1, 
                type = types[love.math.random(1, #types)], dir = 1, steps = 0 })
            spawned = spawned + 1
        end
    end
end

function updateDeath(dt)
    deathTimer = deathTimer + dt
    shakeIntensity = math.max(0, shakeIntensity - dt * 30)
    player.rx = player.rx + player.vx * dt / TILE_SIZE
    player.ry = player.ry + player.vy * dt / TILE_SIZE
    player.angle = player.angle + 20 * dt
    for _, e in ipairs(enemies) do
        e.rx = e.rx + (e.x - e.rx) * LERP_SPEED * dt
        e.ry = e.ry + (e.y - e.ry) * LERP_SPEED * dt
    end
    if deathTimer > 2.0 then
        deathFade = math.min(1, deathFade + dt * 1.5)
    end
    if deathFade > 0.7 then
        if not bigCube.cracked then
            bigCube.y = bigCube.y + (love.graphics.getHeight()/2.5 - bigCube.y) * 5 * dt
            bigCube.shake = math.sin(deathTimer * 40) * 5
            if deathTimer > 4.5 then
                bigCube.cracked = true
                shakeIntensity = 10
                sounds.shatter:play()
                for i = 1, 6 do
                    table.insert(fragments, {
                        x = love.graphics.getWidth()/2, y = love.graphics.getHeight()/2.5,
                        vx = love.math.random(-200, 200), vy = love.math.random(-400, -100),
                        ang = 0, va = love.math.random(-5, 5)
                    })
                end
            end
        else
            for _, f in ipairs(fragments) do
                f.vy = f.vy + 1200 * dt
                f.x, f.y = f.x + f.vx * dt, f.y + f.vy * dt
                f.ang = f.ang + f.va * dt
                if f.y > love.graphics.getHeight() - 100 then f.y = love.graphics.getHeight() - 100; f.vx = 0; f.va = 0 end
            end
        end
    end
    if bigCube.cracked then
        local mx, my = love.mouse.getPosition()
        restartBtn.x, restartBtn.y = love.graphics.getWidth()/2 - 90, love.graphics.getHeight() * 0.75
        restartBtn.hover = (mx > restartBtn.x and mx < restartBtn.x + restartBtn.w and my > restartBtn.y and my < restartBtn.y + restartBtn.h)
    end
end

function love.update(dt)
    if gameState == "menu" then
        -- Возвращаем куб в исходное состояние (анимация сплющивания)
        menuCube.sx = menuCube.sx + (1 - menuCube.sx) * 8 * dt
        menuCube.sy = menuCube.sy + (1 - menuCube.sy) * 8 * dt
        local mx, my = love.mouse.getPosition()
        playBtn.hover = (mx > playBtn.x and mx < playBtn.x + playBtn.w and my > playBtn.y and my < playBtn.y + playBtn.h)
    else
        if player.dead then
            updateDeath(dt)
        elseif winTimer > 0 then
            winTimer = winTimer + dt
            shakeIntensity = winTimer * 3 
            player.rx = player.rx + (player.x - player.rx) * LERP_SPEED * dt
            player.ry = player.ry + (player.y - player.ry) * LERP_SPEED * dt
            player.sx = math.max(0, player.sx - dt * 0.7)
            player.sy = math.max(0, player.sy - dt * 0.7)
            if winTimer > 1.5 then
                sounds.shatter:play()
                roomCount = roomCount + 1
                generateRoom()
            end
        else
            player.rx = player.rx + (player.x - player.rx) * LERP_SPEED * dt
            player.ry = player.ry + (player.y - player.ry) * LERP_SPEED * dt
            player.sx = player.sx + (1 - player.sx) * 12 * dt
            player.sy = player.sy + (1 - player.sy) * 12 * dt
            for _, e in ipairs(enemies) do
                e.rx = e.rx + (e.x - e.rx) * LERP_SPEED * dt
                e.ry = e.ry + (e.y - e.ry) * LERP_SPEED * dt
                e.sx = e.sx + (1 - e.sx) * 12 * dt
                e.sy = e.sy + (1 - e.sy) * 12 * dt
            end
        end
    end
end

local function drawBox(tx, ty, sx, sy, col, ang)
    local x = OFFSET_X + (tx-0.5)*TILE_SIZE
    local y = OFFSET_Y + (ty-0.5)*TILE_SIZE
    local sz = TILE_SIZE * 0.8
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(ang or 0)
    -- Тень под боксами
    love.graphics.setColor(0, 0, 0, 0.15)
    love.graphics.rectangle("fill", -sz*0.4*sx - 2, -sz*0.4*sy + 4, sz*sx, sz*sy, 5)
    love.graphics.setColor(unpack(col))
    love.graphics.rectangle("fill", -sz*0.4*sx, -sz*0.4*sy, sz*sx, sz*sy, 5)
    love.graphics.pop()
end

function love.draw()
    if gameState == "menu" then
        love.graphics.clear(0.95, 0.95, 0.96)
        local cx, cy = love.graphics.getWidth()/2, love.graphics.getHeight()/2 - 40
        
        -- Тень под центральным кубом
        love.graphics.setColor(0, 0, 0, 0.1)
        love.graphics.ellipse("fill", cx, cy + 60, 60 * menuCube.sx, 15)
        
        -- Центральный куб
        love.graphics.push()
        love.graphics.translate(cx, cy)
        love.graphics.scale(menuCube.sx, menuCube.sy)
        love.graphics.setColor(0.8, 0.2, 0.2)
        love.graphics.rectangle("fill", -50, -50, 100, 100, 15)
        love.graphics.pop()
        
        -- Кнопка Play с тенью
        local b = playBtn
        love.graphics.setColor(0, 0, 0, 0.1)
        love.graphics.rectangle("fill", b.x + 4, b.y + 4, b.w, b.h, 15)
        love.graphics.setColor(b.hover and {0.45, 0.85, 0.55} or {0.4, 0.8, 0.5})
        love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 15)
        love.graphics.setColor(1, 1, 1)
        local font = love.graphics.getFont()
        love.graphics.printf("PLAY", b.x, b.y + (b.h - font:getHeight())/2, b.w, "center")
        
    else
        -- Весь твой игровой процесс
        love.graphics.push()
        if shakeIntensity > 0 then
            love.graphics.translate(love.math.random(-shakeIntensity, shakeIntensity), love.math.random(-shakeIntensity, shakeIntensity))
        end
        love.graphics.clear(0.95, 0.95, 0.96)
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("fill", OFFSET_X, OFFSET_Y, GRID_W * TILE_SIZE, GRID_H * TILE_SIZE, 10, 10)
        for k, _ in pairs(walls) do
            local x, y = k:match("([^,]+),([^,]+)")
            drawBox(tonumber(x), tonumber(y), 1, 1, {0.8, 0.8, 0.85})
        end
        drawBox(exit.x, exit.y, 1, 1, {0.4, 0.8, 0.5})
        for _, e in ipairs(enemies) do 
            local col = {0.2, 0.4, 0.8}
            if e.type == "mimic" then col = {0.6, 0.3, 0.8}
            elseif e.type == "patrol" then col = {0.9, 0.6, 0.2} end
            drawBox(e.rx, e.ry, e.sx, e.sy, col) 
        end
        if deathFade < 1 then
            drawBox(player.rx, player.ry, player.sx, player.sy, {0.8, 0.2, 0.2}, player.angle)
        end
        if winTimer > 0 then
            local px = OFFSET_X + (player.rx-0.5)*TILE_SIZE
            local py = OFFSET_Y + (player.ry-0.5)*TILE_SIZE
            love.graphics.setColor(0.4, 0.8, 0.5, 0.7)
            for i = 1, 8 do
                local angle = (winTimer * 10) + (i * (math.pi * 2 / 8))
                local dist = 50 * (1.5 - winTimer) / 1.5
                local ox = math.cos(angle) * dist
                local oy = math.sin(angle) * dist
                love.graphics.circle("fill", px + ox, py + oy, 4)
            end
            if winTimer > 1.3 then
                love.graphics.setColor(1, 1, 1, (winTimer-1.3)/0.2)
                love.graphics.rectangle("fill", -100, -100, 4000, 4000)
            end
        end
        love.graphics.pop()
        if deathFade > 0 then
            love.graphics.setColor(0.05, 0.05, 0.1, deathFade * 0.98)
            love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
            local cx = love.graphics.getWidth()/2
            if not bigCube.cracked then
                love.graphics.setColor(0, 0, 0, deathFade * 0.3)
                love.graphics.rectangle("fill", cx + bigCube.shake - 54, bigCube.y - 54, 110, 110, 10)
                love.graphics.setColor(0.8, 0.2, 0.2, deathFade)
                love.graphics.rectangle("fill", cx + bigCube.shake - 50, bigCube.y - 50, 100, 100, 10)
            else
                for _, f in ipairs(fragments) do
                    love.graphics.push()
                    love.graphics.translate(f.x, f.y); love.graphics.rotate(f.ang)
                    love.graphics.setColor(0.8, 0.2, 0.2, deathFade)
                    love.graphics.rectangle("fill", -15, -15, 30, 30, 5)
                    love.graphics.pop()
                end
                love.graphics.setColor(1, 1, 1, deathFade)
                local fontBig = love.graphics.newFont(love.graphics.getWidth() > 500 and 40 or 24)
                love.graphics.setFont(fontBig)
                love.graphics.printf("DESTINY BROKEN", 0, love.graphics.getHeight() * 0.2, love.graphics.getWidth(), "center")
                love.graphics.printf("ROOMS: " .. roomCount, 0, love.graphics.getHeight() * 0.6, love.graphics.getWidth(), "center")
                
                -- РЕСТАРТ КНОПКА ФИКС ТЕКСТА
                local b = restartBtn
                love.graphics.setColor(0, 0, 0, deathFade * 0.2)
                love.graphics.rectangle("fill", b.x + 4, b.y + 4, b.w, b.h, 10)
                love.graphics.setColor(b.hover and {0.9, 0.3, 0.3} or {0.8, 0.2, 0.2})
                love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 10)
                love.graphics.setColor(1, 1, 1)
                -- Текст центрируется по фактическим координатам кнопки
                local fontBtn = love.graphics.getFont()
                love.graphics.printf("RESTART", b.x, b.y + (b.h - fontBtn:getHeight())/2, b.w, "center")
            end
        end
    end
end

function handleMove(dx, dy)
    if player.dead or winTimer > 0 or gameState == "menu" then return end
    local nx, ny = player.x + dx, player.y + dy
    if nx == exit.x and ny == exit.y then
        player.x, player.y = nx, ny
        winTimer = 0.001 
        sounds.move:play()
    elseif canMove(nx, ny) then
        player.x, player.y = nx, ny
        player.sx, player.sy = 0.8, 1.2
        sounds.move:stop(); sounds.move:play()
        moveEnemies(dx, dy)
    else
        player.rx = player.rx + dx * 0.25
        player.ry = player.ry + dy * 0.25
        player.sx, player.sy = 1.2, 0.8
    end
end

function love.touchpressed(id, x, y)
    touchStartX, touchStartY = x, y
    
    if gameState == "menu" then
        local cx, cy = love.graphics.getWidth()/2, love.graphics.getHeight()/2 - 40
        -- Нажатие на куб
        if x > cx - 50 and x < cx + 50 and y > cy - 50 and y < cy + 50 then
            menuCube.sx, menuCube.sy = 1.6, 0.4
            sounds.move:play()
        end
        -- Нажатие на Play
        if x > playBtn.x and x < playBtn.x + playBtn.w and y > playBtn.y and y < playBtn.y + playBtn.h then
            gameState = "playing"
            generateRoom()
        end
    elseif bigCube.cracked then
        if x > restartBtn.x and x < restartBtn.x + restartBtn.w and y > restartBtn.y and y < restartBtn.y + restartBtn.h then
            roomCount = 1
            generateRoom()
            sounds.move:play()
        end
    end
end

function love.touchreleased(id, x, y)
    local dx, dy = x - touchStartX, y - touchStartY
    if math.abs(dx) > math.abs(dy) then
        if math.abs(dx) > swipeThreshold then
            handleMove(dx > 0 and 1 or -1, 0)
        end
    else
        if math.abs(dy) > swipeThreshold then
            handleMove(0, dy > 0 and 1 or -1)
        end
    end
end

function love.mousepressed(x, y, button)
    -- Перенаправляем на логику тача для универсальности
    love.touchpressed(1, x, y)
end

function love.keypressed(key)
    if gameState == "menu" and key == "return" then
        gameState = "playing"
        generateRoom()
    end
    local dx, dy = 0, 0
    if key == "up" or key == "w" then dy = -1
    elseif key == "down" or key == "s" then dy = 1
    elseif key == "left" or key == "a" then dx = -1
    elseif key == "right" or key == "d" then dx = 1 end
    if dx ~= 0 or dy ~= 0 then handleMove(dx, dy) end
end

function canMove(x, y)
    if x < 1 or x > GRID_W or y < 1 or y > GRID_H or walls[x..","..y] then return false end
    return true
end

function moveEnemies(pdx, pdy)
    for _, e in ipairs(enemies) do
        local nx, ny = e.x, e.y
        if e.type == "chaser" then
            if e.x < player.x then nx = nx + 1 elseif e.x > player.x then nx = nx - 1
            elseif e.y < player.y then ny = ny + 1 elseif e.y > player.y then ny = ny - 1 end
        elseif e.type == "mimic" then nx, ny = e.x + pdx, e.y + pdy
        elseif e.type == "patrol" then
            local tx = e.x + e.dir
            if canMove(tx, e.y) and e.steps < 3 then nx, e.steps = tx, e.steps + 1
            else e.dir, e.steps = -e.dir, 0 end
        end
        local enemyBlocking = false
        for _, other in ipairs(enemies) do
            if other ~= e and other.x == nx and other.y == ny then
                enemyBlocking = true
                break
            end
        end
        if canMove(nx, ny) and not enemyBlocking then 
            e.x, e.y = nx, ny 
            e.sx, e.sy = 0.8, 1.2 
        end
        if e.x == player.x and e.y == player.y then triggerDeath(e) end
    end
end
