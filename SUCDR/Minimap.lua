-- SUCDR - ikona u minimapy (bez knihoven)
-- Levý klik otevře/zavře okno, pravý klik otevře Nastavení, tažením jde posunout po okraji.
local _, ns = ...
local T = ns.T

local btn

-- Které čtvrtiny minimapy jsou kulaté (stejně jako LibDBIcon), podle GetMinimapShape()
local SHAPES = {
    ROUND = { true, true, true, true },
    SQUARE = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function updatePosition()
    local angle = math.rad(ns.db.minimapAngle or 200)
    local x, y = math.cos(angle), math.sin(angle)
    local q = 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local round = (SHAPES[shape] or SHAPES.ROUND)[q]
    local w = (Minimap:GetWidth() / 2) + 5
    local h = (Minimap:GetHeight() / 2) + 5
    if round then
        x, y = x * w, y * h
    else
        -- hranatý roh: posun po úhlopříčce a oříznutí na okraj čtverce
        local dw = math.sqrt(2 * w * w) - 10
        local dh = math.sqrt(2 * h * h) - 10
        x = math.max(-w, math.min(x * dw, w))
        y = math.max(-h, math.min(y * dh, h))
    end
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function onDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    ns.db.minimapAngle = math.deg(math.atan2(py - my, px - mx))
    updatePosition()
end

local function create()
    btn = CreateFrame("Button", "SUCDRMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(19, 19)
    icon:SetTexture(ns.ICON)
    icon:SetPoint("TOPLEFT", 6, -5)
    -- kulatý výřez jako u ostatních ikon u minimapy
    if icon.SetMask then icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ns.UI.ShowTab("settings")
        else
            ns.UI.Toggle()
        end
    end)
    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", onDragUpdate)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("SUCDR")
        local s = ns.Game.state
        if s and s.phase ~= "done" then
            GameTooltip:AddLine(ns.Game.ModeName(s.phase == "lobby" and s.choice or s.mode) .. " - " .. ns.Gold(s.bet),
                1, 1, 1)
        end
        GameTooltip:AddLine(T("mm_left"), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(T("mm_right"), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(T("mm_drag"), 0.6, 0.6, 0.6)
        GameTooltip:Show()
        ns.UI.CzechTooltip()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    updatePosition()
end

function ns.UpdateMinimapButton()
    if ns.db.minimap then
        if not btn then create() end
        btn:SetParent(Minimap)
        btn:SetFrameStrata("MEDIUM")
        btn:SetFrameLevel(8)
        updatePosition()
        btn:Show()
    elseif btn then
        btn:Hide()
    end
end

-- /sucdr minimap: vrátí ikonu na výchozí místo a zobrazí ji
function ns.ResetMinimapButton()
    ns.db.minimap = true
    ns.db.minimapAngle = 200
    ns.UpdateMinimapButton()
end

-- tvar a velikost minimapy můžou jiné addony změnit až po načtení
ns.OnInit(ns.UpdateMinimapButton)
ns.On("PLAYER_ENTERING_WORLD", function()
    if ns.db.minimap and btn then updatePosition() end
end)
