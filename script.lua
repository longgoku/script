-- Longdzvcl Hub

------------------------------------------------------------------
-- SERVICES
------------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Lighting         = game:GetService("Lighting")
local GuiService       = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer

------------------------------------------------------------------
-- THEME
------------------------------------------------------------------
local THEME = {
    Accent   = Color3.fromRGB(0, 219, 146),
    Accent2  = Color3.fromRGB(0, 168, 232),   -- màu phụ cho gradient
    Bg       = Color3.fromRGB(17, 18, 24),
    BgLight  = Color3.fromRGB(24, 26, 33),
    Card     = Color3.fromRGB(28, 30, 39),
    Card2    = Color3.fromRGB(33, 36, 47),
    Stroke   = Color3.fromRGB(45, 49, 62),
    Text     = Color3.fromRGB(238, 240, 246),
    Dim      = Color3.fromRGB(133, 141, 158),
    Off      = Color3.fromRGB(54, 58, 72),
    Red      = Color3.fromRGB(230, 46, 46),
    Warn     = Color3.fromRGB(255, 190, 80),
    Mob      = Color3.fromRGB(255, 92, 92),   -- màu ESP quái
}

------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------
local ALL_MOBS = "Tất cả quái"

local CONFIG = {
    YoutubeUrl = nil, -- đã bỏ tính năng này
    MenuKey    = Enum.KeyCode.RightShift,
    EspPlayer  = THEME.Accent,
    EspMob     = THEME.Mob,

    -- ⚙ TÙY CHỈNH CÁCH ĐÁNH CỦA AUTOFARM
    -- Mặc định: tự trang bị Tool trong Backpack rồi bấm liên tục (kiểu game dùng kiếm).
    -- Nếu game bạn gây damage bằng RemoteEvent, bỏ comment và sửa đoạn dưới:
    --
    -- OnAttack = function(mobModel, mobHumanoid)
    --     game.ReplicatedStorage.Remotes.Hit:FireServer(mobModel)
    -- end,
    OnAttack = nil,

    AttackRate = 0.12,  -- giây giữa 2 lần đánh
}

local State = {
    FixLag = false, EspPlayer = false, EspMob = false, Fullbright = false,
    Speed = false, Fly = false, JumpBoost = false, AutoFarm = false, Noclip = false,
    SpeedValue = 45,      -- WalkSpeed khi bật Speed
    JumpValue  = 90,      -- JumpPower khi bật JumpBoost
    FlySpeed   = 65,      -- tốc độ bay
    FarmTarget = ALL_MOBS,-- loại quái đang chọn
    FarmHeight = 3,       -- bay cao hơn đầu quái bao nhiêu studs (thấp = dễ chạm đòn hơn)
    MenuOpen   = true,
}

-- Bảng công tắc, khai báo sớm để các chức năng gọi lẫn nhau được
local switches = {}

-- Thông số gốc của nhân vật (đọc lại mỗi lần hồi sinh)
local baseStats = { WalkSpeed = 16, JumpPower = 50, JumpHeight = 7.2 }

------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------
local function new(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        if k ~= "Parent" then inst[k] = v end
    end
    for _, c in ipairs(children or {}) do c.Parent = inst end
    if props and props.Parent then inst.Parent = props.Parent end
    return inst
end

local function corner(parent, r)
    return new("UICorner", { CornerRadius = UDim.new(0, r), Parent = parent })
end

local function stroke(parent, color, thickness)
    return new("UIStroke", {
        Color = color or THEME.Stroke, Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent,
    })
end

local function gradient(parent, c1, c2, rot, transparency)
    return new("UIGradient", {
        Parent = parent, Rotation = rot or 90,
        Color = ColorSequence.new(c1, c2),
        Transparency = transparency or NumberSequence.new(0),
    })
end

local function tween(inst, time, props, style)
    local t = TweenService:Create(inst,
        TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    t:Play()
    return t
end

local function getHum()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid") or nil
end

local function getRoot()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart") or nil
end

local function isTouch()
    return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Kéo (drag) hoạt động cho cả chuột và cảm ứng
local function makeDraggable(handle, target, onTap)
    local dragging, startPos, startAbs, moved = false, nil, nil, 0
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, 0
            startAbs, startPos = input.Position, target.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local d = input.Position - startAbs
            moved = math.max(moved, math.abs(d.X) + math.abs(d.Y))
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            if onTap and moved < 8 then onTap() end -- bấm chứ không phải kéo
        end
    end)
end

------------------------------------------------------------------
-- MOB UTIL : tìm quái (Model có Humanoid, không phải người chơi)
------------------------------------------------------------------
local MobUtil = {}
do
    local cache, cacheTime = nil, -1

    function MobUtil.refresh() cacheTime = -1 end

    -- Có cache 1 giây để không quét lại cả map mỗi frame
    function MobUtil.list()
        if cache and (os.clock() - cacheTime) < 1 then return cache end
        local out = {}
        for _, inst in ipairs(workspace:GetDescendants()) do
            if inst:IsA("Humanoid") then
                local model = inst.Parent
                if model and model:IsA("Model")
                    and not Players:GetPlayerFromCharacter(model) then
                    out[#out + 1] = { model = model, hum = inst }
                end
            end
        end
        cache, cacheTime = out, os.clock()
        return out
    end

    function MobUtil.anchorOf(model)
        return model:FindFirstChild("Head")
            or model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("Torso")
            or model.PrimaryPart
    end

    -- Danh sách tên quái (không trùng) cho dropdown
    function MobUtil.names()
        local seen, list = {}, {}
        for _, m in ipairs(MobUtil.list()) do
            if m.hum.Parent and m.hum.Health > 0 and not seen[m.model.Name] then
                seen[m.model.Name] = true
                list[#list + 1] = m.model.Name
            end
        end
        table.sort(list)
        table.insert(list, 1, ALL_MOBS)
        return list
    end

    function MobUtil.nearest(nameFilter)
        local root = getRoot()
        if not root then return nil end
        local best, bestDist = nil, math.huge
        for _, m in ipairs(MobUtil.list()) do
            if m.hum.Parent and m.hum.Health > 0
                and (nameFilter == ALL_MOBS or m.model.Name == nameFilter) then
                local anchor = MobUtil.anchorOf(m.model)
                if anchor then
                    local d = (anchor.Position - root.Position).Magnitude
                    if d < bestDist then best, bestDist = m, d end
                end
            end
        end
        return best
    end
end

------------------------------------------------------------------
-- GUI GỐC
------------------------------------------------------------------
local oldGui = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("DonchoigameHub")
if oldGui then oldGui:Destroy() end

local gui = new("ScreenGui", {
    Name = "DonchoigameHub", ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
    Parent = LocalPlayer.PlayerGui,
})

-- ░░ WRAPPER (kéo + co giãn) ░░
local root = new("Frame", {
    Name = "Root", Parent = gui,
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(304, 430),
    BackgroundTransparency = 1, Visible = State.MenuOpen,
})
local uiScale = new("UIScale", { Parent = root })

local function fitScreen()
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
        or Vector2.new(1280, 720)
    return math.clamp(math.min(vp.Y / 540, vp.X / 480), 0.66, 1)
end
local baseScale = fitScreen()
uiScale.Scale = baseScale

-- ░░ BÓNG ĐỔ MỀM phía sau khung ░░
local shadow = new("ImageLabel", {
    Parent = root, ZIndex = 0, Image = "rbxassetid://5028857084",
    ImageColor3 = Color3.new(0, 0, 0), ImageTransparency = 0.45,
    ScaleType = Enum.ScaleType.Slice,
    SliceCenter = Rect.new(24, 24, 276, 276),
    Position = UDim2.new(0.5, 0, 0.5, 10), AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.new(1, 34, 1, 40), BackgroundTransparency = 1,
})

-- ░░ HÀO QUANG (glow) phía sau menu ░░
local glow = new("Frame", {
    Parent = root, ZIndex = 0,
    Position = UDim2.new(0, -8, 0, -8), Size = UDim2.new(1, 16, 1, 16),
    BackgroundColor3 = THEME.Accent, BackgroundTransparency = 0.9, BorderSizePixel = 0,
})
corner(glow, 22)
gradient(glow, THEME.Accent, THEME.Accent2, 140)

-- ░░ KHUNG CHÍNH ░░
local main = new("Frame", {
    Name = "Main", Parent = root, ZIndex = 1,
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = THEME.Bg, BorderSizePixel = 0, ClipsDescendants = true,
})
corner(main, 16)
stroke(main, THEME.Stroke, 1)
gradient(main, THEME.BgLight, THEME.Bg, 90)

------------------------------------------------------------------
-- HEADER
------------------------------------------------------------------
local header = new("Frame", {
    Parent = main, Size = UDim2.new(1, 0, 0, 60),
    BackgroundColor3 = THEME.Card, BackgroundTransparency = 0.45,
    BorderSizePixel = 0, Active = true, -- Active: cần cho việc kéo menu
})
gradient(header, THEME.Accent, THEME.Card, 0,
    NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.82),
        NumberSequenceKeypoint.new(0.55, 1),
        NumberSequenceKeypoint.new(1, 1),
    }))

