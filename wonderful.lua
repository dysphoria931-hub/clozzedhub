--[[
    WonderfulHub — Dead Rails
    self-written, self-contained, no external loader
    place: Dead Rails Alpha (116495829188952)
    executor: Delta / Codex / Redz — needs Drawing, gethui (fallback: CoreGui)
]]

if game.PlaceId ~= 116495829188952 then
    return warn("[wonderfulhub] wrong game — Dead Rails only")
end

-- ─────────────────────────────────────────────────────────────
-- SERVICES
-- ─────────────────────────────────────────────────────────────
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local CoreGui           = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP     = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ─────────────────────────────────────────────────────────────
-- CONFIG
-- ─────────────────────────────────────────────────────────────
local cfg = {
    esp          = false,
    espBoxes     = true,
    espNames     = true,
    espHealth    = true,
    espDistance  = true,
    espFOV       = 0,        -- 0 = весь экран; >0 = только в радиусе (studs)
    itemsESP     = false,
    killAura     = false,
    auraRange    = 18,
    autoCollect  = false,
    collectRange = 60,
    autoFuel     = false,
    autoHeal     = false,
    noclip       = false,
    fullBright   = false,
    walkSpeed    = nil,      -- nil = не трогать
    jumpPower    = nil,
}

local ITEM_PATTERNS = { "bond", "money", "cash", "medicine", "medkit",
                        "weapon", "ammo", "bottle", "glass", "coal",
                        "barrel", "wood", "scrap", "ore" }

-- ─────────────────────────────────────────────────────────────
-- UTIL
-- ─────────────────────────────────────────────────────────────
local function char()  return LP.Character end
local function hrp()   local c = char(); return c and c:FindFirstChild("HumanoidRootPart") end
local function hum()   local c = char(); return c and c:FindFirstChildOfClass("Humanoid") end

local function isItem(name)
    local n = name:lower()
    for _, p in ipairs(ITEM_PATTERNS) do
        if n:find(p, 1, true) then return true end
    end
    return false
end

local function w2s(worldPos)
    local sp, on = Camera:WorldToViewportPoint(worldPos)
    return Vector2.new(sp.X, sp.Y), on and sp.Z > 0
end

local function notify(text)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "WonderfulHub", Text = text, Duration = 3,
        })
    end)
end

-- безопасный цикл: ошибка не убивает поток
local function safeLoop(fn, dt)
    task.spawn(function()
        while true do
            local ok, err = pcall(fn)
            if not ok then warn("[wonderfulhub] " .. tostring(err)) end
            task.wait(dt or 0.1)
        end
    end)
end

-- ─────────────────────────────────────────────────────────────
-- ESP (Drawing)
-- ─────────────────────────────────────────────────────────────
local drawingOk = (typeof and typeof(Drawing) == "table") or (Drawing ~= nil)
local espStore  = {}   -- [player] = { box, name, dist, hpBg, hpFill }
local itemStore = {}   -- [part]   = { box, name }

local function makeEspEntry()
    local e = {}
    e.box   = Drawing.new("Square")
    e.box.Thickness = 1
    e.box.Color     = Color3.fromRGB(255, 40, 40)
    e.box.Filled    = false
    e.box.Visible   = false

    e.name  = Drawing.new("Text")
    e.name.Size   = 14
    e.name.Center = true
    e.name.Outline = true
    e.name.Color  = Color3.new(1, 1, 1)
    e.name.Visible = false

    e.dist  = Drawing.new("Text")
    e.dist.Size   = 12
    e.dist.Center = true
    e.dist.Outline = true
    e.dist.Color  = Color3.fromRGB(200, 200, 200)
    e.dist.Visible = false

    e.hpBg   = Drawing.new("Square")
    e.hpBg.Thickness = 0
    e.hpBg.Filled    = true
    e.hpBg.Color     = Color3.fromRGB(0, 0, 0)
    e.hpBg.Visible   = false

    e.hpFill = Drawing.new("Square")
    e.hpFill.Thickness = 0
    e.hpFill.Filled    = true
    e.hpFill.Color     = Color3.fromRGB(60, 220, 60)
    e.hpFill.Visible   = false

    return e
end

local function destroyEspEntry(e)
    for _, v in pairs(e) do pcall(function() v:Remove() end) end
end

