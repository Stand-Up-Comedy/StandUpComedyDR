-- SUCDR - záložka Loterie
-- Guild master: formulář nové loterie, nebo přehled běžící (platby, uzavření, losování).
-- Ostatní: aktuální výhra a vlastní losy (bez procent a bonusů).
local _, ns = ...
local T = ns.T
local UI = ns.UI
local K = UI.kit

local lp = {}
local FIELDS = { "price", "limit", "step", "bonus", "bonusMax", "share" }
local LABELS = { price = "lot_price", limit = "lot_limit", step = "lot_step", bonus = "lot_bonus",
    bonusMax = "lot_bonus_max", share = "lot_share" }

local function confirm(text, fn)
    UI.Confirm(text, { { T("lot_yes"), fn, true }, { T("lot_no") } })
end

local function readForm()
    local o = { guests = lp.guests:GetChecked() and true or false }
    for _, k in ipairs(FIELDS) do o[k] = math.floor(tonumber(lp.edit[k]:GetText()) or 0) end
    return o
end

local function build(p)
    local Lot = ns.Lottery

    lp.box = K.Box(p)
    lp.box:SetPoint("TOPLEFT", 0, 0)
    lp.box:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    lp.box:SetHeight(86)
    lp.status = K.Label(lp.box, "", "text")
    lp.status:SetPoint("TOPLEFT", 14, -9)
    lp.status:SetPoint("RIGHT", lp.box, "RIGHT", -10, 0)
    lp.status:SetJustifyV("TOP")
    lp.status:SetSpacing(3)

    -- formulář nové loterie
    lp.form = CreateFrame("Frame", nil, p)
    lp.form:SetPoint("TOPLEFT", 0, -96)
    lp.form:SetPoint("BOTTOMRIGHT", 0, 0)
    local title = K.Loc(K.Label(lp.form, "", "header"), "lot_form_title")
    title:SetPoint("TOPLEFT", 2, -4)
    lp.edit = {}
    for i, k in ipairs(FIELDS) do
        local label = K.Loc(K.Label(lp.form, "", "label"), LABELS[k])
        label:SetPoint("TOPLEFT", 2, -8 - i * 30)
        local e = K.Edit(lp.form, 110)
        e:SetPoint("TOPLEFT", 170, -3 - i * 30)
        lp.edit[k] = e
    end
    lp.guests = K.Check(lp.form, "lot_guests", function() end)
    lp.guests:SetPoint("TOPLEFT", 2, -220)
    lp.create = K.Loc(K.Btn(lp.form, "", 214, 28, function()
        local o = readForm()
        local err = Lot.Validate(o)
        if err then
            ns.Print(T(err))
            return
        end
        confirm(T("lot_confirm_create", ns.Gold(o.price), o.limit), function() Lot.Create(o) end)
    end, true), "lot_create")
    lp.create:SetPoint("TOPLEFT", 0, -252)
    lp.back = K.Loc(K.Btn(lp.form, "", 120, 28, function()
        lp.showForm = false
        ns.RefreshUI()
    end), "btn_back")
    lp.back:SetPoint("LEFT", lp.create, "RIGHT", 6, 0)

    -- ovládání běžící loterie
    local W, GAP = 150, 6
    local function button(key, col, row, fn, primary)
        local b = K.Loc(K.Btn(p, "", W, 26, fn, primary), key)
        b:SetPoint("TOPLEFT", col * (W + GAP), -96 - row * 32)
        return b
    end
    lp.close = button("lot_close", 0, 0, function() confirm(T("lot_confirm_close"), Lot.Close) end, true)
    lp.draw = button("lot_draw", 1, 0, function() Lot.Draw() end, true)
    lp.cancel = button("lot_cancel", 2, 0, function() confirm(T("lot_confirm_cancel"), Lot.Cancel) end)
    lp.publish = button("lot_publish", 0, 1, function() Lot.PublishList() end)
    lp.report = button("lot_report", 1, 1, function() UI.ShowLog(T("lot_report"), Lot.Report()) end)
    lp.save = button("lot_save", 2, 1, function() confirm(T("lot_confirm_save"), function() ReloadUI() end) end)
    lp.newBtn = button("lot_new", 0, 2, function()
        lp.showForm = true
        ns.RefreshUI()
    end)
    lp.buttons = { lp.close, lp.draw, lp.cancel, lp.publish, lp.report, lp.save, lp.newBtn }

    lp.list = K.CreateList(p, 24)
    lp.list.frame:SetPoint("TOPLEFT", 0, -196)
    lp.list.frame:SetPoint("BOTTOMRIGHT", 0, 0)