-- huy hiệu logo tròn góc trái tiêu đề
local logo = new("Frame", {
    Parent = header, Position = UDim2.new(0, 12, 0, 11), Size = UDim2.fromOffset(38, 38),
    BackgroundColor3 = THEME.Accent, BorderSizePixel = 0,
})
corner(logo, 12)
gradient(logo, THEME.Accent, THEME.Accent2, 135)
stroke(logo, Color3.new(1, 1, 1), 1).Transparency = 0.75
new("TextLabel", {
    Parent = logo, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
    Font = Enum.Font.GothamBlack, Text = "L", TextSize = 19, TextColor3 = Color3.new(1, 1, 1),
})

new("TextLabel", {
    Parent = header, BackgroundTransparency = 1,
    Position = UDim2.new(0, 58, 0, 13), Size = UDim2.new(1, -142, 0, 20),
    Font = Enum.Font.GothamBold, Text = "Longdzvcl", TextSize = 17,
    TextColor3 = THEME.Text, TextXAlignment = Enum.TextXAlignment.Left,
})
new("TextLabel", {
    Parent = header, BackgroundTransparency = 1,
    Position = UDim2.new(0, 58, 0, 33), Size = UDim2.new(1, -142, 0, 14),
    Font = Enum.Font.Gotham, Text = "by Longdzvcl", TextSize = 11,
    TextColor3 = THEME.Dim, TextXAlignment = Enum.TextXAlignment.Left,
})

-- viên FPS
local fpsPill = new("Frame", {
    Parent = header, Position = UDim2.new(1, -108, 0, 17), Size = UDim2.fromOffset(56, 20),
    BackgroundColor3 = THEME.Bg, BackgroundTransparency = 0.25, BorderSizePixel = 0,
})
corner(fpsPill, 10)
stroke(fpsPill, THEME.Stroke, 1)
local fpsLabel = new("TextLabel", {
    Parent = fpsPill, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
    Font = Enum.Font.GothamBold, Text = "-- FPS", TextSize = 10, TextColor3 = THEME.Dim,
})

local closeBtn = new("TextButton", {
    Parent = header, AutoButtonColor = false,
    Position = UDim2.new(1, -44, 0, 16), Size = UDim2.fromOffset(28, 28),
    BackgroundColor3 = THEME.Card2, BorderSizePixel = 0,
    Font = Enum.Font.GothamBold, Text = "✕", TextSize = 13, TextColor3 = THEME.Dim,
})
corner(closeBtn, 9)
stroke(closeBtn, THEME.Stroke, 1)
closeBtn.MouseEnter:Connect(function()
    tween(closeBtn, 0.15, { BackgroundColor3 = THEME.Red, TextColor3 = Color3.new(1, 1, 1) })
end)
closeBtn.MouseLeave:Connect(function()
    tween(closeBtn, 0.15, { BackgroundColor3 = THEME.Card2, TextColor3 = THEME.Dim })
end)

new("Frame", {
    Parent = main, Position = UDim2.new(0, 0, 0, 60), Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = THEME.Stroke, BorderSizePixel = 0,
})

------------------------------------------------------------------
-- BODY
------------------------------------------------------------------
local body = new("ScrollingFrame", {
    Parent = main,
    Position = UDim2.new(0, 0, 0, 61), Size = UDim2.new(1, 0, 1, -71),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    ScrollBarThickness = 3, ScrollBarImageColor3 = THEME.Accent,
    ScrollBarImageTransparency = 0.5, ClipsDescendants = true,
})
new("UIListLayout", {
    Parent = body, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
})
new("UIPadding", {
    Parent = body,
    PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
    PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10),
})