local function updateESP()
    if not drawingOk then return end

    local lhrp = hrp()
    local lpos = lhrp and lhrp.Position or Vector3.zero

    -- hide everything first
    for _, e in pairs(espStore) do
        if e.box then e.box.Visible = false end
        if e.name then e.name.Visible = false end
        if e.dist then e.dist.Visible = false end
        if e.hpBg then e.hpBg.Visible = false end
        if e.hpFill then e.hpFill.Visible = false end
    end
    if not cfg.esp then return end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LP then continue end
        local c   = plr.Character
        local phrp = c and c:FindFirstChild("HumanoidRootPart")
        local phum = c and c:FindFirstChildOfClass("Humanoid")
        if not phrp or not phum or phum.Health <= 0 then continue end

        local dist3d = (phrp.Position - lpos).Magnitude
        if cfg.espFOV > 0 and dist3d > cfg.espFOV then continue end

        local head = phrp.Position + Vector3.new(0, 1.5, 0)
        local feet = phrp.Position - Vector3.new(0, 2.7, 0)
        local h2d, hOn = w2s(head)
        local f2d, fOn = w2s(feet)
        if not (hOn and fOn) then continue end

        local h = f2d.Y - h2d.Y
        if h < 8 then continue end
        local w = h * 0.45
        local x = h2d.X - w / 2
        local y = h2d.Y

        local e = espStore[plr] or makeEspEntry()
        espStore[plr] = e

        if cfg.espBoxes then
            e.box.Size     = Vector2.new(w, h)
            e.box.Position = Vector2.new(x, y)
            e.box.Visible  = true
        end
        if cfg.espNames then
            e.name.Text    = plr.Name
            e.name.Position = Vector2.new(h2d.X, y - 16)
            e.name.Visible = true
        end
        if cfg.espDistance then
            e.dist.Text    = string.format("%d m", math.floor(dist3d))
            e.dist.Position = Vector2.new(h2d.X, y + h + 2)
            e.dist.Visible = true
        end
        if cfg.espHealth then
            local hpFrac = math.clamp(phum.Health / phum.MaxHealth, 0, 1)
            local barX = x - 6
            e.hpBg.Size     = Vector2.new(3, h)
            e.hpBg.Position = Vector2.new(barX, y)
            e.hpBg.Color    = Color3.fromRGB(30, 0, 0)
            e.hpBg.Visible  = true
            e.hpFill.Size   = Vector2.new(3, h * hpFrac)
            e.hpFill.Position = Vector2.new(barX, y + h - h * hpFrac)
            e.hpFill.Color  = hpFrac > 0.6 and Color3.fromRGB(60, 220, 60)
                          or hpFrac > 0.3 and Color3.fromRGB(240, 200, 40)
                          or Color3.fromRGB(240, 60, 60)
            e.hpFill.Visible = true
        end
    end
end

-- items ESP — отдельная простыня, лёгкая
local function updateItemsESP()
    if not (drawingOk and cfg.itemsESP) then
        for _, e in pairs(itemStore) do
            if e.box then e.box.Visible = false end
            if e.name then e.name.Visible = false end
        end
        return
    end

    local lhrp = hrp()
    local lpos = lhrp and lhrp.Position or Vector3.zero

    for _, e in pairs(itemStore) do
        if e.box then e.box.Visible = false end
        if e.name then e.name.Visible = false end
    end

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if not obj:IsA("BasePart") then continue end
        if not isItem(obj.Name) then continue end
        local dist = (obj.Position - lpos).Magnitude
        if dist > 120 then continue end

        local p2d, on = w2s(obj.Position)
        if not on then continue end

        local e = itemStore[obj]
        if not e then
            local box = Drawing.new("Square")
            box.Thickness = 1
            box.Color     = Color3.fromRGB(80, 200, 255)
            box.Filled    = false
            local name = Drawing.new("Text")
            name.Size = 12
            name.Center = true
            name.Outline = true
            name.Color = Color3.fromRGB(80, 200, 255)
            e = { box = box, name = name }
            itemStore[obj] = e
        end

        local size = 6
        e.box.Size     = Vector2.new(size * 2, size * 2)
        e.box.Position = Vector2.new(p2d.X - size, p2d.Y - size)
        e.box.Visible  = true

        e.name.Text    = obj.Name
        e.name.Position = Vector2.new(p2d.X, p2d.Y - 20)
        e.name.Visible = true
    end
end

-- ─────────────────────────────────────────────────────────────
-- AUTO COLLECT / FUEL
-- ─────────────────────────────────────────────────────────────
local function teleportTo(pos)
    local h = hrp()
    if h then h.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) end
end

