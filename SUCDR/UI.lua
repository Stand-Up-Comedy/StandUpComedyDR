-- SUCDR - okno s tlačítky (plochý tmavý vzhled s oranžovým akcentem)
local _, ns = ...
local T = ns.T

local UI = {}
ns.UI = UI

local f
local panels, tabs = {}, {}
local current = "game"
local gp, dp, hp, sp = {}, {}, {}, {}

---------------------------------------------------------------------------
-- Barvy
---------------------------------------------------------------------------
local C = {
    bg = { 0.055, 0.058, 0.07, 0.97 },
    surface = { 0.10, 0.105, 0.125, 1 },
    hover = { 0.15, 0.155, 0.185, 1 },
    field = { 0.035, 0.037, 0.045, 1 },
    border = { 0.21, 0.22, 0.26, 1 },
    accent = { 1, 0.56, 0.16, 1 },
    accentHover = { 1, 0.66, 0.32, 1 },
    text = { 0.93, 0.93, 0.95, 1 },
    muted = { 0.58, 0.60, 0.66, 1 },
    disabled = { 0.40, 0.41, 0.45, 1 },
    dark = { 0.07, 0.06, 0.05, 1 },
}
local ACCENT = "|cffff8f29"
UI.ACCENT = ACCENT

local function SetColor(tex, c) tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end

---------------------------------------------------------------------------
-- Fonty: výchozí UI font (Friz Quadrata) nemá č, ř, ě, ů. Přibalený Inter
-- (Media\, licence OFL) češtinu má; náhradou je font chatu.
---------------------------------------------------------------------------
local CHAT_FONT = ChatFontNormal:GetFont()
local MEDIA = "Interface\\AddOns\\SUCDR\\Media\\"
local INTER = MEDIA .. "Inter-Regular.ttf"
local INTER_SEMI = MEDIA .. "Inter-SemiBold.ttf"

-- velikost pro Inter / pro font chatu (Inter je širší)
local FONT_DEFS = {
    small = { "SUCDRFontSmall", 10, 11 },
    normal = { "SUCDRFontNormal", 11, 12 },
    big = { "SUCDRFontBig", 14, 15, true },
    title = { "SUCDRFontTitle", 15, 16, true },
}

local Fonts = {}
for key, def in pairs(FONT_DEFS) do
    local font = CreateFont(def[1])
    font:SetFont(CHAT_FONT, def[3], "")
    font:SetShadowOffset(1, -1)
    font:SetShadowColor(0, 0, 0, 0.8)
    Fonts[key] = font
end

-- Přepne všechny font objekty (prvky okna se překreslí samy)
function UI.ApplyFont()
    local inter = ns.db and ns.db.font
    for key, def in pairs(FONT_DEFS) do
        if inter then
            Fonts[key]:SetFont(def[4] and INTER_SEMI or INTER, def[2], "")
        else
            Fonts[key]:SetFont(CHAT_FONT, def[3], "")
        end
    end
end
ns.OnInit(UI.ApplyFont)

---------------------------------------------------------------------------
-- Přeložitelné texty: zaregistrované prvky se přepíšou při změně jazyka
---------------------------------------------------------------------------
local texts, checks = {}, {}
local function Loc(widget, key)
    texts[#texts + 1] = { widget, key }
    widget:SetText(T(key))
    return widget
end

---------------------------------------------------------------------------
-- Stavební kostky
---------------------------------------------------------------------------
local function Border(fr, c)
    if not fr.borders then
        local function line() return fr:CreateTexture(nil, "BORDER", nil, 7) end
        local top, bottom, left, right = line(), line(), line(), line()
        top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
        bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(1)
        left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(1)
        right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(1)
        fr.borders = { top, bottom, left, right }
    end
    for _, t in ipairs(fr.borders) do SetColor(t, c) end
end

local function Skin(fr, bg, border)
    if not fr.bg then
        fr.bg = fr:CreateTexture(nil, "BACKGROUND", nil, -8)
        fr.bg:SetAllPoints()
    end
    SetColor(fr.bg, bg)
    if border then Border(fr, border) end
    return fr
end

-- style: "label" (šedý popisek), "text" (bílý), "small", "big", "header" (oranžový)
local function Label(parent, text, style)
    local t = parent:CreateFontString(nil, "OVERLAY")
    style = style or "label"
    t:SetFontObject((style == "small" or style == "label") and Fonts.small
        or (style == "big" and Fonts.big) or (style == "title" and Fonts.title) or Fonts.normal)
    local c = (style == "label" and C.muted) or (style == "header" and C.accent) or C.text
    t:SetTextColor(c[1], c[2], c[3])
    t:SetText(text or "")
    t:SetJustifyH("LEFT")
    return t
end

-- Ploché tlačítko; primary = plné v barvě akcentu
local function Btn(parent, text, w, h, onClick, primary)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h or 24)
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetFontObject((h or 24) >= 30 and Fonts.big or Fonts.normal)
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    b.text:SetWordWrap(false)
    b:SetFontString(b.text)
    b:SetPushedTextOffset(1, -1)
    b.primary = primary
    Skin(b, C.surface, C.border)

    function b:Paint()
        local hover = self:IsEnabled() and self:IsMouseOver()
        local tc
        if not self:IsEnabled() then
            SetColor(self.bg, C.surface)
            Border(self, C.border)
            tc = C.disabled
        elseif self.primary then
            SetColor(self.bg, hover and C.accentHover or C.accent)
            Border(self, C.accent)
            tc = C.dark
        else
            SetColor(self.bg, (hover or self.selected) and C.hover or C.surface)
            Border(self, (hover or self.selected) and C.accent or C.border)
            tc = self.selected and C.accent or C.text
        end
        self.text:SetTextColor(tc[1], tc[2], tc[3])
    end
    function b:SetSelected(v)
        self.selected = v
        self:Paint()
    end
    b:SetScript("OnEnter", b.Paint)
    b:SetScript("OnLeave", b.Paint)
    b:SetScript("OnEnable", b.Paint)
    b:SetScript("OnDisable", b.Paint)
    if onClick then b:SetScript("OnClick", onClick) end
    b:SetText(text or "")
    b:Paint()
    return b
end

-- Záložka: jen text s oranžovým podtržením u vybrané
local function Tab(parent, w, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 30)
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetFontObject(Fonts.normal)
    b.text:SetPoint("CENTER", 0, 1)
    b:SetFontString(b.text)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetPoint("BOTTOMLEFT", 8, 0)
    b.line:SetPoint("BOTTOMRIGHT", -8, 0)
    b.line:SetHeight(2)
    SetColor(b.line, C.accent)
    function b:Paint()
        local c = (self.selected or self:IsMouseOver()) and C.text or C.muted
        self.text:SetTextColor(c[1], c[2], c[3])
        self.line:SetShown(self.selected and true or false)
    end
    function b:SetSelected(v)
        self.selected = v
        self:Paint()
    end
    b:SetScript("OnEnter", b.Paint)
    b:SetScript("OnLeave", b.Paint)
    b:SetScript("OnClick", onClick)
    b:Paint()
    return b
end