------------------------------------------------------------------
-- NÚT TRÒN MỞ MENU (PC + Mobile)
------------------------------------------------------------------
local fab = new("TextButton", {
    Name = "Fab", Parent = gui, AutoButtonColor = false,
    Position = UDim2.new(0, 16, 0.5, -27), Size = UDim2.fromOffset(54, 54),
    BackgroundColor3 = THEME.Accent, BorderSizePixel = 0,
    Font = Enum.Font.GothamBlack, Text = "DH", TextSize = 18,
    TextColor3 = Color3.fromRGB(8, 22, 18),
})
corner(fab, 27)
gradient(fab, THEME.Accent, THEME.Accent2, 135)
stroke(fab, Color3.new(1, 1, 1), 1.5).Transparency = 0.72

------------------------------------------------------------------
-- TOAST
------------------------------------------------------------------
local activeToast
local function toast(text, color)
    if activeToast then activeToast:Destroy() end
    local t = new("Frame", {
        Parent = gui, AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(0, 34),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = THEME.Card, BackgroundTransparency = 0.04, BorderSizePixel = 0,
    })
    activeToast = t
    corner(t, 10)
    stroke(t, color or THEME.Accent, 1.5)
    new("UIPadding", {
        Parent = t, PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16),
    })
    new("TextLabel", {
        Parent = t, BackgroundTransparency = 1, Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Font = Enum.Font.GothamMedium, Text = text, TextSize = 13, TextColor3 = THEME.Text,
    })
    task.delay(1.9, function()
        if t.Parent then
            tween(t, 0.25, { BackgroundTransparency = 1 })
            task.wait(0.25)
            t:Destroy()
            if activeToast == t then activeToast = nil end
        end
    end)
end

------------------------------------------------------------------
-- COMPONENT: công tắc bật/tắt
------------------------------------------------------------------
local function makeSwitch(parent, onChange)
    local btn = new("TextButton", {
        Parent = parent, AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(44, 23),
        BackgroundColor3 = THEME.Off, BorderSizePixel = 0, Text = "",
    })
    new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = btn })
    local glowStroke = new("UIStroke", {
        Parent = btn, Color = THEME.Accent, Thickness = 1.5, Transparency = 1,
    })
    local knob = new("Frame", {
        Parent = btn, Size = UDim2.fromOffset(17, 17), Position = UDim2.new(0, 3, 0.5, -8.5),
        BackgroundColor3 = Color3.fromRGB(246, 248, 252), BorderSizePixel = 0,
    })
    new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = knob })

    local on = false
    local function render(animate)
        local d = animate and 0.16 or 0
        tween(btn, d, { BackgroundColor3 = on and THEME.Accent or THEME.Off })
        tween(glowStroke, d, { Transparency = on and 0.55 or 1 })
        tween(knob, d, {
            Position = on and UDim2.new(1, -20, 0.5, -8.5) or UDim2.new(0, 3, 0.5, -8.5),
        }, Enum.EasingStyle.Back)
    end

    local api = {}
    function api.Set(value, silent)
        if on == value then return end
        on = value
        render(true)
        if not silent and onChange then onChange(on) end
    end
    function api.Get() return on end

    btn.MouseButton1Click:Connect(function() api.Set(not on) end)
    render(false)
    return api
end

