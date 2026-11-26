-- SUCDR - komunikace mezi addony (skryté addon zprávy)
-- Formát rámce: "<mid>:<část>:<počet>:<data>", data = "TYP;payload"
local _, ns = ...

local PREFIX = ns.PREFIX
local MAX_PART = 230

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

local queue = {}
local tokens, MAX_TOKENS = 6, 6 -- Blizzard omezuje počet zpráv, posíláme cca 1/s
local nextMid = 0
local receivers = {}
local buffers = {}

function ns.OnComm(msgType, fn)
    receivers[msgType] = fn
end

-- Rozdělí text na části, nikdy uprostřed UTF-8 znaku
local function split(text)
    local parts, i, len = {}, 1, #text
    while i <= len do
        local j = math.min(i + MAX_PART - 1, len)
        while j < len and j > i do
            local b = text:byte(j + 1)
            if b < 0x80 or b >= 0xC0 then break end
            j = j - 1
        end
        parts[#parts + 1] = text:sub(i, j)
        i = j + 1
    end
    if #parts == 0 then parts[1] = "" end
    return parts
end

-- pro /sucdr selftest
ns.CommSplit = split
ns.CommMaxPart = MAX_PART

-- key: zprávy se stejným klíčem čekající ve frontě se nahradí novější (např. stav hry)
function ns.Send(msgType, payload, channel, target, key)
    if not channel then return end
    nextMid = (nextMid % 999) + 1
    local item = {
        parts = split(msgType .. ";" .. (payload or "")),
        idx = 1, mid = nextMid, channel = channel, target = target, key = key,
    }
    if key then
        for i, q in ipairs(queue) do
            if q.key == key and q.idx == 1 then
                queue[i] = item
                return
            end
        end
    end
    queue[#queue + 1] = item
end

function ns.SendGroup(msgType, payload, key)
    ns.Send(msgType, payload, ns.GroupChannel(), nil, key)
end

function ns.SendGuild(msgType, payload)
    if IsInGuild() then ns.Send(msgType, payload, "GUILD") end
end

-- Výsledek: "ok", "throttle" (zkusit znovu, až se uvolní limit) nebo "error"
local function sendRaw(text, channel, target)
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, channel, target)
    if not ok then return "error" end
    -- starší klient vrací true/false, novější Enum.SendAddonMessageResult
    if res == nil or res == true or res == 0 then return "ok" end
    if res == false then return "error" end
    local R = Enum.SendAddonMessageResult
    if R and (res == R.Success) then return "ok" end
    if R and (res == R.AddonMessageThrottle or res == R.ChannelThrottle) then return "throttle" end
    return "error"
end

local MAX_RETRY = 5

local function pump()
    while tokens >= 1 and queue[1] do
        local item = queue[1]
        local n = #item.parts
        local text = item.mid .. ":" .. item.idx .. ":" .. n .. ":" .. item.parts[item.idx]
        local r = sendRaw(text, item.channel, item.target)
        if r == "throttle" then
            tokens = 0
            return
        end
        tokens = tokens - 1
        if r == "error" then
            -- např. dočasné zablokování addon zpráv; pár pokusů, pak zahodit
            item.tries = (item.tries or 0) + 1
            if item.tries >= MAX_RETRY then
                table.remove(queue, 1)
            else
                tokens = 0 -- další pokus nejdřív za ~1 s
                return
            end
        else
            item.idx = item.idx + 1
            if item.idx > n then table.remove(queue, 1) end
        end
    end
end

-- Nedokončené vícedílné zprávy (část se ztratila) po minutě zahodíme
local BUFFER_TTL = 60
local ticks = 0
local function cleanBuffers()
    local now = GetTime()
    for key, buf in pairs(buffers) do
        if now - buf.t > BUFFER_TTL then buffers[key] = nil end
    end
end

C_Timer.NewTicker(0.25, function()
    tokens = math.min(MAX_TOKENS, tokens + 0.25)
    pump()
    ticks = ticks + 1
    if ticks >= 120 then
        ticks = 0
        cleanBuffers()
    end
end)

ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= PREFIX then return end
    if ns.IsSecret(text, sender) then return end
    sender = ns.Normalize(sender)
    if not sender then return end
    -- vlastní zprávy ignorujeme, kromě šeptání sám sobě (/sucdr selftest)
    local fromSelf = (sender == ns.Me())
    if fromSelf and channel ~= "WHISPER" then return end

    local mid, i, n, data = text:match("^(%d+):(%d+):(%d+):(.*)$")
    if not mid then return end
    i, n = tonumber(i), tonumber(n)
    if n < 1 or n > 100 or i < 1 or i > n then return end

    local payload
    if n == 1 then
        payload = data
    else
        local key = sender .. "#" .. mid
        local buf = buffers[key]
        if i == 1 or not buf then
            buf = { parts = {} }
            buffers[key] = buf
        end
        buf.t = GetTime()
        buf.parts[i] = data
        for k = 1, n do
            if not buf.parts[k] then return end
        end
        payload = table.concat(buf.parts, "", 1, n)
        buffers[key] = nil
    end

    local msgType, rest = payload:match("^([^;]+);?(.*)$")
    if fromSelf and msgType ~= "SELFTEST" then return end
    local fn = msgType and receivers[msgType]
    if fn then fn(sender, rest, channel) end
end)