local function scanAndCollect(range)
    local lhrp = hrp()
    if not lhrp then return end
    local lpos = lhrp.Position
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if not obj:IsA("BasePart") then continue end
        if not isItem(obj.Name) then continue end
        local d = (obj.Position - lpos).Magnitude
        if d <= range then
            teleportTo(obj.Position)
            task.wait(0.05)
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- KILL AURA
-- ─────────────────────────────────────────────────────────────
local function killAuraTick()
    local c   = char()
    local h   = c and c:FindFirstChild("HumanoidRootPart")
    if not h then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LP then continue end
        local pc = plr.Character
        local phrp = pc and pc:FindFirstChild("HumanoidRootPart")
        local phum = pc and pc:FindFirstChildOfClass("Humanoid")
        if not phrp or not phum or phum.Health <= 0 then continue end
        if (phrp.Position - h.Position).Magnitude > cfg.auraRange then continue end

        local tool = c:FindFirstChildOfClass("Tool")
        if tool then pcall(function() tool:Activate() end) end
        pcall(function()
            firetouchinterest(h, phrp, 0)
            task.wait()
            firetouchinterest(h, phrp, 1)
        end)
    end
end

-- ─────────────────────────────────────────────────────────────
-- MISC (noclip, heal, bright, speed)
-- ─────────────────────────────────────────────────────────────
local function noclipTick()
    if not cfg.noclip then return end
    local c = char()
    if not c then return end
    for _, part in ipairs(c:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            part.CanCollide = false
        end
    end
end

local function healTick()
    if not cfg.autoHeal then return end
    local h = hum()
    if h and h.Health < h.MaxHealth then
        h.Health = h.MaxHealth
    end
end

local function applyBright()
    if cfg.fullBright then
        if not Lighting:FindFirstChild("WonderfulHubBright") then
            local cl = Instance.new("ColorCorrectionEffect")
            cl.Name = "WonderfulHubBright"
            cl.Brightness = 0.4
            cl.Contrast = 0.1
            cl.Parent = Lighting
        end
        Lighting.Ambient = Color3.fromRGB(200, 200, 200)
        Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
    else
        local cl = Lighting:FindFirstChild("WonderfulHubBright")
        if cl then cl:Destroy() end
        Lighting.Ambient = Color3.fromRGB(70, 70, 70)
        Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
    end
end

local function applyMovement()
    local h = hum()
    if not h then return end
    h.WalkSpeed  = cfg.walkSpeed  or 16
    h.JumpPower  = cfg.jumpPower  or 50
    h.UseJumpPower = true
end

-- ─────────────────────────────────────────────────────────────
-- MAIN LOOPS
-- ─────────────────────────────────────────────────────────────
RunService.RenderStepped:Connect(function()
    pcall(updateESP)
    pcall(updateItemsESP)
end)

safeLoop(function()
    if cfg.killAura then killAuraTick() end
end, 0.1)

safeLoop(function()
    if cfg.autoCollect then scanAndCollect(cfg.collectRange) end
end, 0.8)

safeLoop(function()
    if cfg.autoFuel then scanAndCollect(20) end
end, 0.4)

safeLoop(function()
    noclipTick()
    healTick()
end, 0.2)

applyBright()

-- respawn handling: скорость/прыжок переприменяются
LP.CharacterAdded:Connect(function()
    task.wait(1)
    applyMovement()
end)

-- ─────────────────────────────────────────────────────────────
-- UI
-- ─────────────────────────────────────────────────────────────
local uiParent = (gethui and gethui()) or CoreGui

-- сносим старую копию, если был перезапуск
pcall(function()
    local old = uiParent:FindFirstChild("WonderfulHubGui")
    if old then old:Destroy() end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "WonderfulHubGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = uiParent

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(280, 460)
main.Position = UDim2.new(0, 20, 0.2, 0)
main.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(60, 60, 60)
stroke.Thickness = 1
stroke.Parent = main

local header = Instance.new("TextLabel")
header.Size = UDim2.new(1, 0, 0, 34)
header.BackgroundColor3 = Color3.fromRGB(32, 32, 36)
header.BorderSizePixel = 0
header.Text = "  WonderfulHub — dead rails"
header.TextColor3 = Color3.fromRGB(230, 230, 230)
header.TextXAlignment = Enum.TextXAlignment.Left
header.Font = Enum.Font.GothamBold
header.TextSize = 14
header.Parent = main

local body = Instance.new("ScrollingFrame")
body.Size = UDim2.new(1, -12, 1, -44)
body.Position = UDim2.new(0, 6, 0, 40)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 4
body.CanvasSize = UDim2.new(0, 0, 0, 0)
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.Parent = main

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 6)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = body

local order = 0
local function addToggle(label, key, onChange)
    order += 1
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 30)
    btn.BackgroundColor3 = Color3.fromRGB(40, 40, 44)
    btn.BorderSizePixel = 0
    btn.Text = label .. ": OFF"
    btn.TextColor3 = Color3.fromRGB(230, 230, 230)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 13
    btn.LayoutOrder = order
    btn.Parent = body

    local state = cfg[key] and true or false
    local function refresh()
        btn.Text = label .. ": " .. (state and "ON" or "OFF")
        btn.BackgroundColor3 = state
            and Color3.fromRGB(36, 110, 52)
            or Color3.fromRGB(40, 40, 44)
    end
    refresh()

    btn.MouseButton1Click:Connect(function()
        state = not state
        cfg[key] = state
        refresh()
        if onChange then pcall(onChange, state) end
    end)
    return btn