local function Edit(parent, w)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w, 22)
    e:SetAutoFocus(false)
    e:SetNumeric(true)
    e:SetFontObject(Fonts.normal)
    e:SetTextColor(C.text[1], C.text[2], C.text[3])
    e:SetTextInsets(7, 7, 0, 0)
    Skin(e, C.field, C.border)
    e:SetScript("OnEditFocusGained", function(self) Border(self, C.accent) end)
    e:SetScript("OnEditFocusLost", function(self) Border(self, C.border) end)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    return e
end

local function Check(parent, key, onClick)
    local c = CreateFrame("CheckButton", nil, parent)
    c:SetSize(16, 16)
    Skin(c, C.field, C.border)
    c:SetCheckedTexture("Interface\\Buttons\\WHITE8X8")
    local mark = c:GetCheckedTexture()
    mark:ClearAllPoints()
    mark:SetPoint("TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", -3, 3)
    mark:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
    c.label = Label(c, "", "text")
    c.label:SetFontObject(Fonts.normal)
    c.label:SetPoint("LEFT", c, "RIGHT", 8, 0)
    Loc(c.label, key)
    c:SetScript("OnEnter", function(self) Border(self, C.accent) end)
    c:SetScript("OnLeave", function(self) Border(self, C.border) end)
    c:SetScript("OnClick", onClick)
    checks[#checks + 1] = c
    return c
end

-- Popisek zaškrtávátka je taky klikací
local function UpdateCheckHitRects()
    for _, c in ipairs(checks) do
        c:SetHitRectInsets(0, -(c.label:GetStringWidth() + 10), -3, -3)
    end
end

-- Panel s okrajem a oranžovým proužkem vlevo
local function Box(parent)
    local b = Skin(CreateFrame("Frame", nil, parent), C.surface, C.border)
    local stripe = b:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT", 1, -1)
    stripe:SetPoint("BOTTOMLEFT", 1, 1)
    stripe:SetWidth(3)
    SetColor(stripe, C.accent)
    return b
end

-- Tenký posuvník + kolečko myši pro ScrollFrame
local function AttachScroll(scroll, step)
    local thumb = scroll:GetParent():CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
    local function update()
        local range = scroll:GetVerticalScrollRange()
        local h = scroll:GetHeight()
        if range <= 0 or h <= 0 then
            thumb:Hide()
            return
        end
        local th = math.max(20, h * h / (h + range))
        local off = (h - th) * math.min(1, scroll:GetVerticalScroll() / range)
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 3, -off)
        thumb:Show()
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * step)))
    end)
    scroll:SetScript("OnScrollRangeChanged", function(self)
        local range = self:GetVerticalScrollRange()
        if self:GetVerticalScroll() > range then self:SetVerticalScroll(math.max(0, range)) end
        update()
    end)
    scroll:SetScript("OnVerticalScroll", update)
    scroll:HookScript("OnSizeChanged", update)
    return update
end

-- Seznam s řádky: pruhované pozadí, ikona, text, volitelné tlačítko.
-- list.frame je rámeček, který se umisťuje.
local function CreateList(parent, rowHeight)
    local frame = Skin(CreateFrame("Frame", nil, parent), C.field, C.border)
    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", 1, -1)
    scroll:SetPoint("BOTTOMRIGHT", -8, 1)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    local list = { frame = frame, scroll = scroll, content = content, rows = {} }
    list.updateThumb = AttachScroll(scroll, rowHeight * 2)

    list.empty = Label(frame, "", "label")
    list.empty:SetPoint("TOP", 0, -14)

    function list:SetItems(items, render, emptyText)
        content:SetWidth(math.max(1, scroll:GetWidth()))
        for i, item in ipairs(items) do
            local row = self.rows[i]
            if not row then
                row = CreateFrame("Frame", nil, content)
                row:SetHeight(rowHeight)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
                row:SetPoint("RIGHT", content, "RIGHT")
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
                row.hl = row:CreateTexture(nil, "BORDER")
                row.hl:SetAllPoints()
                row.mark = row:CreateTexture(nil, "ARTWORK")
                row.mark:SetPoint("TOPLEFT")
                row.mark:SetPoint("BOTTOMLEFT")
                row.mark:SetWidth(2)
                SetColor(row.mark, C.accent)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(rowHeight - 8, rowHeight - 8)
                row.icon:SetPoint("LEFT", 8, 0)
                row.text = row:CreateFontString(nil, "OVERLAY")
                row.text:SetFontObject(Fonts.normal)
                row.text:SetTextColor(C.text[1], C.text[2], C.text[3])
                row.text:SetJustifyH("LEFT")
                row.text:SetWordWrap(false)
                row.button = Btn(row, "", 84, rowHeight - 6)
                row.button:SetPoint("RIGHT", -4, 0)
                self.rows[i] = row
            end
            row:Show()
            row.button:Hide()
            row.button:SetScript("OnEnter", row.button.Paint)
            row.button:SetScript("OnLeave", row.button.Paint)
            row.hl:Hide()
            row.mark:Hide()
            row.icon:Hide()
            render(row, item, i)
            row.text:ClearAllPoints()
            row.text:SetPoint("LEFT", row.icon:IsShown() and (rowHeight + 2) or 10, 0)
            row.text:SetPoint("RIGHT", row.button:IsShown() and -92 or -6, 0)
        end
        for i = #items + 1, #self.rows do self.rows[i]:Hide() end
        content:SetHeight(math.max(1, #items * rowHeight))
        self.empty:SetText(#items == 0 and (emptyText or "") or "")
        self.updateThumb()
    end

    return list
end

-- Tooltip: GameTooltip kreslí font bez č, ř, ě, ů. Po Show() se řádky přepnou na font addonu
-- (Inter, nebo font chatu) a po skrytí tooltipu se vrátí původní font.
local tipFonts = {}
function UI.CzechTooltip()
    local inter = ns.db and ns.db.font
    for i = 1, GameTooltip:NumLines() do
        for _, side in ipairs({ "Left", "Right" }) do
            local fs = _G["GameTooltipText" .. side .. i]
            if fs and not tipFonts[fs] then
                local font, size, flags = fs:GetFont()
                tipFonts[fs] = { font, size, flags }
                local file = inter and ((i == 1) and INTER_SEMI or INTER) or CHAT_FONT
                fs:SetFont(file, (size or 12) - (inter and 1 or 0), flags or "")
            end
        end
    end
    GameTooltip:Show() -- přepočítá velikost
end
GameTooltip:HookScript("OnHide", function()
    for fs, o in pairs(tipFonts) do
        if o[1] then fs:SetFont(o[1], o[2], o[3] or "") end
        tipFonts[fs] = nil
    end
end)

-- Okno: tmavý panel, záhlaví s ikonou a tlačítkem zavřít, tahá se za záhlaví
local function Window(name, w, h)
    local win = CreateFrame("Frame", name, UIParent)
    win:SetSize(w, h)
    win:SetPoint("CENTER")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetClampedToScreen(true)
    win:SetFrameStrata("DIALOG")
    Skin(win, C.bg, C.border)
    tinsert(UISpecialFrames, name)

    local top = win:CreateTexture(nil, "ARTWORK")
    top:SetPoint("TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", -1, -1)
    top:SetHeight(2)
    SetColor(top, C.accent)

    local bar = Skin(CreateFrame("Frame", nil, win), C.surface)
    bar:SetPoint("TOPLEFT", 1, -3)
    bar:SetPoint("TOPRIGHT", -1, -3)
    bar:SetHeight(30)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() win:StartMoving() end)
    bar:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
    win.bar = bar

    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexture(ns.ICON)
    win.title = Label(bar, "", "title")
    win.title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    win.subtitle = Label(bar, "", "label")
    win.subtitle:SetPoint("LEFT", win.title, "RIGHT", 8, -1)

    local close = CreateFrame("Button", nil, bar)
    close:SetSize(30, 30)
    close:SetPoint("RIGHT")
    close.text = Label(close, "X", "big")
    close.text:SetPoint("CENTER")
    close.text:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    close:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 0.35, 0.3) end)
    close:SetScript("OnLeave", function(self) self.text:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end)
    close:SetScript("OnClick", function() win:Hide() end)
    return win