end

local function rows(l)
    local Lot = ns.Lottery
    local items = {}
    for i, p in ipairs(l.pending) do
        items[#items + 1] = { text = T("lot_row_pending", ns.Display(p.name), ns.Gold(p.gold)), btn = "lot_resolve",
            click = function() Lot.AskPending(i) end }
    end
    if Lot.PrizeLeft() > 0 then
        items[#items + 1] = { text = T("lot_row_payout", ns.Display(l.winner), ns.Gold(Lot.PrizeLeft())),
            btn = "lot_mark_paid", click = function() confirm(T("lot_confirm_manual"), Lot.MarkPaidOut) end }
    end
    local back = {}
    for name in pairs(l.back) do back[#back + 1] = name end
    table.sort(back)
    for _, name in ipairs(back) do
        items[#items + 1] = { text = T("lot_row_back", ns.Display(name), ns.Gold(l.back[name])), btn = "lot_done_btn",
            click = function() confirm(T("lot_confirm_manual"), function() Lot.MarkReturned(name) end) end }
    end
    for _, name in ipairs(Lot.Buyers()) do
        items[#items + 1] = { text = T("lot_row_buyer", ns.Display(name), Lot.Ranges(name), Lot.CountOf(name)) }
    end
    return items
end

local function playerText(seen)
    if not seen then return T("lot_none") end
    local text = T("lot_player_status", T("lot_st_" .. seen.status), ns.Gold(seen.prize), ns.Gold(seen.price),
        seen.limit, ns.Display(seen.host))
    if seen.winner and seen.number then
        text = text .. "\n" .. T("lot_player_winner", ns.Display(seen.winner), seen.number)
    end
    return text
end

local function refresh()
    local Lot = ns.Lottery
    local gm = ns.Sync.IsGuildMaster()
    local l = ns.db.lottery
    local own = gm and l and l.host == ns.Me()
    if not Lot.Busy() and gm and not own then lp.showForm = true end
    if Lot.Busy() then lp.showForm = false end
    local form = gm and lp.showForm

    for _, b in ipairs(lp.buttons) do b:SetShown(own and not form or false) end
    lp.form:SetShown(form and true or false)
    lp.list.frame:SetShown(not form)

    if form then
        lp.back:SetShown(own and true or false)
        if not lp.formFilled then
            lp.formFilled = true
            local d = ns.db.lotteryDefaults or Lot.DEFAULTS
            for _, k in ipairs(FIELDS) do lp.edit[k]:SetText(tostring(d[k])) end
            lp.guests:SetChecked(d.guests)
        end
        lp.status:SetText(T("lot_none"))
        return
    end
    lp.formFilled = false

    if own then
        local sales, bonus, prize, bank, toNext = Lot.Money(l)
        local text = T("lot_gm_status", T("lot_st_" .. l.status), ns.Gold(prize), l.count, ns.Gold(sales),
            ns.Gold(bank), ns.Gold(bonus))
        if l.status == "open" and toNext then text = text .. "\n" .. T("lot_to_next", ns.Gold(toNext)) end
        if l.winner then text = text .. "\n" .. T("lot_player_winner", ns.Display(l.winner), l.number) end
        lp.status:SetText(text)
        lp.close:SetEnabled(l.status == "open")
        lp.draw:SetEnabled(l.status == "closed")
        lp.cancel:SetEnabled(l.status == "open" or l.status == "closed")
        lp.publish:SetEnabled(l.count > 0)
        lp.newBtn:SetEnabled(not Lot.Busy())
        lp.list:SetItems(rows(l), function(row, item)
            row.text:SetText(item.text)
            if item.btn then
                row.button:SetText(T(item.btn))
                row.button:SetScript("OnClick", item.click)
                row.button:Show()
            end
        end, T("lot_empty"))
    else
        local seen = ns.db.lotterySeen
        lp.status:SetText(playerText(seen))
        local items = {}
        if seen then
            items[1] = seen.mine and T("lot_my", (seen.mine:gsub(",", ", "))) or T("lot_my_none")
        end
        lp.list:SetItems(items, function(row, item) row.text:SetText(item) end, "")
    end
end

UI.lottery = { build = build, refresh = refresh }