------------------------------------------------------------------
-- COMPONENT: slider (chuột + cảm ứng)
------------------------------------------------------------------
local function makeSlider(parent, opts)
    local holder = new("Frame", {
        Parent = parent, LayoutOrder = opts.order or 2, Visible = opts.visible ~= false,
        Size = UDim2.new(1, 0, 0, opts.label and 44 or 32), BackgroundTransparency = 1,
    })
    new("UIPadding", {
        Parent = holder, PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 10),
    })

    local yOff = 0
    if opts.label then
        new("TextLabel", {
            Parent = holder, BackgroundTransparency = 1,
            Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, 0, 0, 13),
            Font = Enum.Font.Gotham, Text = opts.label, TextSize = 10.5,
            TextColor3 = THEME.Dim, TextXAlignment = Enum.TextXAlignment.Left,
        })
        yOff = 13
    end

    local track = new("Frame", {
        Parent = holder, Position = UDim2.new(0, 0, 0, yOff + 8), Size = UDim2.new(1, -46, 0, 6),
        BackgroundColor3 = THEME.Off, BorderSizePixel = 0,
    })
    new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = track })

    local fill = new("Frame", {
        Parent = track, Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = THEME.Accent, BorderSizePixel = 0,
    })
    new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = fill })
    gradient(fill, THEME.Accent2, THEME.Accent, 0)

    local knob = new("Frame", {
        Parent = track, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(15, 15),
        BackgroundColor3 = Color3.fromRGB(246, 248, 252), BorderSizePixel = 0,
    })
    new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = knob })

    local valueLabel = new("TextLabel", {
        Parent = holder, BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, yOff + 2), Size = UDim2.fromOffset(42, 16),
        Font = Enum.Font.GothamBold, Text = tostring(opts.default), TextSize = 12,
        TextColor3 = THEME.Accent, TextXAlignment = Enum.TextXAlignment.Right,
    })

    -- vùng bấm rộng hơn track cho dễ dùng trên điện thoại
    local hit = new("TextButton", {
        Parent = holder, BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
        Position = UDim2.new(0, -8, 0, yOff), Size = UDim2.new(1, -30, 0, 26),
    })

    local value = opts.default
    local function render()
        local a = (value - opts.min) / (opts.max - opts.min)
        fill.Size = UDim2.fromScale(a, 1)
        knob.Position = UDim2.new(a, 0, 0.5, 0)
        valueLabel.Text = tostring(value)
    end

    local function setFromX(x)
        local a = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
        local v = math.floor(opts.min + (opts.max - opts.min) * a + 0.5)
        if v ~= value then
            value = v
            render()
            if opts.onChanged then opts.onChanged(value) end
        end
    end

    local dragging = false
    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            tween(knob, 0.1, { Size = UDim2.fromOffset(19, 19) })
            setFromX(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            setFromX(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
            tween(knob, 0.12, { Size = UDim2.fromOffset(15, 15) })
        end
    end)

    render()
    return holder
end

------------------------------------------------------------------
-- COMPONENT: dropdown chọn loại quái
------------------------------------------------------------------
local function makeDropdown(parent, opts)
    local holder = new("Frame", {
        Parent = parent, LayoutOrder = opts.order or 3,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
    })
    new("UIListLayout", { Parent = holder, Padding = UDim.new(0, 6) })
    new("UIPadding", {
        Parent = holder, PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 10),
    })

    local bar = new("Frame", {
        Parent = holder, LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
    })

    local head = new("TextButton", {
        Parent = bar, AutoButtonColor = false,
        Size = UDim2.new(1, -36, 1, 0), BackgroundColor3 = THEME.Bg,
        BackgroundTransparency = 0.15, BorderSizePixel = 0,
        Font = Enum.Font.GothamMedium, Text = "", TextSize = 12,
    })
    corner(head, 8)
    stroke(head, THEME.Stroke, 1)

    local valueLabel = new("TextLabel", {
        Parent = head, BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(1, -32, 1, 0),
        Font = Enum.Font.GothamMedium, Text = opts.default, TextSize = 12,
        TextColor3 = THEME.Text, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    local arrow = new("TextLabel", {
        Parent = head, BackgroundTransparency = 1,
        Position = UDim2.new(1, -22, 0, 0), Size = UDim2.fromOffset(18, 30),
        Font = Enum.Font.GothamBold, Text = "▾", TextSize = 12, TextColor3 = THEME.Accent,
    })

    local refreshBtn = new("TextButton", {
        Parent = bar, AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(30, 30),
        BackgroundColor3 = THEME.Bg, BackgroundTransparency = 0.15, BorderSizePixel = 0,
        Font = Enum.Font.GothamBold, Text = "⟳", TextSize = 15, TextColor3 = THEME.Accent,
    })
    corner(refreshBtn, 8)
    stroke(refreshBtn, THEME.Stroke, 1)

    local list = new("ScrollingFrame", {
        Parent = holder, LayoutOrder = 2, Visible = false,
        Size = UDim2.new(1, 0, 0, 108), BackgroundColor3 = THEME.Bg,
        BackgroundTransparency = 0.2, BorderSizePixel = 0,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3, ScrollBarImageColor3 = THEME.Accent,
        ScrollBarImageTransparency = 0.5,
    })
    corner(list, 8)
    stroke(list, THEME.Stroke, 1)
    new("UIListLayout", { Parent = list, Padding = UDim.new(0, 3) })
    new("UIPadding", {
        Parent = list, PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5),
        PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5),
    })

    local value = opts.default
    local open = false

    local function rebuild()
        for _, c in ipairs(list:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        local items = opts.getItems()
        for i, name in ipairs(items) do
            local item = new("TextButton", {
                Parent = list, LayoutOrder = i, AutoButtonColor = false,
                Size = UDim2.new(1, 0, 0, 26),
                BackgroundColor3 = name == value and THEME.Accent or THEME.Card2,
                BackgroundTransparency = name == value and 0.7 or 0.35,
                BorderSizePixel = 0, Font = Enum.Font.Gotham, Text = "  " .. name,
                TextSize = 11.5, TextColor3 = name == value and THEME.Accent or THEME.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
            })
            corner(item, 6)
            item.MouseButton1Click:Connect(function()
                value = name
                valueLabel.Text = name
                rebuild()
                if opts.onSelect then opts.onSelect(name) end
            end)
        end
        if #items <= 1 then
            new("TextButton", {
                Parent = list, LayoutOrder = 999, AutoButtonColor = false,
                Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1,
                Font = Enum.Font.Gotham, Text = "  (chưa thấy quái — bấm ⟳)",
                TextSize = 11, TextColor3 = THEME.Dim,
                TextXAlignment = Enum.TextXAlignment.Left,
            })
        end
    end

    local function setOpen(v)
        open = v
        list.Visible = v
        arrow.Text = v and "▴" or "▾"
        if v then rebuild() end
    end

    head.MouseButton1Click:Connect(function() setOpen(not open) end)
    refreshBtn.MouseButton1Click:Connect(function()
        MobUtil.refresh()
        if open then rebuild() else setOpen(true) end
        tween(refreshBtn, 0.2, { BackgroundTransparency = 0.5 })
        task.delay(0.2, function() tween(refreshBtn, 0.2, { BackgroundTransparency = 0.15 }) end)
    end)

    return { Get = function() return value end }
end

------------------------------------------------------------------
-- COMPONENT: nhóm mục + dòng chức năng
------------------------------------------------------------------
local rowOrder = 0

local function addSection(text)
    rowOrder += 1
    local f = new("Frame", {
        Parent = body, LayoutOrder = rowOrder,
        Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
    })
    new("TextLabel", {
        Parent = f, BackgroundTransparency = 1,
        Position = UDim2.new(0, 4, 0, 3), Size = UDim2.new(1, -8, 0, 12),
        Font = Enum.Font.GothamBold, Text = text, TextSize = 10,
        TextColor3 = THEME.Dim, TextXAlignment = Enum.TextXAlignment.Left,
    })
    return f
end

local function addFeature(opts)
    rowOrder += 1
    local card = new("Frame", {
        Parent = body, LayoutOrder = rowOrder, ClipsDescendants = true,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = THEME.Card, BorderSizePixel = 0,
    })
    corner(card, 11)
    gradient(card, THEME.Card2, THEME.Card, 90)
    local cardStroke = stroke(card, THEME.Stroke, 1)
    new("UIListLayout", { Parent = card, SortOrder = Enum.SortOrder.LayoutOrder })

    local head = new("Frame", {
        Parent = card, LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 44),
        BackgroundTransparency = 1,
    })

    -- vạch accent bên trái khi bật (nằm trong head để UIListLayout không đẩy thành 1 dòng)
    local activeBar = new("Frame", {
        Parent = head, Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = THEME.Accent,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2,
    })

    local iconBox = new("Frame", {
        Parent = head, Position = UDim2.new(0, 10, 0.5, -13), Size = UDim2.fromOffset(26, 26),
        BackgroundColor3 = opts.color or THEME.Accent, BackgroundTransparency = 0.87,
        BorderSizePixel = 0,
    })
    corner(iconBox, 8)
    new("TextLabel", {
        Parent = iconBox, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
        Font = Enum.Font.GothamBold, Text = opts.icon, TextSize = 13, TextColor3 = THEME.Text,
    })

    new("TextLabel", {
        Parent = head, BackgroundTransparency = 1,
        Position = UDim2.new(0, 46, 0, 7), Size = UDim2.new(1, -116, 0, 16),
        Font = Enum.Font.GothamBold, Text = opts.title, TextSize = 13,
        TextColor3 = THEME.Text, TextXAlignment = Enum.TextXAlignment.Left,
    })
    new("TextLabel", {
        Parent = head, BackgroundTransparency = 1,
        Position = UDim2.new(0, 46, 0, 23), Size = UDim2.new(1, -116, 0, 13),
        Font = Enum.Font.Gotham, Text = opts.desc or "", TextSize = 10,
        TextColor3 = THEME.Dim, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    local extras = {}   -- phần hiện ra khi bật (slider...)
    local function setActive(on)
        tween(activeBar, 0.18, { BackgroundTransparency = on and 0 or 1 })
        tween(cardStroke, 0.18, { Color = on and (opts.color or THEME.Accent) or THEME.Stroke })
        tween(iconBox, 0.18, { BackgroundTransparency = on and 0.72 or 0.87 })
        for _, e in ipairs(extras) do e.Visible = on end
    end

    local switch = makeSwitch(head, function(on)
        setActive(on)
        opts.onToggle(on)
    end)

    local api = { Card = card, Switch = switch }
    function api.Set(v, silent)
        switch.Set(v, silent)
        if silent then setActive(v) end
    end
    function api.Get() return switch.Get() end

    -- slider chỉ hiện khi bật
    if opts.slider then
        opts.slider.order = 2
        opts.slider.visible = false
        extras[#extras + 1] = makeSlider(card, opts.slider)
    end
    -- phần luôn hiện (dropdown, slider của autofarm...)
    if opts.build then opts.build(card) end

    return api
end

------------------------------------------------------------------
-- CHỨC NĂNG: FIX LAG
------------------------------------------------------------------
local FixLag = {}
do
    local saved, conn, active = {}, nil, false

    local function set(inst, prop, value)
        local ok, old = pcall(function() return inst[prop] end)
        if ok then
            saved[#saved + 1] = { inst, prop, old }
            pcall(function() inst[prop] = value end)
        end
    end

    local function process(inst)
        if inst:IsA("Terrain") then
            set(inst, "Decoration", false)
            set(inst, "WaterWaveSize", 0)
            set(inst, "WaterWaveSpeed", 0)
            set(inst, "WaterReflectance", 0)
        elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Smoke")
            or inst:IsA("Fire") or inst:IsA("Sparkles") then
            if inst.Enabled then set(inst, "Enabled", false) end
        elseif inst:IsA("Decal") or inst:IsA("Texture") then
            if inst.Transparency < 1 then set(inst, "Transparency", 1) end
        elseif inst:IsA("BasePart") then
            if inst.Material ~= Enum.Material.SmoothPlastic then
                set(inst, "Material", Enum.Material.SmoothPlastic)
            end
            if inst.Reflectance > 0 then set(inst, "Reflectance", 0) end
            if inst.CastShadow then set(inst, "CastShadow", false) end
        end
    end

    -- bỏ qua người chơi & quái để không làm biến dạng hình ảnh nhân vật
    local function isCreature(model)
        return model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") ~= nil
    end

    function FixLag.SetEnabled(on)
        if on == active then return end
        active = on

        if on then
            pcall(function()
                settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
            end)

            set(Lighting, "GlobalShadows", false)
            set(Lighting, "EnvironmentDiffuseScale", 0)
            set(Lighting, "EnvironmentSpecularScale", 0)
            for _, fx in ipairs(Lighting:GetChildren()) do
                if fx:IsA("PostEffect") and fx.Enabled then set(fx, "Enabled", false) end
            end

            local count = 0
            for _, child in ipairs(workspace:GetChildren()) do
                if not isCreature(child) then
                    process(child)
                    for _, d in ipairs(child:GetDescendants()) do
                        process(d)
                        count += 1
                        if count % 400 == 0 then task.wait() end -- tránh treo game
                    end
                end
            end

            conn = workspace.DescendantAdded:Connect(function(inst)
                if not active then return end
                task.defer(function()
                    local model = inst:FindFirstAncestorOfClass("Model")
                    if model and isCreature(model) then return end
                    process(inst)
                end)
            end)
        else
            if conn then conn:Disconnect(); conn = nil end
            for i = #saved, 1, -1 do
                local rec = saved[i]
                pcall(function() rec[1][rec[2]] = rec[3] end)
            end
            table.clear(saved)
            pcall(function()
                settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
            end)
        end
    end
end

------------------------------------------------------------------
-- CHỨC NĂNG: ESP (người chơi + quái)
------------------------------------------------------------------
local ESP = {}
do
    local folder
    local entries = {}      -- [model] = { kind, hum, anchor, info }
    local playerConns = {}  -- [player] = connection
    local conns = { player = {}, mob = {} }  -- tách theo loại để tắt riêng được
    local loop, acc = nil, 0

    local function dropConns(kind)
        for _, c in ipairs(conns[kind]) do c:Disconnect() end
        table.clear(conns[kind])
    end

    local function ensureFolder()
        if not folder or not folder.Parent then
            folder = new("Folder", {
                Name = "DGH_ESP", Parent = workspace.CurrentCamera or workspace,
            })
        end
        return folder
    end

    local function destroyEntry(model)
        local e = entries[model]
        if not e then return end
        if e.highlight then e.highlight:Destroy() end
        if e.billboard then e.billboard:Destroy() end
        entries[model] = nil
    end

    local function addModel(model, kind, label)
        if entries[model] or not model.Parent then return end
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        local anchor = MobUtil.anchorOf(model)
        if not anchor then return end

        local color = kind == "player" and CONFIG.EspPlayer or CONFIG.EspMob
        local e = { kind = kind, hum = hum, anchor = anchor }

        e.highlight = new("Highlight", {
            Parent = ensureFolder(), Adornee = model,
            DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
            FillColor = color, FillTransparency = 0.72,
            OutlineColor = color, OutlineTransparency = 0,
        })
        e.billboard = new("BillboardGui", {
            Parent = ensureFolder(), Adornee = anchor,
            Size = UDim2.fromOffset(190, 34), StudsOffset = Vector3.new(0, 2.4, 0),
            AlwaysOnTop = true, MaxDistance = 3000, LightInfluence = 0,
        })
        new("TextLabel", {
            Parent = e.billboard, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 17),
            Font = Enum.Font.GothamBold, Text = label, TextSize = 13, TextColor3 = color,
            TextStrokeTransparency = 0.35, TextStrokeColor3 = Color3.new(0, 0, 0),
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        e.info = new("TextLabel", {
            Parent = e.billboard, BackgroundTransparency = 1,
            Position = UDim2.new(0, 0, 0, 17), Size = UDim2.new(1, 0, 0, 14),
            Font = Enum.Font.Gotham, Text = "", TextSize = 11,
            TextColor3 = THEME.Dim, TextStrokeTransparency = 0.6,
            TextStrokeColor3 = Color3.new(0, 0, 0),
        })

        entries[model] = e
    end

    local function refreshPlayer(plr)
        if not State.EspPlayer then return end
        local char = plr.Character
        if char then addModel(char, "player", plr.Name) end
    end

    local function refreshMobs()
        if not State.EspMob then return end
        for _, m in ipairs(MobUtil.list()) do
            addModel(m.model, "mob", m.model.Name)
        end
    end

    local function startLoop()
        if loop then return end
        loop = RunService.Heartbeat:Connect(function(dt)
            acc += dt
            -- xoá entry của model đã chết / bị xoá
            for model, e in pairs(entries) do
                if not model.Parent or not e.hum.Parent or e.hum.Health <= 0 then
                    destroyEntry(model)
                elseif (e.kind == "player" and not State.EspPlayer)
                    or (e.kind == "mob" and not State.EspMob) then
                    destroyEntry(model)
                else
                    e.info.Text = string.format("%d / %d HP", math.max(0, math.floor(e.hum.Health)), math.floor(e.hum.MaxHealth))
                end
            end
            -- quét thêm entry mới, dãn cách 0.5s để đỡ tốn hiệu năng
            if acc >= 0.5 then
                acc = 0
                if State.EspPlayer then
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr ~= LocalPlayer then refreshPlayer(plr) end
                    end
                end
                if State.EspMob then refreshMobs() end
            end
        end)
    end

    function ESP.SetPlayer(on)
        State.EspPlayer = on
        startLoop()
        if not on then
            for model, e in pairs(entries) do
                if e.kind == "player" then destroyEntry(model) end
            end
        end
    end

    function ESP.SetMob(on)
        State.EspMob = on
        startLoop()
        if not on then
            for model, e in pairs(entries) do
                if e.kind == "mob" then destroyEntry(model) end
            end
        end
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            conns.player[#conns.player + 1] = plr.CharacterAdded:Connect(function()
                task.wait(0.3); refreshPlayer(plr)
            end)
        end
    end
    Players.PlayerAdded:Connect(function(plr)
        conns.player[#conns.player + 1] = plr.CharacterAdded:Connect(function()
            task.wait(0.3); refreshPlayer(plr)
        end)
    end)
end

------------------------------------------------------------------
-- CHỨC NĂNG: FULLBRIGHT
------------------------------------------------------------------
local Fullbright = {}
do
    local saved, active = {}, false
    local function set(prop, value)
        saved[prop] = Lighting[prop]
        Lighting[prop] = value
    end
    function Fullbright.SetEnabled(on)
        if on == active then return end
        active = on
        if on then
            set("Brightness", 2); set("ClockTime", 14)
            set("FogEnd", 100000); set("GlobalShadows", false)
            set("OutdoorAmbient", Color3.fromRGB(200, 200, 200))
        else
            for prop, v in pairs(saved) do Lighting[prop] = v end
            table.clear(saved)
        end
    end
end

------------------------------------------------------------------
-- CHỨC NĂNG: DI CHUYỂN (Speed / Jump / Fly)
------------------------------------------------------------------
local Movement = {}
do
    local flyConn, flyBV, upBtn, downBtn, upHeld, downHeld = nil, nil, nil, nil, false, false
    local enforceConn

    -- Nút bay lên / xuống nổi trên màn hình — bắt buộc phải có vì mobile
    -- không có phím Space/Shift. Bấm giữ = giữ hướng, thả tay = dừng.
    local function ensureFlyButtons()
        if upBtn then return end
        upBtn = new("TextButton", {
            Name = "FlyUp", Parent = gui, Visible = false, ZIndex = 50,
            Size = UDim2.fromOffset(52, 52), Position = UDim2.new(1, -70, 1, -150),
            BackgroundColor3 = THEME.Accent, AutoButtonColor = true,
            Font = Enum.Font.GothamBlack, Text = "▲", TextSize = 20, TextColor3 = Color3.new(1, 1, 1),
        })
        corner(upBtn, 26)
        downBtn = new("TextButton", {
            Name = "FlyDown", Parent = gui, Visible = false, ZIndex = 50,
            Size = UDim2.fromOffset(52, 52), Position = UDim2.new(1, -70, 1, -86),
            BackgroundColor3 = THEME.Card2, AutoButtonColor = true,
            Font = Enum.Font.GothamBlack, Text = "▼", TextSize = 20, TextColor3 = Color3.new(1, 1, 1),
        })
        corner(downBtn, 26)

        local function bind(btn, setter)
            btn.InputBegan:Connect(function(inp)
                if inp.UserInputType == Enum.UserInputType.Touch
                    or inp.UserInputType == Enum.UserInputType.MouseButton1 then
                    setter(true)
                end
            end)
            btn.InputEnded:Connect(function(inp)
                if inp.UserInputType == Enum.UserInputType.Touch
                    or inp.UserInputType == Enum.UserInputType.MouseButton1 then
                    setter(false)
                end
            end)
        end
        bind(upBtn, function(v) upHeld = v end)
        bind(downBtn, function(v) downHeld = v end)
    end

    -- Ép WalkSpeed/JumpPower liên tục mỗi frame: nhiều game simulator tự set lại
    -- 2 stat này theo nội bộ của họ, nếu chỉ set 1 lần thì bị đè về giá trị gốc ngay lập tức.
    local function startEnforce()
        if enforceConn then return end
        enforceConn = RunService.Heartbeat:Connect(function()
            local hum = getHum()
            if not hum then return end
            if State.Speed and hum.WalkSpeed ~= State.SpeedValue then
                hum.WalkSpeed = State.SpeedValue
            end
            if State.JumpBoost and hum.JumpPower ~= State.JumpValue then
                hum.JumpPower = State.JumpValue
            end
        end)
    end
    startEnforce()

    function Movement.ApplySpeed(on)
        local hum = getHum()
        if hum then hum.WalkSpeed = on and State.SpeedValue or baseStats.WalkSpeed end
    end

    function Movement.ApplyJump(on)
        local hum = getHum()
        if hum then hum.JumpPower = on and State.JumpValue or baseStats.JumpPower end
    end

    function Movement.StopFly()
        if flyConn then flyConn:Disconnect(); flyConn = nil end
        if flyBV then flyBV:Destroy(); flyBV = nil end
        upHeld, downHeld = false, false
        if upBtn then upBtn.Visible = false end
        if downBtn then downBtn.Visible = false end
    end

    -- Fly kiểu "huỷ trọng lực": không PlatformStand nên Humanoid vẫn nhận input
    -- di chuyển ngang bình thường (bàn phím lẫn joystick chạm trên mobile đều
    -- chạy qua WalkSpeed như cũ) — script chỉ bù lực để không rơi + cho lên/xuống.
    function Movement.ApplyFly(on)
        local hum, root = getHum(), getRoot()
        if not hum or not root then return end
        Movement.StopFly()
        if not on then return end

        ensureFlyButtons()
        upBtn.Visible = true
        downBtn.Visible = true

        flyBV = new("BodyVelocity", {
            Parent = root, MaxForce = Vector3.new(1e5, 1e5, 1e5), Velocity = Vector3.new(),
        })

        flyConn = RunService.Heartbeat:Connect(function()
            if not State.Fly or not root.Parent or not flyBV then return end

            -- hum.MoveDirection là hướng đi mà Roblox đã tự tính sẵn từ input hiện có
            -- (joystick chạm trên mobile, WASD trên PC, hoặc tay cầm) — dùng thẳng
            -- cái này thay vì tự đọc phím giúp bay di chuyển được trên mọi thiết bị.
            local horiz = hum.MoveDirection
            local horizVel = horiz.Magnitude > 0 and (horiz.Unit * State.FlySpeed) or Vector3.new()

            local vy = 0
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) or upHeld then
                vy = State.FlySpeed
            elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or downHeld then
                vy = -State.FlySpeed
            end

            flyBV.Velocity = Vector3.new(horizVel.X, vy, horizVel.Z)
        end)
    end
end

------------------------------------------------------------------
-- CHỨC NĂNG: GOD MODE (bất tử — khoá máu + chặn chết do mọi sát thương)
------------------------------------------------------------------
local God = {}
do
    local HUGE_HP = 1e9 -- số lớn hữu hạn, KHÔNG dùng math.huge vì Roblox có thể
                         -- từ chối/gây lỗi khi gán giá trị vô cực cho property Health,
                         -- và lỗi đó không hiện log gì khiến God mode coi như không chạy.
    local hpConn, diedConn, stateConn, enforceConn, hookedHum

    local function unhook()
        if hpConn then hpConn:Disconnect(); hpConn = nil end
        if diedConn then diedConn:Disconnect(); diedConn = nil end
        if stateConn then stateConn:Disconnect(); stateConn = nil end
        if enforceConn then enforceConn:Disconnect(); enforceConn = nil end
        hookedHum = nil
    end

    -- Gắn vào Humanoid hiện tại: khoá máu ở mức tối đa, chặn trạng thái "Dead",
    -- và ép máu về full LIÊN TỤC MỖI FRAME (không chỉ chờ event HealthChanged) —
    -- vì có game gây sát thương liên tiếp nhanh hơn tốc độ event xử lý kịp.
    function God.Hook(hum)
        unhook()
        if not hum then return end
        hookedHum = hum

        local ok = pcall(function()
            hum.MaxHealth = HUGE_HP
            hum.Health = HUGE_HP
        end)
        if not ok then
            pcall(function() hum.MaxHealth = 1e6; hum.Health = 1e6 end)
        end
        hum.BreakJointsOnDeath = false
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)

        hpConn = hum.HealthChanged:Connect(function(hp)
            if State.God and hp < hum.MaxHealth then
                hum.Health = hum.MaxHealth
            end
        end)

        stateConn = hum.StateChanged:Connect(function(_, new)
            if State.God and new == Enum.HumanoidStateType.Dead then
                hum.Health = hum.MaxHealth
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
            end
        end)

        diedConn = hum.Died:Connect(function()
            if not State.God then return end
            if hum and hum.Parent then
                pcall(function() hum.Health = hum.MaxHealth end)
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
            end
        end)

        -- lưới an toàn: ép máu mỗi frame, phòng trường hợp thứ gây chết không đi
        -- qua HealthChanged (ví dụ set thẳng bằng script khác nhanh liên tiếp)
        enforceConn = RunService.Heartbeat:Connect(function()
            if State.God and hookedHum and hookedHum.Parent and hookedHum.Health < hookedHum.MaxHealth then
                hookedHum.Health = hookedHum.MaxHealth
            end
        end)
    end

    function God.SetEnabled(on)
        State.God = on
        if on then God.Hook(getHum()) else unhook() end
    end
end

------------------------------------------------------------------
-- CHỨC NĂNG: NOCLIP (đi xuyên tường)
------------------------------------------------------------------
local Noclip = {}
do
    local conn

    -- Tắt CanCollide toàn bộ part của nhân vật, và tự chạy lại mỗi frame
    -- vì có part mới sinh ra (do tool, animation...) hoặc bị game bật lại CanCollide.
    function Noclip.Apply()
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end
    end

    function Noclip.SetEnabled(on)
        State.Noclip = on
        if conn then conn:Disconnect(); conn = nil end
        if not on then return end
        Noclip.Apply()
        conn = RunService.Stepped:Connect(function()
            if State.Noclip then Noclip.Apply() end
        end)
    end
end

------------------------------------------------------------------
-- CHỨC NĂNG: AUTO FARM
------------------------------------------------------------------
local AutoFarm = {}
do
    local running = false

    local function attack(model, hum)
        if CONFIG.OnAttack then
            pcall(CONFIG.OnAttack, model, hum)
            return
        end
        local char = LocalPlayer.Character
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        local tool = char and char:FindFirstChildOfClass("Tool")
        if not tool and backpack then
            tool = backpack:FindFirstChildOfClass("Tool")
            if tool then tool.Parent = char end
        end
        if tool then pcall(function() tool:Activate() end) end
    end

    function AutoFarm.SetEnabled(on)
        State.AutoFarm = on
        if running or not on then running = on; return end
        running = true
        task.spawn(function()
            while running and State.AutoFarm do
                local target = MobUtil.nearest(State.FarmTarget)
                local root = getRoot()
                if target and root then
                    local anchor = MobUtil.anchorOf(target.model)
                    if anchor then
                        root.CFrame = CFrame.new(anchor.Position + Vector3.new(0, State.FarmHeight, 0))
                        attack(target.model, target.hum)
                    end
                end
                task.wait(CONFIG.AttackRate)
            end
        end)
    end
end

------------------------------------------------------------------
-- RÁP CÁC THẺ CHỨC NĂNG VÀO MENU
------------------------------------------------------------------
addSection("HIỆU NĂNG & TẦM NHÌN")

switches.FixLag = addFeature({
    icon = "⚡", title = "Fix Lag", desc = "Giảm hiệu ứng, tăng FPS",
    onToggle = function(on) FixLag.SetEnabled(on) end,
})

switches.EspPlayer = addFeature({
    icon = "👤", title = "ESP Người chơi", desc = "Nhìn xuyên tường người chơi khác",
    color = THEME.Accent2,
    onToggle = function(on) ESP.SetPlayer(on) end,
})

switches.EspMob = addFeature({
    icon = "👹", title = "ESP Quái", desc = "Nhìn xuyên tường quái vật",
    color = THEME.Mob,
    onToggle = function(on) ESP.SetMob(on) end,
})

switches.Fullbright = addFeature({
    icon = "☀", title = "Fullbright", desc = "Sáng bản đồ, xoá sương mù",
    color = THEME.Warn,
    onToggle = function(on) Fullbright.SetEnabled(on) end,
})

addSection("DI CHUYỂN")

switches.Speed = addFeature({
    icon = "🏃", title = "Speed", desc = "Tăng tốc độ chạy",
    onToggle = function(on) State.Speed = on; Movement.ApplySpeed(on) end,
    slider = {
        min = 16, max = 999, default = State.SpeedValue, label = "Tốc độ",
        onChanged = function(v) State.SpeedValue = v; if State.Speed then Movement.ApplySpeed(true) end end,
    },
})

switches.JumpBoost = addFeature({
    icon = "⬆", title = "Jump Boost", desc = "Nhảy cao hơn",
    onToggle = function(on) State.JumpBoost = on; Movement.ApplyJump(on) end,
    slider = {
        min = 50, max = 999, default = State.JumpValue, label = "Lực nhảy",
        onChanged = function(v) State.JumpValue = v; if State.JumpBoost then Movement.ApplyJump(true) end end,
    },
})

switches.Fly = addFeature({
    icon = "🕊", title = "Fly", desc = "Bay tự do: WASD + Space/Shift",
    color = THEME.Accent2,
    onToggle = function(on) State.Fly = on; Movement.ApplyFly(on) end,
    slider = {
        min = 20, max = 300, default = State.FlySpeed, label = "Tốc độ bay",
        onChanged = function(v) State.FlySpeed = v end,
    },
})

switches.Noclip = addFeature({
    icon = "🚪", title = "Noclip", desc = "Đi xuyên tường/vật cản",
    color = THEME.Accent2,
    onToggle = function(on) Noclip.SetEnabled(on) end,
})

addSection("CHIẾN ĐẤU")

switches.God = addFeature({
    icon = "🛡", title = "Bất Tử (God Mode)", desc = "Miễn nhiễm mọi sát thương, kể cả đòn chí mạng",
    color = THEME.Red,
    onToggle = function(on) God.SetEnabled(on) end,
})

switches.AutoFarm = addFeature({
    icon = "⚔", title = "Auto Farm", desc = "Tự bay tới và đánh quái",
    color = THEME.Warn,
    onToggle = function(on) AutoFarm.SetEnabled(on) end,
    build = function(card)
        makeDropdown(card, {
            order = 2, default = State.FarmTarget,
            getItems = function() return MobUtil.names() end,
            onSelect = function(name) State.FarmTarget = name end,
        })
        makeSlider(card, {
            order = 3, min = 0, max = 15, default = State.FarmHeight, label = "Độ cao khi đánh",
            onChanged = function(v) State.FarmHeight = v end,
        })
    end,
})

------------------------------------------------------------------
-- KHỞI ĐỘNG: nút mở/đóng, phím tắt, FPS, hồi sinh nhân vật
------------------------------------------------------------------
local function setMenuOpen(v)
    State.MenuOpen = v
    root.Visible = v
    fab.Visible = not v
end

closeBtn.MouseButton1Click:Connect(function() setMenuOpen(false) end)
makeDraggable(fab, fab, function() setMenuOpen(true) end)
makeDraggable(header, root)

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == CONFIG.MenuKey then
        setMenuOpen(not State.MenuOpen)
    end
end)

-- đồng hồ FPS
do
    local frames, timer = 0, 0
    RunService.RenderStepped:Connect(function(dt)
        frames += 1
        timer += dt
        if timer >= 1 then
            fpsLabel.Text = frames .. " FPS"
            frames, timer = 0, 0
        end
    end)
end

-- áp lại toàn bộ trạng thái mỗi khi nhân vật hồi sinh
local function onCharacterAdded(char)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hum then return end
    task.wait(0.25)

    baseStats.WalkSpeed  = hum.WalkSpeed
    baseStats.JumpPower  = hum.JumpPower

    if State.Speed then Movement.ApplySpeed(true) end
    if State.JumpBoost then Movement.ApplyJump(true) end
    if State.Fly then Movement.ApplyFly(true) end
    if State.God then God.Hook(hum) end
    if State.Noclip then Noclip.SetEnabled(true) end
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
if LocalPlayer.Character then onCharacterAdded(LocalPlayer.Character) end

setMenuOpen(State.MenuOpen)
toast("Longdzvcl đã tải xong!", THEME.Accent)