end

-- Potvrzovací okno místo StaticPopup (ten má font bez českých znaků).
-- buttons = { { "text", fn, primary }, ... } (1-3 tlačítka, bez fn jen zavře)
local confirm
function UI.Confirm(text, buttons)
    if not confirm then
        confirm = Window("SUCDRConfirm", 380, 150)
        confirm:SetFrameStrata("FULLSCREEN_DIALOG")
        confirm:ClearAllPoints()
        confirm:SetPoint("TOP", 0, -160)
        confirm.title:SetText(ACCENT .. "SUCDR|r")
        confirm.msg = Label(confirm, "", "text")
        confirm.msg:SetPoint("TOPLEFT", 16, -48)
        confirm.msg:SetPoint("TOPRIGHT", -16, -48)
        confirm.msg:SetJustifyH("CENTER")
        confirm.btns = {}
    end
    confirm.msg:SetText(text)
    for _, b in ipairs(confirm.btns) do b:Hide() end
    local n = #buttons
    local w = math.floor((380 - 32 - (n - 1) * 8) / n)
    for i, def in ipairs(buttons) do
        local b = confirm.btns[i]
        if not b then
            b = Btn(confirm, "", w, 28, function(self)
                confirm:Hide()
                if self.fn then self.fn() end
            end)
            confirm.btns[i] = b
        end
        b:SetSize(w, 28)
        b:SetText(def[1])
        b.fn = def[2]
        b.primary = def[3]
        b:Paint()
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", 16 + (i - 1) * (w + 8), 14)
        b:Show()
    end
    confirm:SetHeight(48 + confirm.msg:GetStringHeight() + 60)
    confirm:Show()
    confirm:Raise()
end

local function fmtTime(t) return date("%d.%m. %H:%M", t or 0) end

local function readNumber(edit, fallback)
    local n = tonumber(edit:GetText())
    return n or fallback
end

local function version() return C_AddOns.GetAddOnMetadata("SUCDR", "Version") or "?" end