end

local function addSlider(label, key, min, max, def, step)
    order += 1
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 48)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 33)
    frame.BorderSizePixel = 0
    frame.LayoutOrder = order
    frame.Parent = body

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -10, 0, 18)
    lbl.Position = UDim2.new(0, 8, 0, 4)
    lbl.BackgroundTransparency = 1
    lbl.Text = label .. ": " .. tostring(cfg[key] or def)
    lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.Parent = frame

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -20, 0, 14)
    bar.Position = UDim2.new(0, 10, 0, 26)
    bar.BackgroundColor3 = Color3.fromRGB(55, 55, 60)
    bar.BorderSizePixel = 0
    bar.Parent = frame

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((cfg[key] or def - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(80, 160, 240)
    fill.BorderSizePixel = 0
    fill.Parent = bar

    local dragging = false
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if not dragging then return end
        if i.UserInputType ~= Enum.UserInputType.MouseMovement
        and i.UserInputType ~= Enum.UserInputType.Touch then return end
        local rel = math.clamp((i.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local val = min + (max - min) * rel
        val = math.floor(val / step + 0.5) * step
        cfg[key] = val
        fill.Size = UDim2.new(rel, 0, 1, 0)
        lbl.Text = label .. ": " .. tostring(val)
    end)
end

local function addButton(label, onClick)
    order += 1
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 30)
    btn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    btn.BorderSizePixel = 0
    btn.Text = label
    btn.TextColor3 = Color3.fromRGB(230, 230, 230)
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 13
    btn.LayoutOrder = order
    btn.Parent = body
    btn.MouseButton1Click:Connect(function() pcall(onClick) end)
end

local function addLabel(text)
    order += 1
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 0, 20)
    l.BackgroundTransparency = 1
    l.Text = "— " .. text .. " —"
    l.TextColor3 = Color3.fromRGB(120, 120, 120)
    l.Font = Enum.Font.Gotham
    l.TextSize = 11
    l.LayoutOrder = order
    l.Parent = body
end

-- groups
addLabel("esp")
addToggle("ESP", "esp")
addToggle("Boxes", "espBoxes")
addToggle("Names", "espNames")
addToggle("Health bar", "espHealth")
addToggle("Distance", "espDistance")
addSlider("ESP radius (0=all)", "espFOV", 0, 300, 0, 10)
addToggle("Items ESP", "itemsESP")

addLabel("combat")
addToggle("Kill Aura", "killAura")
addSlider("Aura range", "auraRange", 6, 40, 18, 1)

addLabel("loot")
addToggle("Auto collect", "autoCollect")
addSlider("Collect range", "collectRange", 10, 200, 60, 5)
addToggle("Auto fuel", "autoFuel")

addLabel("player")
addToggle("Noclip", "noclip")
addToggle("Auto heal", "autoHeal")
addToggle("Full bright", "fullBright", function(v)
    cfg.fullBright = v
    applyBright()
end)
addSlider("Walk speed", "walkSpeed", 8, 200, 16, 1)
addSlider("Jump power", "jumpPower", 30, 300, 50, 1)
addButton("Apply speed/jump", function()
    applyMovement()
    notify("movement applied")
end)

addLabel("util")
addButton("Reposition UI to corner", function()
    main.Position = UDim2.new(0, 20, 0, 60)
end)
addButton("Unload script", function()
    for _, e in pairs(espStore)  do destroyEspEntry(e) end
    for _, e in pairs(itemStore) do
        pcall(function() e.box:Remove() end)
        pcall(function() e.name:Remove() end)
    end
    gui:Destroy()
end)

notify("WonderfulHub loaded — Dead Rails")