-- Barvy povolání hráčů ve skupině (jméno -> "|cffxxxxxx"), přepočet jen při změně skupiny
local colorCache
ns.On("GROUP_ROSTER_UPDATE", function() colorCache = nil end)
ns.On("PLAYER_ENTERING_WORLD", function() colorCache = nil end)
local function classColors()
    if colorCache then return colorCache end
    local map = {}
    colorCache = map
    local function add(unit)
        local name = ns.UnitFull(unit)
        local _, class = UnitClass(unit)
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if name and c and c.colorStr then map[name] = "|c" .. c.colorStr end
    end
    add("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do add("raid" .. i) end
    else
        for i = 1, GetNumSubgroupMembers() do add("party" .. i) end
    end
    return map
end

local ICON_READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ICON_NOT = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local ICON_WAIT = "Interface\\RaidFrame\\ReadyCheck-Waiting"

---------------------------------------------------------------------------
-- Záložka Hra
---------------------------------------------------------------------------
local function Field(p, key, w, anchor, x)
    local l = Loc(Label(p, "", "label"), key)
    if anchor then l:SetPoint("LEFT", anchor, "RIGHT", x or 16, 0) else l:SetPoint("TOPLEFT", 0, -10) end
    local e = Edit(p, w)
    e:SetPoint("LEFT", l, "RIGHT", 8, 0)
    return e
end

local function BuildGame(p)
    local G = ns.Game

    gp.bet = Field(p, "bet_label", 84)
    gp.bet:SetText(tostring(ns.db.bet))
    gp.bet:SetScript("OnTextChanged", function(self) ns.db.bet = readNumber(self, ns.db.bet) end)
    gp.time = Field(p, "limit_label", 40, gp.bet, 24)
    gp.time:SetText(tostring(ns.db.roundTime))
    gp.time:SetScript("OnTextChanged", function(self) ns.db.roundTime = readNumber(self, ns.db.roundTime) end)

    local W, GAP = 108, 6
    gp.create = Btn(p, "", W, 26, function() G.Create(readNumber(gp.bet)) end, true)
    gp.create:SetPoint("TOPLEFT", 0, -40)
    gp.join = Loc(Btn(p, "", W, 26, G.Join), "btn_join")
    gp.join:SetPoint("LEFT", gp.create, "RIGHT", GAP, 0)
    gp.leave = Loc(Btn(p, "", W, 26, G.Leave), "btn_leave")
    gp.leave:SetPoint("LEFT", gp.join, "RIGHT", GAP, 0)
    gp.target = Btn(p, "", W, 26, function()
        if G.state and G.state.test then G.AddBot() else G.AddTarget() end
    end)
    gp.target:SetPoint("LEFT", gp.leave, "RIGHT", GAP, 0)

    gp.startBtn = Loc(Btn(p, "", W, 26, G.Start, true), "btn_start")
    gp.startBtn:SetPoint("TOPLEFT", 0, -72)
    gp.cancel = Loc(Btn(p, "", W, 26, G.Cancel), "btn_cancel")
    gp.cancel:SetPoint("LEFT", gp.startBtn, "RIGHT", GAP, 0)
    -- Přepínač režimu: klik přepne na další režim
    gp.mode = Btn(p, "", W * 2 + GAP, 26, function()
        local modes, cur = G.MODES, ns.db.mode or "auto"
        local s = G.state
        if s and s.isHost and s.phase == "lobby" then cur = s.choice or cur end
        local nextMode = modes[1]
        for i, m in ipairs(modes) do
            if m == cur then nextMode = modes[i % #modes + 1] end
        end
        G.SetMode(nextMode)
    end)
    gp.mode:SetPoint("LEFT", gp.cancel, "RIGHT", GAP, 0)
    gp.mode:HookScript("OnEnter", function(self)
        local s = G.state
        local m = (s and s.phase == "lobby" and s.choice) or ns.db.mode or "auto"
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(G.ModeName(m))
        GameTooltip:AddLine(G.ModeHelp(m), 1, 1, 1, true)
        GameTooltip:AddLine(T("mode_tip_click"), 0.6, 0.6, 0.6)
        GameTooltip:Show()
        UI.CzechTooltip()
    end)
    gp.mode:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- Stav hry s ukazatelem zbývajícího času
    gp.box = Box(p)
    gp.box:SetPoint("TOPLEFT", 0, -110)
    gp.box:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    gp.box:SetHeight(58)
    gp.status = Label(gp.box, "", "text")
    gp.status:SetPoint("TOPLEFT", 14, -9)
    gp.status:SetPoint("RIGHT", gp.box, "RIGHT", -60, 0)
    gp.status:SetJustifyV("TOP")
    gp.status:SetSpacing(3)
    gp.timerText = Label(gp.box, "", "big")
    gp.timerText:SetPoint("TOPRIGHT", -12, -9)
    gp.timerText:SetJustifyH("RIGHT")
    gp.track = gp.box:CreateTexture(nil, "ARTWORK")
    gp.track:SetPoint("BOTTOMLEFT", 4, 1)
    gp.track:SetPoint("BOTTOMRIGHT", -1, 1)
    gp.track:SetHeight(3)
    gp.track:SetColorTexture(1, 1, 1, 0.06)
    gp.bar = CreateFrame("StatusBar", nil, gp.box)
    gp.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    gp.bar:SetAllPoints(gp.track)
    gp.bar:SetMinMaxValues(0, 1)
    gp.bar:Hide()

    gp.header = Label(p, "", "header")
    gp.header:SetPoint("TOPLEFT", 2, -180)

    gp.list = CreateList(p, 24)
    gp.list.frame:SetPoint("TOPLEFT", 0, -198)
    gp.list.frame:SetPoint("BOTTOMRIGHT", 0, 60)
    -- logo guildy, když se nehraje
    gp.logo = gp.list.frame:CreateTexture(nil, "ARTWORK")
    gp.logo:SetSize(170, 170)
    gp.logo:SetPoint("CENTER")
    gp.logo:SetTexture(ns.LOGO)
    gp.logo:SetAlpha(0.9)

    gp.roll = Btn(p, "", 280, 42, G.Roll, true)
    gp.roll:SetPoint("BOTTOM", 0, 6)
    -- Pulzující záře, když jsem na řadě
    gp.glow = gp.roll:CreateTexture(nil, "OVERLAY")
    gp.glow:SetPoint("TOPLEFT", -2, 2)
    gp.glow:SetPoint("BOTTOMRIGHT", 2, -2)
    gp.glow:SetColorTexture(1, 0.75, 0.4, 0.35)
    gp.glow:SetBlendMode("ADD")
    gp.glow:Hide()
    gp.pulse = gp.glow:CreateAnimationGroup()
    gp.pulse:SetLooping("BOUNCE")
    local a = gp.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(0.1)
    a:SetToAlpha(0.8)
    a:SetDuration(0.6)
end

-- Ukazatel času se překresluje každý snímek
local function UpdateTimer()
    local s = ns.Game.state
    local left = s and s.phase == "running" and s.deadline and math.max(0, s.deadline - GetTime())
    if not left then
        gp.bar:Hide()
        gp.timerText:SetText("")
        return
    end
    local total = (s.limit and s.limit > 0) and s.limit or math.max(left, 1)
    local frac = math.min(1, left / total)
    gp.bar:SetValue(frac)
    local r, g, b
    if frac > 0.5 then
        r, g, b = 0.3, 0.85, 0.45
    elseif frac > 0.25 then
        r, g, b = C.accent[1], C.accent[2], C.accent[3]
    else
        r, g, b = 1, 0.3, 0.25
    end
    gp.bar:SetStatusBarColor(r, g, b)
    gp.timerText:SetTextColor(r, g, b)
    gp.bar:Show()
    gp.timerText:SetText(("%d s"):format(math.ceil(left)))
end

local function statusText(s)
    if not s then return T("st_none") end
    local G = ns.Game
    if s.phase == "lobby" then
        return T("st_lobby", G.ModeName(s.choice), #s.players, ns.Gold(s.bet), s.start, ns.Display(s.host))
    elseif s.phase == "running" then
        if G.TurnBased(s) then
            local p = s.players[s.turn]
            return T("st_turn", G.ModeName(s.mode), ns.Gold(s.bet), ns.Display(p and p.name), s.curMax or 0)
        end
        local n = 0
        for _, q in ipairs(s.players) do if q.state == "a" then n = n + 1 end end
        return T("st_mass", ns.Gold(s.bet), s.round or 0, n, #s.players)
    end
    if s.loser then
        return T("st_ring_done", ns.Display(s.loser), ns.Gold(s.bet), ns.Display(s.winner))
    end
    return T("st_done", ns.Display(s.winner), ns.Gold(s.bet))
end

local function RefreshGame()
    local G = ns.Game
    local s = G.state
    local me = ns.Me()
    local inGroup = ns.GroupChannel() ~= nil
    local active = s and s.phase ~= "done"
    local host = s and s.isHost
    local lobby = s and s.phase == "lobby"
    local mine = s and G.FindPlayer(me)

    gp.create:SetEnabled((inGroup or G.testMode) and not active)
    gp.create:SetText(T(G.testMode and "btn_create_test" or "btn_create"))
    gp.target:SetText(T((s and s.test) and "btn_bot" or "btn_target"))
    gp.join:SetEnabled((lobby and not mine) and true or false)
    gp.leave:SetEnabled((lobby and mine) and true or false)
    gp.target:SetEnabled((lobby and host) and true or false)
    gp.startBtn:SetEnabled((lobby and host and #s.players >= 2) and true or false)
    gp.cancel:SetEnabled((active and host) and true or false)
    local modeShown = (lobby and s.choice) or ns.db.mode or "auto"
    gp.mode:SetText(T("btn_mode", G.ModeName(modeShown)))
    gp.mode:SetEnabled((not active or (lobby and host)) and true or false)

    local prefix = ""
    if (s and s.test) or (not s and G.testMode) then prefix = ACCENT .. T("st_test_prefix") .. "|r" end
    -- bez skupiny a testu nejde hru založit: řekni proč, ať tlačítka nejsou šedá bez vysvětlení
    gp.status:SetText(prefix .. ((not s and not inGroup and not G.testMode) and T("need_group") or statusText(s)))
    UpdateTimer()

    local max = G.MyRollMax()
    gp.roll:SetText(max and T("btn_roll_range", max) or T("btn_roll"))
    local canRoll = G.CanRollNow()
    gp.roll:SetEnabled(canRoll)
    if canRoll then
        if not gp.pulse:IsPlaying() then gp.glow:Show(); gp.pulse:Play() end
    elseif gp.pulse:IsPlaying() or gp.glow:IsShown() then
        gp.pulse:Stop()
        gp.glow:Hide()
    end

    local players = s and s.players or {}
    gp.logo:SetShown(#players == 0)
    gp.header:SetText(("%s  |cff888888%d|r"):format(T("players_header"), #players))
    local colors = classColors()
    gp.list:SetItems(players, function(row, p, idx)
        local info, icon
        local onTurn = false
        if p.state == "w" then
            info, icon = "|cff60ff80" .. T("pl_winner") .. "|r", ICON_READY
        elseif p.state == "o" then
            info = (s.loser and ("|cffff6060" .. T("pl_pays") .. "|r") or ("|cff888888" .. T("pl_out") .. "|r"))
                .. (p.last and ("|cff888888" .. T("pl_rolled_n", p.last) .. "|r") or "")
            icon = ICON_NOT
        elseif p.state == "s" then
            info = "|cff888888" .. T("pl_safe") .. "|r"
        elseif s.phase == "lobby" then
            info = "|cff888888" .. T("pl_ready") .. "|r"
        elseif G.TurnBased(s) then
            onTurn = (idx == s.turn)
            info = onTurn and (ACCENT .. T("pl_on_turn", s.curMax or 0) .. "|r")
                or (p.last and T("pl_rolled", p.last) or ("|cff888888" .. T("pl_waiting") .. "|r"))
            if onTurn then icon = ICON_WAIT end
        else
            onTurn = not p.rolled
            info = p.rolled and T("pl_rolled", p.last or 0) or (ACCENT .. T("pl_rolling", p.max or 0) .. "|r")
            if onTurn then icon = ICON_WAIT end
        end
        if icon then
            row.icon:SetTexture(icon)
            row.icon:Show()
        end
        if onTurn then
            row.hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.10)
            row.hl:Show()
            row.mark:Show()
        elseif p.name == me then
            row.hl:SetColorTexture(0.4, 0.7, 1, 0.07)
            row.hl:Show()
        end
        local order = (s.mode == "ring" and s.phase ~= "lobby") and ("|cff888888" .. idx .. ".|r ") or ""
        local color = colors[p.name] or "|cffffffff"
        local hostTag = (p.name == s.host) and ("  |cff888888" .. T("pl_host") .. "|r") or ""
        row.text:SetText(("%s%s%s|r%s     %s"):format(order, color, ns.Display(p.name), hostTag, info))
    end)
end

---------------------------------------------------------------------------
-- Záložka Dluhy
---------------------------------------------------------------------------
local function BuildDebts(p)
    dp.onlyMine = Check(p, "debts_only_mine", function() ns.RefreshUI() end)
    dp.onlyMine:SetPoint("TOPLEFT", 2, -6)
    dp.onlyMine:SetChecked(true)
    dp.showPaid = Check(p, "debts_show_paid", function() ns.RefreshUI() end)
    dp.showPaid:SetPoint("LEFT", dp.onlyMine.label, "RIGHT", 24, 0)
    dp.sync = Loc(Btn(p, "", 130, 26, function() ns.Ledger.RequestSync() end), "btn_sync")
    dp.sync:SetPoint("TOPRIGHT", 0, 0)

    -- Dvě karty se součty
    local function Card(key, color)
        local card = Box(p)
        card:SetHeight(58)
        local l = Loc(Label(card, "", "label"), key)
        l:SetPoint("TOPLEFT", 14, -10)
        card.value = Label(card, "", "title")
        card.value:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -6)
        card.value:SetTextColor(color[1], color[2], color[3])
        return card
    end
    dp.oweCard = Card("debts_owe", { 1, 0.42, 0.4 })
    dp.oweCard:SetPoint("TOPLEFT", 0, -38)
    dp.oweCard:SetPoint("RIGHT", p, "CENTER", -4, 0)
    dp.owedCard = Card("debts_owed", { 0.4, 0.9, 0.5 })
    dp.owedCard:SetPoint("TOPLEFT", p, "TOP", 4, -38)
    dp.owedCard:SetPoint("RIGHT", p, "RIGHT", 0, 0)

    dp.list = CreateList(p, 26)
    dp.list.frame:SetPoint("TOPLEFT", 0, -106)
    dp.list.frame:SetPoint("BOTTOMRIGHT", 0, 0)
end

local function RefreshDebts()
    local me = ns.Me()
    local L = ns.Ledger
    local items, owe, owed = {}, 0, 0
    local onlyMine, showPaid = dp.onlyMine:GetChecked(), dp.showPaid:GetChecked()
    for _, d in pairs(ns.db.debts) do
        local involved = (d.from == me or d.to == me)
        if not d.paid and not d.unconfirmed then
            if d.from == me then owe = owe + L.Remaining(d) end
            if d.to == me then owed = owed + L.Remaining(d) end
        end
        if (involved or not onlyMine) and (showPaid or not d.paid) then
            items[#items + 1] = d
        end
    end
    table.sort(items, function(a, b)
        if a.paid ~= b.paid then return not a.paid end
        return (a.time or 0) > (b.time or 0)
    end)

    dp.oweCard.value:SetText(ns.Gold(owe))
    dp.owedCard.value:SetText(ns.Gold(owed))

    dp.list:SetItems(items, function(row, d)
        local color = d.paid and "|cff888888"
            or (d.from == me and "|cffff6a66")
            or (d.to == me and "|cff66e680")
            or "|cffffffff"
        local amount = d.paid and d.amount or L.Remaining(d)
        if d.paid then
            row.icon:SetTexture(ICON_READY)
            row.icon:Show()
        end
        local tag = (d.test and (ACCENT .. "TEST|r  ") or "")
            .. ((d.unconfirmed and not d.paid) and ("|cffffcc00" .. T("debt_unconfirmed_tag") .. "|r  ") or "")
        row.text:SetText(("%s%s%s  ->  %s   %s|r   |cff888888%s%s|r"):format(
            tag, color,
            ns.Display(d.from), ns.Display(d.to), ns.Gold(amount), fmtTime(d.time),
            d.paid and ("  " .. T("debt_paid_tag")) or ""))
        if d.unconfirmed and not d.paid and (d.from == me or d.to == me) then
            row.button:SetText(T("btn_review"))
            row.button:SetScript("OnClick", function()
                local text = T("review_debt", ns.Display(d.from), ns.Gold(amount), ns.Display(d.to))
                local id = d.id
                local confirmBtn = { T("btn_confirm"), function() L.Confirm(id) end, true }
                if d.from == me then
                    -- dlužník může dluh i odmítnout
                    UI.Confirm(text, { confirmBtn, { T("btn_reject"), function() L.Reject(id) end }, { T("btn_back") } })
                else
                    UI.Confirm(text, { confirmBtn, { T("btn_back") } })
                end
            end)
            row.button:Show()
        elseif not d.paid and d.to == me then
            row.button:SetText(T("btn_paid"))
            row.button:SetScript("OnClick", function()
                local id = d.id
                UI.Confirm(T("confirm_paid", ns.Gold(amount), ns.Display(d.from)),
                    { { T("btn_yes"), function() L.SetPaid(id, true) end, true }, { T("btn_no") } })
            end)
            row.button:Show()
        elseif not d.paid and not d.test and d.from == me then
            row.button:SetText(T("btn_pay"))
            row.button:SetScript("OnClick", function() L.Pay(d.to) end)
            row.button:SetScript("OnEnter", function(self)
                self:Paint()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(T("pay_tip", ns.Display(d.to), ns.Gold(L.OwedTo(d.to))), 1, 1, 1, true)
                GameTooltip:Show()
                UI.CzechTooltip()
            end)
            row.button:SetScript("OnLeave", function(self)
                self:Paint()
                GameTooltip:Hide()
            end)
            row.button:Show()
        end
    end, T("debts_empty"))
end

---------------------------------------------------------------------------
-- Záložka Historie
---------------------------------------------------------------------------
local function BuildHistory(p)
    hp.list = CreateList(p, 26)
    hp.list.frame:SetPoint("TOPLEFT", 0, 0)
    hp.list.frame:SetPoint("BOTTOMRIGHT", 0, 0)
end

-- Okno s textem logu, který jde označit a zkopírovat (Ctrl+A, Ctrl+C)
local logFrame
function UI.ShowLog(title, lines)
    if not logFrame then
        logFrame = Window("SUCDRLogFrame", 640, 460)
        logFrame:SetPoint("CENTER", 40, -20)
        logFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        local hint = Loc(Label(logFrame, "", "label"), "log_hint")
        hint:SetPoint("TOPLEFT", 14, -44)

        local holder = Skin(CreateFrame("Frame", nil, logFrame), C.field, C.border)
        holder:SetPoint("TOPLEFT", 12, -64)
        holder:SetPoint("BOTTOMRIGHT", -12, 12)
        local scroll = CreateFrame("ScrollFrame", nil, holder)
        scroll:SetPoint("TOPLEFT", 8, -8)
        scroll:SetPoint("BOTTOMRIGHT", -12, 8)
        local eb = CreateFrame("EditBox", nil, scroll)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(Fonts.small)
        eb:SetTextColor(C.text[1], C.text[2], C.text[3])
        eb:SetWidth(590)
        eb:SetScript("OnEscapePressed", function() logFrame:Hide() end)
        scroll:SetScrollChild(eb)
        AttachScroll(scroll, 40)
        logFrame.edit = eb
    end
    logFrame.title:SetText(title)
    logFrame.subtitle:SetText("")
    logFrame.edit:SetText(table.concat(lines, "\n"))
    logFrame:Show()
    logFrame.edit:SetFocus()
    logFrame.edit:HighlightText()
end

local function gameLogLines(g)
    local lines = {
        T("log_header", g.id or "?"),
        T("log_sub", fmtTime(g.time), g.mode or "?", ns.Gold(g.bet), ns.Display(g.winner), g.test and " | TEST" or ""),
        "",
    }
    for _, l in ipairs(g.log or { T("log_unavailable") }) do
        lines[#lines + 1] = l
    end
    return lines
end

function UI.ShowLastLog()
    local s = ns.Game.state
    if s and s.log and s.phase ~= "done" then
        UI.ShowLog(T("log_title_running"), s.log)
        return
    end
    local last
    for _, g in pairs(ns.db.games) do
        if g.log and (not last or (g.time or 0) > (last.time or 0)) then last = g end
    end
    if last then
        UI.ShowLog(T("log_title_last"), gameLogLines(last))
    else
        ns.Print(T("log_none"))
    end
end

local function RefreshHistory()
    local me = ns.Me()
    local items = {}
    for _, g in pairs(ns.db.games) do items[#items + 1] = g end
    table.sort(items, function(a, b) return (a.time or 0) > (b.time or 0) end)
    while #items > 200 do table.remove(items) end
    hp.list:SetItems(items, function(row, g)
        if g.winner == me then
            row.icon:SetTexture(ICON_READY)
            row.icon:Show()
        elseif g.loser == me or (not g.loser and tContains(g.players, me)) then
            row.icon:SetTexture(ICON_NOT)
            row.icon:Show()
        end
        local pays = g.loser and ("   " .. T("hist_pays") .. " |cffff6a66" .. ns.Display(g.loser) .. "|r") or ""
        local tag = (g.test and (ACCENT .. "TEST|r  ") or "")
            .. (g.unverified and ("|cffffcc00" .. T("debt_unconfirmed_tag") .. "|r  ") or "")
            .. (g.collected and ("|cff66b3ff" .. T("collected_tag") .. "|r  ") or "")
        row.text:SetText(("%s|cff888888%s|r   %s |cff888888(%d)|r   %s   %s |cff66e680%s|r%s"):format(
            tag, fmtTime(g.time), ns.Game.ModeName(g.mode), #g.players,
            ns.Gold(g.bet), T("hist_winner"), ns.Display(g.winner), pays))
        if g.log then
            row.button:SetText(T("btn_log"))
            row.button:SetScript("OnClick", function() UI.ShowLog(T("log_title_game"), gameLogLines(g)) end)
            row.button:Show()
        elseif ns.Sync.CanRequestLog(g) then
            row.button:SetText(T("btn_log_request"))
            row.button:SetScript("OnClick", function() ns.Sync.RequestLog(g) end)
            row.button:Show()
        end
    end, T("hist_empty"))
end

---------------------------------------------------------------------------
-- Záložka Statistiky (moje čísla + žebříček)
---------------------------------------------------------------------------
local stp = {}
local PERIODS = { "all", "30", "7" }
local SORTS = { "net", "wins", "games" }

local function nextOf(list, cur)
    for i, v in ipairs(list) do
        if v == cur then return list[i % #list + 1] end
    end
    return list[1]
end

local function signedGold(n)
    if n > 0 then return "|cff66e680+" .. ns.Gold(n) .. "|r" end
    if n < 0 then return "|cffff6a66-" .. ns.Gold(-n) .. "|r" end
    return "|cff888888" .. ns.Gold(0) .. "|r"
end

local function badgeName(b) return T("badge_" .. b.key) end

local function badgeDesc(b)
    if b.key == "highroller" or b.key == "bigloss" then return T("badge_" .. b.key .. "_d", ns.Gold(b.arg)) end
    if b.key:match("^veteran") then return T("badge_veteran_d", b.arg) end
    return T("badge_" .. b.key .. "_d", b.arg)
end

local function badgeIcons(list, size)
    local out = {}
    for _, b in ipairs(list or {}) do out[#out + 1] = ("|T%s:%d:%d|t"):format(b.icon, size, size) end
    return table.concat(out, " ")
end

function UI.BadgeTooltip(owner, name, list)
    if not list or #list == 0 then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.Display(name))
    for _, b in ipairs(list) do
        GameTooltip:AddLine(("|T%s:16:16|t %s"):format(b.icon, badgeName(b)), 1, 0.82, 0)
        GameTooltip:AddLine("      " .. badgeDesc(b), 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
    UI.CzechTooltip()
end

local function BuildStats(p)
    local h = Loc(Label(p, "", "header"), "stats_mine")
    h:SetPoint("TOPLEFT", 2, -8)
    stp.period = Btn(p, "", 150, 24, function()
        ns.db.statsPeriod = nextOf(PERIODS, ns.db.statsPeriod)
        ns.RefreshUI()
    end)
    stp.period:SetPoint("TOPRIGHT", 0, -2)

    local keys = { "stats_games", "stats_wins", "stats_net", "stats_best" }
    stp.cards = {}
    local GAP = 6
    for i, key in ipairs(keys) do
        local card = Box(p)
        card:SetHeight(54)
        local l = Loc(Label(card, "", "label"), key)
        l:SetPoint("TOPLEFT", 12, -9)
        card.value = Label(card, "", "big")
        card.value:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -6)
        stp.cards[i] = card
    end
    -- karty rozdělí šířku panelu rovnoměrně
    local function layout()
        local w = (p:GetWidth() - GAP * 3) / 4
        for i, card in ipairs(stp.cards) do
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", p, "TOPLEFT", (i - 1) * (w + GAP), -34)
            card:SetWidth(w)
        end
    end
    p:SetScript("OnSizeChanged", layout)
    layout()

    stp.streak = Label(p, "", "label")
    stp.streak:SetPoint("TOPLEFT", 2, -96)
    -- moje odznaky; najetí myší ukáže popis
    stp.badges = CreateFrame("Frame", nil, p)
    stp.badges:SetPoint("TOPLEFT", 0, -110)
    stp.badges:SetPoint("RIGHT", p, "RIGHT")
    stp.badges:SetHeight(18)
    stp.badges.text = Label(stp.badges, "", "label")
    stp.badges.text:SetPoint("LEFT", 2, 0)
    stp.badges.text:SetPoint("RIGHT", -2, 0)
    stp.badges.text:SetJustifyH("LEFT")
    stp.badges.text:SetWordWrap(false)
    stp.badges:EnableMouse(true)
    stp.badges:SetScript("OnEnter", function(self) UI.BadgeTooltip(self, ns.Me(), self.list) end)
    stp.badges:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local lh = Loc(Label(p, "", "header"), "stats_board")
    lh:SetPoint("TOPLEFT", 2, -140)
    stp.sort = Btn(p, "", 150, 24, function()
        ns.db.statsSort = nextOf(SORTS, ns.db.statsSort)
        ns.RefreshUI()
    end)
    stp.sort:SetPoint("TOPRIGHT", 0, -134)

    stp.list = CreateList(p, 24)
    stp.list.frame:SetPoint("TOPLEFT", 0, -164)
    stp.list.frame:SetPoint("BOTTOMRIGHT", 0, 18)
    stp.note = Loc(Label(p, "", "label"), "stats_note")
    stp.note:SetPoint("BOTTOMLEFT", 2, 2)
end

local function RefreshStats()
    local period = ns.db.statsPeriod or "all"
    local since = (period ~= "all") and (time() - tonumber(period) * 86400) or nil
    local stats = ns.Ledger.Stats(since)
    local me = ns.Me()
    local mine = stats[me] or { games = 0, wins = 0, net = 0, best = 0, streak = 0, bestStreak = 0 }

    stp.period:SetText(T("stats_period_" .. period))
    stp.sort:SetText(T("stats_sort", T("stats_sort_" .. (ns.db.statsSort or "net"))))
    stp.cards[1].value:SetText(tostring(mine.games))
    local pct = mine.games > 0 and math.floor(mine.wins * 100 / mine.games + 0.5) or 0
    stp.cards[2].value:SetText(("%d |cff888888(%d %%)|r"):format(mine.wins, pct))
    stp.cards[3].value:SetText(signedGold(mine.net))
    stp.cards[4].value:SetText(ns.Gold(mine.best))
    stp.streak:SetText(T("stats_streak", mine.streak, mine.bestStreak))
    local badges = ns.Ledger.Badges(stats)
    local myBadges = badges[me]
    stp.badges.list = myBadges
    if myBadges then
        local parts = {}
        for _, b in ipairs(myBadges) do
            parts[#parts + 1] = ("|T%s:16:16|t %s"):format(b.icon, badgeName(b))
        end
        stp.badges.text:SetText(T("stats_badges") .. "  |cffffd100" .. table.concat(parts, "   ") .. "|r")
    else
        stp.badges.text:SetText(T("stats_no_badges"))
    end

    local items = {}
    for _, s in pairs(stats) do items[#items + 1] = s end
    local key = ns.db.statsSort or "net"
    table.sort(items, function(a, b)
        if a[key] ~= b[key] then return a[key] > b[key] end
        if a.net ~= b.net then return a.net > b.net end
        return a.name < b.name
    end)
    local colors = classColors()
    stp.list:SetItems(items, function(row, s, i)
        local medal = (i == 1 and "|cffffd100") or (i == 2 and "|cffc0c0c0") or (i == 3 and "|cffcd7f32") or "|cff888888"
        if s.name == me then
            row.hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.10)
            row.hl:Show()
            row.mark:Show()
        end
        local list = badges[s.name]
        row.text:SetText(("%s%d.|r  %s%s|r %s    %s     |cff888888%s|r"):format(
            medal, i, colors[s.name] or "|cffffffff", ns.Display(s.name), badgeIcons(list, 16), signedGold(s.net),
            T("stats_row", s.wins, s.games)))
        -- popis odznaků při najetí myší (řádky seznamu se používají znovu, proto vždy nastavit)
        row:EnableMouse(list ~= nil)
        row:SetScript("OnEnter", list and function(self) UI.BadgeTooltip(self, s.name, list) end or nil)
        row:SetScript("OnLeave", list and function() GameTooltip:Hide() end or nil)
    end, T("stats_empty"))
end

---------------------------------------------------------------------------
-- Záložka Nastavení
---------------------------------------------------------------------------
function UI.ToggleTestMode()
    local G = ns.Game
    if G.state and G.state.phase ~= "done" then
        ns.Print(T("test_finish_first"))
        return
    end
    G.testMode = not G.testMode
    ns.Print(T(G.testMode and "test_on" or "test_off"))
    UI.Show()
    ns.RefreshUI()
end

local function Header(p, key, y)
    local h = Loc(Label(p, "", "header"), key)
    h:SetPoint("TOPLEFT", 2, y)
    local line = p:CreateTexture(nil, "ARTWORK")
    line:SetPoint("LEFT", h, "RIGHT", 10, 0)
    line:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    line:SetHeight(1)
    SetColor(line, C.border)
    return h
end

local function BuildSettings(p)
    Header(p, "set_language", -6)
    sp.lang = {}
    local prev
    for _, lang in ipairs(ns.LANGS) do
        local b = Btn(p, ns.LANG_NAMES[lang], 130, 26, function() ns.SetLang(lang) end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 0, -28) end
        sp.lang[lang] = b
        prev = b
    end

    Header(p, "set_options", -74)
    sp.announce = Check(p, "set_announce", function(self) ns.db.announce = self:GetChecked() end)
    sp.announce:SetPoint("TOPLEFT", 2, -98)
    local hint = Loc(Label(p, "", "label"), "set_announce_hint")
    hint:SetPoint("TOPLEFT", 26, -118)
    sp.sound = Check(p, "set_sound", function(self) ns.db.sound = self:GetChecked() end)
    sp.sound:SetPoint("TOPLEFT", 2, -142)
    sp.autoOpen = Check(p, "set_autoopen", function(self) ns.db.autoOpen = self:GetChecked() end)
    sp.autoOpen:SetPoint("TOPLEFT", 2, -168)
    sp.minimap = Check(p, "set_minimap", function(self)
        ns.db.minimap = self:GetChecked()
        ns.UpdateMinimapButton()
    end)
    sp.minimap:SetPoint("TOPLEFT", 2, -194)
    sp.remind = Check(p, "set_remind", function(self) ns.db.remind = self:GetChecked() end)
    sp.remind:SetPoint("TOPLEFT", 2, -220)
    sp.font = Check(p, "set_font", function(self)
        ns.db.font = self:GetChecked()
        UI.ApplyFont()
        UpdateCheckHitRects()
    end)
    sp.font:SetPoint("TOPLEFT", 2, -246)

    Header(p, "set_tools", -282)
    sp.testMode = Btn(p, "", 214, 26, UI.ToggleTestMode)
    sp.testMode:SetPoint("TOPLEFT", 0, -304)
    sp.clearTest = Loc(Btn(p, "", 214, 26, function() ns.Ledger.ClearTest() end), "btn_clear_test")
    sp.clearTest:SetPoint("LEFT", sp.testMode, "RIGHT", 6, 0)
    sp.selftest = Loc(Btn(p, "", 214, 26, function() ns.SelfTest.Run() end), "btn_selftest")
    sp.selftest:SetPoint("TOPLEFT", 0, -336)
    sp.remindNow = Loc(Btn(p, "", 214, 26, function() ns.Ledger.Remind() end), "btn_remind")
    sp.remindNow:SetPoint("LEFT", sp.selftest, "RIGHT", 6, 0)
    sp.export = Loc(Btn(p, "", 214, 26, function() ns.Export.Run() end), "btn_export")
    sp.export:SetPoint("TOPLEFT", 0, -368)
    -- jen pro guild mastera: sebrat hry od celé guildy
    sp.collect = Loc(Btn(p, "", 214, 26, function() ns.Sync.RequestCollect() end), "btn_collect")
    sp.collect:SetPoint("LEFT", sp.export, "RIGHT", 6, 0)
    sp.collect:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(T("btn_collect"))
        GameTooltip:AddLine(T("collect_tip"), 1, 1, 1, true)
        GameTooltip:Show()
        UI.CzechTooltip()
    end)
    sp.collect:HookScript("OnLeave", function() GameTooltip:Hide() end)

    local cmds = Loc(Label(p, "", "label"), "set_commands")
    cmds:SetPoint("BOTTOMLEFT", 2, 22)
    cmds:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    sp.version = Label(p, "", "label")
    sp.version:SetPoint("BOTTOMLEFT", 2, 4)
end

local function RefreshSettings()
    local lang = ns.Lang()
    for l, b in pairs(sp.lang) do b:SetSelected(l == lang) end
    sp.announce:SetChecked(ns.db.announce)
    sp.sound:SetChecked(ns.db.sound)
    sp.autoOpen:SetChecked(ns.db.autoOpen)
    sp.minimap:SetChecked(ns.db.minimap)
    sp.remind:SetChecked(ns.db.remind)
    sp.font:SetChecked(ns.db.font)
    sp.testMode:SetText(T(ns.Game.testMode and "btn_testmode_off" or "btn_testmode_on"))
    sp.collect:SetShown(ns.Sync.IsGuildMaster())
    sp.version:SetText(T("set_version", version()))
end

---------------------------------------------------------------------------
-- Hlavní okno
---------------------------------------------------------------------------
local refreshers = { game = RefreshGame, debts = RefreshDebts, history = RefreshHistory, stats = RefreshStats,
    settings = RefreshSettings }

local function SelectTab(key)
    current = key
    for k, panel in pairs(panels) do panel:SetShown(k == key) end
    for k, tab in pairs(tabs) do tab:SetSelected(k == key) end
    refreshers[key]()
end

function UI.ApplyTexts()
    for _, t in ipairs(texts) do t[1]:SetText(T(t[2])) end
    UpdateCheckHitRects()
    if f and f:IsShown() then SelectTab(current) end
end

local function Build()
    f = Window("SUCDRFrame", 490, 560)
    f.title:SetText(ACCENT .. "SUCDR|r")
    f.subtitle:SetText(("v%s  -  Stand up Comedy death roll"):format(version()))

    local tabDefs = { { "game", "tab_game" }, { "debts", "tab_debts" }, { "history", "tab_history" },
        { "stats", "tab_stats" }, { "settings", "tab_settings" } }
    local prev
    for _, def in ipairs(tabDefs) do
        local key = def[1]
        local tab = Loc(Tab(f, 92, function() SelectTab(key) end), def[2])
        if prev then tab:SetPoint("LEFT", prev, "RIGHT", 2, 0) else tab:SetPoint("TOPLEFT", 10, -34) end
        tabs[key] = tab
        prev = tab

        local panel = CreateFrame("Frame", nil, f)
        panel:SetPoint("TOPLEFT", 14, -78)
        panel:SetPoint("BOTTOMRIGHT", -14, 14)
        panels[key] = panel
    end
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", 1, -64)
    sep:SetPoint("TOPRIGHT", -1, -64)
    sep:SetHeight(1)
    SetColor(sep, C.border)

    BuildGame(panels.game)
    BuildDebts(panels.debts)
    BuildHistory(panels.history)
    BuildStats(panels.stats)
    BuildSettings(panels.settings)
    UpdateCheckHitRects()

    local acc = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        if current ~= "game" then return end
        UpdateTimer()
        acc = acc + elapsed
        if acc >= 0.5 then
            acc = 0
            RefreshGame()
        end
    end)
    f:SetScript("OnShow", function() SelectTab(current) end)

    SelectTab(current)
end

function ns.RefreshUI()
    if f and f:IsShown() then refreshers[current]() end
end

function UI.Toggle()
    if not f then
        Build()
        return
    end
    f:SetShown(not f:IsShown())
end

function UI.Show()
    if not f then Build() else f:Show() end
end

function UI.ShowTab(key)
    UI.Show()
    SelectTab(key)
end

-- Otevře okno, v boji až po jeho skončení
local pendingShow = false
function UI.ShowSafe()
    if InCombatLockdown() then
        pendingShow = true
    else
        UI.Show()
    end
end
ns.On("PLAYER_REGEN_ENABLED", function()
    if pendingShow then
        pendingShow = false
        UI.Show()
    end
end)

-- Kliknutí v přehledu addonů (tlačítko vedle minimapy)
function SUCDR_OnAddonCompartmentClick()
    UI.Toggle()
end

SLASH_SUCDR1 = "/sucdr"
SlashCmdList.SUCDR = function(input)
    local cmd, arg = (input or ""):match("^(%S*)%s*(.-)%s*$")
    cmd, arg = cmd:lower(), arg:lower()
    if cmd == "test" then
        if arg == "clear" then
            ns.Ledger.ClearTest()
        else
            UI.ToggleTestMode()
        end
    elseif cmd == "join" then
        ns.Game.Join()
        UI.Show()
    elseif cmd == "log" then
        UI.ShowLastLog()
    elseif cmd == "roll" then
        ns.Game.Roll()
    elseif cmd == "sync" then
        ns.Ledger.RequestSync()
    elseif cmd == "selftest" then
        ns.SelfTest.Run()
    elseif cmd == "stats" then
        UI.ShowTab("stats")
    elseif cmd == "remind" then
        ns.Ledger.Remind()
    elseif cmd == "version" or cmd == "ver" then
        ns.Version.Print()
    elseif cmd == "export" then
        ns.Export.Run()
    elseif cmd == "collect" then
        ns.Sync.RequestCollect()
    elseif cmd == "minimap" then
        ns.ResetMinimapButton()
    elseif cmd == "lang" then
        if ns.Locales[arg] then ns.SetLang(arg) else ns.Print("/sucdr lang cs | en") end
    elseif cmd == "help" then
        for _, line in ipairs(T("help")) do ns.Print(line) end
    else
        UI.Toggle()
    end
end
