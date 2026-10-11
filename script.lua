--[[
    ╔══════════════════════════════════════════════════════════════════════╗
    ║                    JEWSKI CODE SNIPER                                ║
    ║        Worker: https://solver.jimmykabobman.workers.dev              ║
    ║        UI:     Skibidi UI  (purple + white)                          ║
    ╚══════════════════════════════════════════════════════════════════════╝
]]

-- =========================================================================
-- Compat / environment
-- =========================================================================

local cloneref        = cloneref or function(x) return x end
local getgenv         = getgenv or function() return _G end
local getconnections  = getconnections
local gethui          = gethui
local getupvalues     = (debug and debug.getupvalues) or getupvalues
local setupvalue      = (debug and debug.setupvalue) or setupvalue

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = cloneref(game:GetService("TweenService"))
local UserInputService  = cloneref(game:GetService("UserInputService"))
local HttpService       = game:GetService("HttpService")
local LocalPlayer       = Players.LocalPlayer

local print, next, pcall, tostring, type, pairs, ipairs
    = print, next, pcall, tostring, type, pairs, ipairs
local table_remove  = table.remove
local table_concat  = table.concat
local table_pack    = table.pack or function(...)
    return { n = select("#", ...), ... }
end
local table_unpack  = table.unpack
local string_sub    = string.sub
local string_gsub   = string.gsub
local string_format = string.format
local math_floor    = math.floor
local math_random   = math.random
local math_min      = math.min
local os_clock      = os.clock
local os_date       = os.date
local tick          = tick
local task_wait     = (task and task.wait) or wait
local task_spawn    = (task and task.spawn) or spawn
local task_delay    = (task and task.delay) or function(t, f)
    task_spawn(function() task_wait(t) f() end)
end

-- =========================================================================
-- Text hygiene
-- =========================================================================

local function stripAllWhitespace(s)
    if type(s) ~= "string" then return "" end
    s = s:gsub("[\194\160\226\128\139]", "")
    s = s:gsub("%s", "")
    return s
end

local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- =========================================================================
-- CONFIG
-- =========================================================================

local Config = {
    Enabled        = true,
    AutoTypeCodes  = true,
    AutoSubmit     = true,
    AIRiddles      = true,
    AIAutoSubmit   = true,
    SubmitAfter    = 4,
    MinFragment    = 1,
    MaxFragWords   = 60,
    ForceOpenCodes = true,

    Debug          = true,
    DebugToUI      = true,
    DebugToConsole = true,
    DebugMaxLines  = 200,
}

local State = {
    typedCount   = 0,
    buffer       = {},
    solvedCount  = 0,
    lastSeen     = nil,
    lastSeenAt   = 0,
    unloaded     = false,
    connections  = {},
}

-- =========================================================================
-- RIDDLE WORKER CLIENT
-- =========================================================================

local RiddleWorker = (function()
    local WORKER_URL    = "https://solver.jimmykabobman.workers.dev"
    local SHARED_SECRET = "a3f9c2d1e847b6510f9e2c3a5d781b49c6e2f0a8d4b7e1359c2a6f8e0d2b4a71"

    local function getRequestFn()
        if syn and syn.request then return syn.request end
        if http and http.request then return http.request end
        if request then return request end
        if http_request then return http_request end
        return nil
    end
    local requestFn = getRequestFn()

    local K = {
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
    }
    local band, bxor, bnot = bit32.band, bit32.bxor, bit32.bnot
    local rrotate, rshift = bit32.rrotate, bit32.rshift

    local function sha256(str)
        local bitlen = #str * 8
        local hi = math.floor(bitlen / 4294967296)
        local lo = bitlen % 4294967296
        local padded = str .. "\128" .. string.rep("\0", (55 - #str) % 64)
            .. string.pack(">I4", hi) .. string.pack(">I4", lo)
        local H = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
                   0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
        for i = 1, #padded, 64 do
            local w = {}
            for j = 0, 15 do w[j+1] = string.unpack(">I4", padded, i + j*4) end
            for j = 17, 64 do
                local s0, s1 = w[j-15], w[j-2]
                w[j] = (w[j-16] + bxor(rrotate(s0,7),rrotate(s0,18),rshift(s0,3))
                      + w[j-7] + bxor(rrotate(s1,17),rrotate(s1,19),rshift(s1,10))) % 4294967296
            end
            local a,b,c,d,e,f,g,h = table.unpack(H)
            for j = 1, 64 do
                local S1 = bxor(rrotate(e,6),rrotate(e,11),rrotate(e,25))
                local ch = bxor(band(e,f),band(bnot(e),g))
                local t1 = (h + S1 + ch + K[j] + w[j]) % 4294967296
                local S0 = bxor(rrotate(a,2),rrotate(a,13),rrotate(a,22))
                local mj = bxor(band(a,b),band(a,c),band(b,c))
                local t2 = (S0 + mj) % 4294967296
                h,g,f,e,d,c,b,a = g,f,e,(d+t1)%4294967296,c,b,a,(t1+t2)%4294967296
            end
            H[1]=(H[1]+a)%4294967296; H[2]=(H[2]+b)%4294967296
            H[3]=(H[3]+c)%4294967296; H[4]=(H[4]+d)%4294967296
            H[5]=(H[5]+e)%4294967296; H[6]=(H[6]+f)%4294967296
            H[7]=(H[7]+g)%4294967296; H[8]=(H[8]+h)%4294967296
        end
        local out = {}
        for i = 1, 8 do out[i] = string.format("%08x", H[i]) end
        return table.concat(out)
    end

    local function hexToStr(hex)
        return (hex:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end))
    end

    local function hmacSha256(key, data)
        if #key > 64 then key = hexToStr(sha256(key)) end
        local k = key .. string.rep("\0", 64 - #key)
        local ipad, opad = {}, {}
        for i = 1, 64 do
            local b = k:byte(i)
            ipad[i] = string.char(bxor(b, 0x5c))
            opad[i] = string.char(bxor(b, 0x36))
        end
        return sha256(table.concat(ipad) .. hexToStr(sha256(table.concat(opad) .. data)))
    end

    local function decrypt(secret, nonce, hexData)
        if type(hexData) ~= "string" or hexData == "" then return nil end
        hexData = hexData:gsub("[^%x]", "")
        if #hexData % 2 ~= 0 then return nil end
        local out = {}
        local totalBytes = #hexData // 2
        for i = 0, totalBytes - 1, 32 do
            local ks = hmacSha256(secret, nonce .. ":" .. tostring(i // 32))
            for j = 0, 31 do
                local idx = i + j
                if idx >= totalBytes then break end
                local ct = tonumber(hexData:sub(idx*2+1, idx*2+2), 16)
                local kt = tonumber(ks:sub(j*2+1, j*2+2), 16)
                out[#out+1] = string.char(bxor(ct, kt))
            end
        end
        return table.concat(out)
    end

    local api = {}
    api.ready = (WORKER_URL ~= "" and #SHARED_SECRET == 64 and requestFn ~= nil)
    api.url    = WORKER_URL

    function api.solve(riddle)
        if not api.ready then return nil, "worker not configured" end
        if type(riddle) ~= "string" or riddle == "" then
            return nil, "empty riddle"
        end

        local t = {}
        for i = 1, 8 do t[#t+1] = string.format("%02x", math_random(0, 255)) end
        local nonce = table_concat(t)

        local ok, res = pcall(requestFn, {
            Url     = WORKER_URL .. "/solve",
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpService:JSONEncode({ riddle = riddle, nonce = nonce }),
        })

        if not ok or type(res) ~= "table" then
            return nil, "request failed"
        end

        local status = tonumber(res.StatusCode or res.Status or res.status_code) or 0
        if status ~= 200 then
            return nil, "http " .. tostring(status)
        end

        local body = res.Body or res.body
        if type(body) ~= "string" then return nil, "no body" end

        local plain = decrypt(SHARED_SECRET, nonce, body)
        if not plain then return nil, "decrypt failed" end

        local ok2, decoded = pcall(function() return HttpService:JSONDecode(plain) end)
        if not ok2 or type(decoded) ~= "table" then
            return nil, "bad json"
        end

        local answer = stripAllWhitespace(tostring(decoded.answer or ""))
        return answer, decoded.source or "?"
    end

    return api
end)()

-- =========================================================================
-- Debug logger
-- =========================================================================

local Debug = (function()
    local lines = {}
    local uiAppend = nil

    local function stamp()
        return os_date("%H:%M:%S")
    end

    local function push(level, msg)
        if not Config.Debug then return end
        local line = string_format("[%s] %s %s", stamp(), level, msg)
        lines[#lines + 1] = line
        while #lines > Config.DebugMaxLines do table_remove(lines, 1) end

        if Config.DebugToConsole then print(line) end
        if Config.DebugToUI and uiAppend then pcall(uiAppend, line) end
    end

    local api = {}
    api.log   = function(msg) push("INFO ", tostring(msg)) end
    api.warn  = function(msg) push("WARN ", tostring(msg)) end
    api.error = function(msg) push("ERROR", tostring(msg)) end
    api.attachUI = function(fn) uiAppend = fn end
    api.lines    = function() return lines end
    api.clear    = function() lines = {} end
    return api
end)()

local function try(label, fn, ...)
    local results = table_pack(xpcall(function(...)
        return fn(...)
    end, function(e)
        return tostring(e) .. "\n" .. debug.traceback("", 2)
    end, ...))

    local ok = results[1]
    if not ok then
        Debug.error(label .. " failed: " .. tostring(results[2]))
        return nil, results[2]
    end
    if results.n == 1 then return true end
    if results.n == 2 then return results[2] end
    return table_unpack(results, 2, results.n)
end

-- =========================================================================
-- Text helpers
-- =========================================================================

local IGNORE_EXPIRED = {
    "expired", "doesn't exist", "does not exist",
    "wrong", "incorrect", "no longer", "invalid",
}
local IGNORE_REDEEMED = { "redeemed", "claimed", "already" }

local function containsAny(s, list)
    for _, w in ipairs(list) do
        if s:find(w, 1, true) then return true end
    end
    return false
end

local function cleanText(s)
    return (s:gsub("@@%u+@@%d+@@", ""):gsub("@@[%w]+@@", ""):gsub("@@", ""))
end

-- =========================================================================
-- Riddle detection
-- =========================================================================

local RIDDLE_STARTERS = {
    "what", "whats", "who", "whos", "when", "where", "which",
    "how", "name", "tell", "type", "say", "guess", "answer",
    "riddle", "spell", "solve",
}

local function looksLikeRiddle(text)
    if type(text) ~= "string" then return false end
    local t = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if t == "" then return false end

    if t:find("?", 1, true) then return true end

    local firstWord = t:match("^(%a+)")
    if firstWord then
        for _, s in ipairs(RIDDLE_STARTERS) do
            if firstWord == s then return true end
        end
    end

    local hasAnd  = t:find("%f[%a]and%f[%A]") ~= nil
    local hasPlus = t:find("plus", 1, true) ~= nil or t:find("+", 1, true) ~= nil
    if (hasAnd or hasPlus) and t:find("%s") then return true end

    if t:find("%f[%a]my%f[%A]") and t:find("%f[%a]and%f[%A]") then
        return true
    end

    if t:find("favorite", 1, true) or t:find("favourite", 1, true) then
        return true
    end

    return false
end

-- =========================================================================
-- Fragment extraction
-- =========================================================================

local FRAGMENT_BLACKLIST = {
    ["top"] = true,
}

local function isBlacklisted(tok)
    return FRAGMENT_BLACKLIST[tok:lower()] == true
end

local function extractFragment(raw)
    if type(raw) ~= "string" then return nil end

    local cleaned = raw:gsub("<[^>]->", " ")
    cleaned = cleaned:gsub("%s+", " ")
    cleaned = cleaned:gsub("^%s*(.-)%s*$", "%1")
    if cleaned == "" then return nil end

    for tok in cleaned:gmatch("%S+") do
        local bare = tok:gsub("[%p]+$", ""):gsub("^[%p]+", "")
        if bare ~= "" and bare:match("^[%w]+$") and not isBlacklisted(bare) then
            return bare
        end
    end
    return nil
end

-- =========================================================================
-- Own-UI / visibility
-- =========================================================================

local OWN_GUI_NAME = "JewskiCodeSniper"

local function isOwnUI(inst)
    local node = inst
    for _ = 1, 10 do
        if not node then break end
        if node.Name == OWN_GUI_NAME
           or node.Name == "SkibidiNotifs"
           or node.Name == "SkibidiTooltip" then
            return true
        end
        node = node.Parent
    end
    return false
end

local function isVisibleChain(inst)
    local node = inst
    while node do
        if node:IsA("GuiObject") and not node.Visible then return false end
        if node:IsA("ScreenGui") then return node.Enabled end
        node = node.Parent
    end
    return true
end

-- =========================================================================
-- Force-open Codes GUI
-- =========================================================================

local function forceOpenCodes()
    if not Config.ForceOpenCodes then return end
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then return end

    local codes = pg:FindFirstChild("Codes")
    if not codes then return end

    if codes:IsA("ScreenGui") then
        pcall(function() codes.Enabled = true end)
    end

    local codes2 = codes:FindFirstChild("Codes") or codes
    if codes2:IsA("GuiObject") then
        pcall(function() codes2.Visible = true end)
    end

    local node = codes2
    while node and node ~= codes do
        if node:IsA("GuiObject") then
            pcall(function() node.Visible = true end)
        end
        node = node.Parent
    end

    node = codes.Parent
    while node do
        if node:IsA("GuiObject") then
            pcall(function() node.Visible = true end)
        end
        if node:IsA("ScreenGui") then
            pcall(function() node.Enabled = true end)
        end
        node = node.Parent
    end
end

-- =========================================================================
-- findCodeBox
-- =========================================================================

local function findCodeBox()
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then
        Debug.warn("no PlayerGui")
        return nil
    end

    pcall(forceOpenCodes)

    local codes = pg:FindFirstChild("Codes")
    if codes then
        if codes:IsA("ScreenGui") then
            pcall(function() codes.Enabled = true end)
        end

        local codes2 = codes:FindFirstChild("Codes") or codes
        if codes2:IsA("GuiObject") then
            pcall(function() codes2.Visible = true end)
        end

        local parent = codes2
        while parent and parent ~= codes do
            if parent:IsA("GuiObject") then
                pcall(function() parent.Visible = true end)
            end
            parent = parent.Parent
        end

        for _, descendant in ipairs(codes2:GetDescendants()) do
            if descendant:IsA("TextBox") and not isOwnUI(descendant) then
                Debug.log("CodeBox (Codes subtree): " .. descendant:GetFullName())
                return descendant
            end
        end
        Debug.warn("Codes subtree present but no TextBox — falling through")
    else
        Debug.log("Codes subtree not found — dynamic scan")
    end

    local deadline = tick() + 2

    while tick() < deadline do
        local candidates = {}
        for _, child in ipairs(pg:GetChildren()) do
            if child:IsA("ScreenGui") and child.Enabled and not isOwnUI(child) then
                for _, d in ipairs(child:GetDescendants()) do
                    if d:IsA("TextBox") and not isOwnUI(d) then
                        candidates[#candidates + 1] = d
                    end
                end
            end
        end

        for _, tb in ipairs(candidates) do
            if isVisibleChain(tb) then
                local n = tb.Name:lower()
                local p = (tb.Parent and tb.Parent.Name or ""):lower()
                if n:find("code") or p:find("code")
                   or n:find("redeem") or p:find("redeem")
                   or n:find("input") or p:find("textbox")
                   or n:find("enter") then
                    Debug.log("CodeBox (dynamic preferred): " .. tb:GetFullName())
                    return tb
                end
            end
        end

        for _, tb in ipairs(candidates) do
            if isVisibleChain(tb) then
                Debug.log("CodeBox (dynamic fallback): " .. tb:GetFullName())
                return tb
            end
        end

        pcall(forceOpenCodes)
        task_wait(0.1)
    end

    Debug.warn("no codebox visible after 2s poll")
    return nil
end

-- =========================================================================
-- findConfirmButton
-- =========================================================================

local SUBMIT_VERBS = {
    "submit", "redeem", "claim", "confirm", "enter",
    "send", "apply", "ok", "use", "go", "check", "go!", "play",
}

local function matchesVerb(str)
    for _, v in ipairs(SUBMIT_VERBS) do
        if str:find(v, 1, true) then return true end
    end
    return false
end

local function findConfirmButton(box)
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end

    local codes = pg:FindFirstChild("Codes")
    if codes then
        local codes2 = codes:FindFirstChild("Codes") or codes
        for _, descendant in ipairs(codes2:GetDescendants()) do
            if (descendant:IsA("TextButton") or descendant:IsA("ImageButton"))
               and not isOwnUI(descendant) then
                local n = descendant.Name:lower()
                local t = ""
                pcall(function() t = tostring(descendant.Text or ""):lower() end)
                if matchesVerb(n) or matchesVerb(t) then
                    return descendant
                end
            end
        end

        for _, descendant in ipairs(codes2:GetDescendants()) do
            if (descendant:IsA("TextButton") or descendant:IsA("ImageButton"))
               and not isOwnUI(descendant) then
                local n = descendant.Name:lower()
                if not n:find("close") and not n:find("toggle") and n ~= "x" then
                    return descendant
                end
            end
        end
    end

    if box then
        local parent = box.Parent
        for _ = 1, 8 do
            if not parent then break end
            for _, d in ipairs(parent:GetDescendants()) do
                if (d:IsA("TextButton") or d:IsA("ImageButton"))
                   and d ~= box and not isOwnUI(d) then
                    local n = d.Name:lower()
                    local t = ""
                    pcall(function() t = tostring(d.Text or ""):lower() end)
                    if matchesVerb(n) or matchesVerb(t) then return d end
                end
            end
            parent = parent.Parent
        end
    end

    return nil
end

-- =========================================================================
-- fireButton
-- =========================================================================

local function fireButton(btn)
    if not btn then return false end

    local attempts = {
        function() btn.MouseButton1Click:Fire() end,
        function() btn.Activated:Fire() end,
    }

    if type(firesignal) == "function" then
        attempts[#attempts + 1] = function() firesignal(btn.MouseButton1Click) end
        attempts[#attempts + 1] = function() firesignal(btn.Activated) end
    end

    if type(getconnections) == "function" then
        attempts[#attempts + 1] = function()
            local ok, conns = pcall(getconnections, btn.MouseButton1Click)
            if ok and type(conns) == "table" then
                for _, c in ipairs(conns) do pcall(function() c:Fire() end) end
            end
            local ok2, conns2 = pcall(getconnections, btn.Activated)
            if ok2 and type(conns2) == "table" then
                for _, c in ipairs(conns2) do pcall(function() c:Fire() end) end
            end
        end
    end

    if type(fireclick) == "function" then
        attempts[#attempts + 1] = function() fireclick(btn) end
    end

    local fired = false
    for _, fn in ipairs(attempts) do
        local ok = pcall(fn)
        fired = fired or ok
    end
    return fired
end

-- =========================================================================
-- fireFocusLost
-- =========================================================================

local function fireFocusLost(box)
    if not box then return false end
    local fired = false

    if type(firesignal) == "function" then
        fired = pcall(firesignal, box.FocusLost, true) or fired
    end

    if type(getconnections) == "function" then
        local ok, conns = pcall(getconnections, box.FocusLost)
        if ok and type(conns) == "table" then
            for _, c in ipairs(conns) do
                local fn = nil
                pcall(function() fn = c.Function end)

                if fn and type(getupvalues) == "function"
                   and type(setupvalue) == "function" then
                    local ok2, ups = pcall(getupvalues, fn)
                    if ok2 and type(ups) == "table" then
                        for k, v in pairs(ups) do
                            if type(v) == "boolean" and v == true then
                                pcall(setupvalue, fn, k, false)
                            end
                        end
                    end
                end

                local ok3 = pcall(function()
                    if c.Enabled ~= false then c:Fire(true) end
                end)
                fired = fired or ok3
            end
        end
    end

    return fired
end

-- =========================================================================
-- submitCode
-- =========================================================================

local function submitCode(text)
    if type(text) ~= "string" or text == "" then
        return false, "empty text"
    end

    text = stripAllWhitespace(text)
    if text == "" then
        return false, "empty after whitespace strip"
    end

    local box = findCodeBox()
    if not box then
        task_wait(0.25)
        pcall(forceOpenCodes)
        box = findCodeBox()
    end
    if not box then
        return false, "no codebox visible"
    end

    pcall(function() box:CaptureFocus() end)
    task_wait(0.02)

    pcall(function() box.Text = "" end)
    task_wait(0.02)
    local okSet = pcall(function() box.Text = text end)
    if not okSet then
        return false, "text set failed"
    end

    local actual = ""
    pcall(function() actual = box.Text end)
    actual = stripAllWhitespace(actual)
    if actual ~= text then
        Debug.warn(string_format("box.Text mismatch: wanted [%s] got [%s]", text, actual))
        pcall(function() box.Text = text end)
    end

    task_wait(0.05)

    local btn = findConfirmButton(box)
    if btn then
        fireButton(btn)
    end

    fireFocusLost(box)

    Debug.log("Typed + submitted: " .. text)
    return true, "submitted"
end

-- =========================================================================
-- Notification remote discovery
-- =========================================================================

local function getHandlerSource(fn)
    if type(fn) ~= "function" then return nil end
    if type(debug) == "table" and type(debug.info) == "function" then
        local ok, src = pcall(debug.info, fn, "s")
        if ok and type(src) == "string" and #src > 0 then return src end
    end
    if type(debug) == "table" and type(debug.getinfo) == "function" then
        local ok, info = pcall(debug.getinfo, fn)
        if ok and type(info) == "table" then
            if type(info.short_src) == "string" and #info.short_src > 0 then
                return info.short_src
            end
            if type(info.source) == "string" and #info.source > 0 then
                return info.source
            end
        end
    end
    return nil
end

local function findNotificationRemote()
    if _G.PhiNotifyRemote then return _G.PhiNotifyRemote end

    if type(getconnections) ~= "function" then
        Debug.warn("getconnections unavailable")
        return nil
    end
    if type(debug) ~= "table"
       or (type(debug.getinfo) ~= "function" and type(debug.info) ~= "function") then
        Debug.warn("debug.getinfo unavailable")
        return nil
    end

    local netFolder
    local ok = pcall(function()
        local packages = ReplicatedStorage:FindFirstChild("Packages")
        if not packages then return end
        netFolder = packages:FindFirstChild("Net")
    end)
    if not ok or not netFolder then
        Debug.warn("Packages.Net not found")
        return nil
    end

    local descendants = netFolder:GetDescendants()
    Debug.log(string_format("Scanning %d descendants", #descendants))

    local scanned = 0
    for _, inst in ipairs(descendants) do
        local isRemote = false
        pcall(function() isRemote = inst:IsA("RemoteEvent") end)
        if isRemote then
            scanned = scanned + 1
            local conns
            local ok2 = pcall(function() conns = getconnections(inst.OnClientEvent) end)
            if ok2 and type(conns) == "table" then
                for _, c in ipairs(conns) do
                    local fn
                    pcall(function() fn = c.Function end)
                    if type(fn) == "function" then
                        local src = getHandlerSource(fn)
                        if type(src) == "string"
                           and src:find("NotificationController", 1, true) then
                            Debug.log("Matched: " .. inst:GetFullName())
                            _G.PhiNotifyRemote = inst
                            return inst
                        end
                    end
                end
            end
        end
    end

    Debug.warn(string_format("No match (scanned %d remotes)", scanned))
    return nil
end

-- =========================================================================
-- Skibidi UI loading — with fallback stub
-- =========================================================================

local SKIBIDI_URL = "https://raw.githubusercontent.com/blookzz/skibidi/refs/heads/main/UILib.lua"

local Skibidi
do
    local ok, result = pcall(function()
        local src = game:HttpGet(SKIBIDI_URL)
        if type(src) ~= "string" or #src < 200 then
            error("Skibidi source empty or truncated")
        end
        local chunk = loadstring(src)
        if type(chunk) ~= "function" then
            error("Skibidi loadstring returned non-function")
        end
        return chunk()
    end)

    if ok and type(result) == "table" and type(result.CreatePanel) == "function" then
        Skibidi = result
        print("[Jewski] Skibidi UI loaded")
    else
        warn("[Jewski] Skibidi UI failed to load: " .. tostring(result))
        Skibidi = nil
    end
end

local function makeStubUI()
    local function noop() end
    local function emptyComponent()
        local t = {}
        setmetatable(t, {
            __index = function(_, k)
                if k == "Content" or k == "Frame" then return t end
                return function() return t end
            end,
            __call = function() return t end,
        })
        return t
    end
    local stub = {}
    stub.Init = function(self) return self end
    stub.Theme = {}
    stub.CreatePanel = function()
        local t = emptyComponent()
        t.GetTab = function() return t end
        t.SetTab = noop
        t.SetTitle = noop
        t.Close = noop
        t.Content = t
        return t
    end
    stub.CreateSection        = emptyComponent
    stub.CreateToggle         = emptyComponent
    stub.CreateSlider         = emptyComponent
    stub.CreateButton         = emptyComponent
    stub.CreateKeyValue       = function()
        return {
            SetValue = noop, SetLabel = noop, GetValue = function() return "" end,
            Frame = emptyComponent(),
        }
    end
    stub.CreateStatusLog      = function() return { Log = noop, Clear = noop } end
    stub.CreateLabel          = emptyComponent
    stub.CreateDivider        = emptyComponent
    stub.CreateSpace          = emptyComponent
    stub.CreateParagraph      = emptyComponent
    stub.CreateProgressBar    = emptyComponent
    stub.CreateTextInput      = emptyComponent
    stub.CreateKeybind        = emptyComponent
    stub.CreateDropdown       = emptyComponent
    stub.CreateGroup          = emptyComponent
    stub.CreateColorPicker    = emptyComponent
    stub.CreateHStack         = emptyComponent
    stub.CreateVStack         = emptyComponent
    stub.ShowNotification     = noop
    stub.notify               = noop
    stub.Unload               = noop
    return stub
end

if not Skibidi then
    Skibidi = makeStubUI()
end

-- =========================================================================
-- THEME — royal purple + white
-- =========================================================================

if Skibidi and Skibidi.Init and next(Skibidi.Theme or {}) ~= nil then
    pcall(function()
        Skibidi.Init({
            Theme = {
                Bg0 = Color3.fromRGB(14, 12, 22),
                Bg1 = Color3.fromRGB(21, 18, 33),
                Bg2 = Color3.fromRGB(30, 26, 46),
                Bg3 = Color3.fromRGB(18, 15, 28),

                Accent     = Color3.fromRGB(160, 118, 255),
                AccentSec  = Color3.fromRGB(216, 198, 255),
                AccentDim  = Color3.fromRGB(72, 52, 128),

                ToggleOff  = Color3.fromRGB(42, 36, 60),
                ToggleOn   = Color3.fromRGB(126, 88, 210),
                Knob       = Color3.fromRGB(245, 240, 255),

                Hover      = Color3.fromRGB(38, 32, 56),
                InputBg    = Color3.fromRGB(14, 12, 22),

                TextPrimary   = Color3.fromRGB(245, 243, 252),
                TextMuted     = Color3.fromRGB(140, 132, 168),
                ActiveTabText = Color3.fromRGB(255, 255, 255),

                Success = Color3.fromRGB(120, 214, 150),
                Warning = Color3.fromRGB(240, 190, 100),
                Danger  = Color3.fromRGB(235, 100, 120),
                Info    = Color3.fromRGB(140, 168, 255),
            },
        })
    end)
end

-- =========================================================================
-- UI construction
-- =========================================================================

local UI = { panel = nil, log = nil, kvState = nil, kvSolved = nil, kvBuffer = nil }

local function buildUI(parent)
    Debug.log("buildUI start (Skibidi)")

    local panel = Skibidi.CreatePanel({
        Name          = OWN_GUI_NAME,
        Parent        = parent,
        Title         = "JEWSKI CODE SNIPER",
        Icon          = "crosshair",
        Width         = 340,
        Height        = 400,
        Tabs          = {
            { Name = "Main",  Icon = "zap" },
            { Name = "Debug", Icon = "bug" },
        },
        Search        = true,
        Scaler        = true,
        Minimized     = false,
        ClampToScreen = true,
        ConfirmClose  = true,
        CloseTitle    = "Close sniper?",
        CloseMessage  = "Automation will stop and the window will be removed.",
    })

    if not panel then
        Debug.error("CreatePanel returned nil")
        return UI
    end

    local function tabFrame(i)
        local t
        if type(panel.GetTab) == "function" then
            local ok, res = pcall(panel.GetTab, panel, i)
            if ok then t = res end
        end
        if not t and i == 1 then
            t = panel.Content
        end
        return t
    end

    local main = tabFrame(1)
    if main then
        -- STATUS --------------------------------------------------
        local okStatus, statusSection = pcall(Skibidi.CreateSection, main, {
            Title = "STATUS", Icon = "activity", Open = true,
        })
        if okStatus and statusSection and statusSection.Content then
            UI.kvState = Skibidi.CreateKeyValue(statusSection.Content, {
                Label = "State", Icon = "power", Value = "READY",
            })
            UI.kvSolved = Skibidi.CreateKeyValue(statusSection.Content, {
                Label = "Solved", Icon = "circle-check", Value = "0",
            })
            UI.kvBuffer = Skibidi.CreateKeyValue(statusSection.Content, {
                Label = "Buffer", Icon = "inbox",
                Value = "0 / " .. tostring(math_floor(Config.SubmitAfter + 0.5)),
            })
        else
            Debug.warn("STATUS section failed: " .. tostring(statusSection))
        end

        -- SETTINGS ------------------------------------------------
        local okSettings, settingsSection = pcall(Skibidi.CreateSection, main, {
            Title = "SETTINGS", Icon = "settings", Open = true,
        })
        if okSettings and settingsSection and settingsSection.Content then
            Skibidi.CreateToggle(settingsSection.Content, {
                Label = "Auto Type Codes",
                Default = Config.AutoTypeCodes,
                Flag = "jewski_autotype",
                OnChanged = function(v)
                    Config.AutoTypeCodes = v
                    Debug.log("Auto type: " .. tostring(v))
                end,
            })

            Skibidi.CreateToggle(settingsSection.Content, {
                Label = "Auto Submit",
                Default = Config.AutoSubmit,
                Flag = "jewski_autosubmit",
                OnChanged = function(v)
                    Config.AutoSubmit = v
                    Debug.log("Auto submit: " .. tostring(v))
                end,
            })

            Skibidi.CreateToggle(settingsSection.Content, {
                Label = "Auto Riddles",
                Default = Config.AIRiddles,
                Flag = "jewski_riddles",
                OnChanged = function(v)
                    Config.AIRiddles = v
                    Debug.log("AI riddles: " .. tostring(v))
                end,
            })

            Skibidi.CreateToggle(settingsSection.Content, {
                Label = "AI Auto Submit",
                Default = Config.AIAutoSubmit,
                Flag = "jewski_aisubmit",
                OnChanged = function(v)
                    Config.AIAutoSubmit = v
                    Debug.log("AI auto submit: " .. tostring(v))
                end,
            })

            Skibidi.CreateSlider(settingsSection.Content, {
                Label = "Submit After",
                Icon = "list-checks",
                Min = 1, Max = 10,
                Default = math_floor(Config.SubmitAfter + 0.5),
                Step = 1,
                Format = "%d",
                Flag = "jewski_submitafter",
                OnChanged = function(v)
                    v = math_floor((tonumber(v) or 1) + 0.5)
                    if v < 1 then v = 1 elseif v > 10 then v = 10 end
                    Config.SubmitAfter = v
                    if #State.buffer > 0 then State.buffer = {} end
                    if UI.kvBuffer then
                        UI.kvBuffer.SetValue(#State.buffer .. " / " .. tostring(v))
                    end
                end,
            })
        else
            Debug.warn("SETTINGS section failed: " .. tostring(settingsSection))
        end

        -- ACTIONS -------------------------------------------------
        local okActions, actionsSection = pcall(Skibidi.CreateSection, main, {
            Title = "ACTIONS", Icon = "wrench", Open = true,
        })
        if okActions and actionsSection and actionsSection.Content then
            Skibidi.CreateButton(actionsSection.Content, {
                Text = "Reset Counters",
                Icon = "rotate-ccw",
                Confirm = true,
                ConfirmText = "Confirm reset?",
                OnClick = function()
                    State.typedCount  = 0
                    State.buffer      = {}
                    State.solvedCount = 0
                    local box = findCodeBox()
                    if box then box.Text = "" end
                    Debug.log("Reset counters")
                    if UI.kvSolved then UI.kvSolved.SetValue("0") end
                    if UI.kvBuffer then
                        UI.kvBuffer.SetValue(
                            "0 / " .. tostring(math_floor(Config.SubmitAfter + 0.5)))
                    end
                end,
            })

            Skibidi.CreateButton(actionsSection.Content, {
                Text = "Unload",
                Icon = "log-out",
                Confirm = true,
                ConfirmText = "Confirm unload?",
                OnClick = function()
                    if getgenv().__jewskiSniper and getgenv().__jewskiSniper.unload then
                        pcall(getgenv().__jewskiSniper.unload)
                    end
                end,
            })
        else
            Debug.warn("ACTIONS section failed: " .. tostring(actionsSection))
        end
    else
        Debug.warn("Main tab frame unavailable")
    end

    -- Debug tab ----------------------------------------------------
    local debugTab = tabFrame(2)
    if debugTab then
        -- Build our own scroller instead of CreateStatusLog. This removes
        -- every dependency on Skibidi's internal layout shape, which in
        -- some builds produced a zero-sized frame that swallowed every
        -- line appended to it.
        debugTab.Visible = true

        local scroll = Instance.new("ScrollingFrame")
        scroll.Name = "JewskiDebugLog"
        scroll.Size = UDim2.new(1, 0, 1, -8)
        scroll.Position = UDim2.new(0, 0, 0, 0)
        scroll.BackgroundColor3 = (Skibidi.Theme and Skibidi.Theme.Bg3)
            or Color3.fromRGB(18, 15, 28)
        scroll.BackgroundTransparency = 0.2
        scroll.BorderSizePixel = 0
        scroll.ScrollBarThickness = 4
        scroll.ScrollBarImageColor3 = (Skibidi.Theme and Skibidi.Theme.Accent)
            or Color3.fromRGB(160, 118, 255)
        scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scroll.ClipsDescendants = true
        scroll.ZIndex = 2
        scroll.Parent = debugTab

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = scroll

        local stroke = Instance.new("UIStroke")
        stroke.Color = (Skibidi.Theme and Skibidi.Theme.AccentDim)
            or Color3.fromRGB(72, 52, 128)
        stroke.Thickness = 1
        stroke.Parent = scroll

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 8)
        pad.PaddingRight = UDim.new(0, 8)
        pad.PaddingTop = UDim.new(0, 6)
        pad.PaddingBottom = UDim.new(0, 6)
        pad.Parent = scroll

        local layout = Instance.new("UIListLayout")
        layout.FillDirection = Enum.FillDirection.Vertical
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 2)
        layout.Parent = scroll

        local lineCount = 0
        local MAX_LINES = Config.DebugMaxLines or 200

        local function appendLine(text)
            if lineCount >= MAX_LINES then
                local kids = scroll:GetChildren()
                local removed = 0
                for _, k in ipairs(kids) do
                    if k:IsA("TextLabel") and removed < 20 then
                        k:Destroy()
                        removed = removed + 1
                    end
                end
                lineCount = math.max(0, lineCount - removed)
            end

            local lbl = Instance.new("TextLabel")
            lbl.LayoutOrder = lineCount
            lbl.AutomaticSize = Enum.AutomaticSize.Y
            lbl.Size = UDim2.new(1, 0, 0, 14)
            lbl.BackgroundTransparency = 1
            lbl.Font = Enum.Font.Code
            lbl.TextSize = 11
            lbl.TextColor3 = (Skibidi.Theme and Skibidi.Theme.TextPrimary)
                or Color3.fromRGB(245, 243, 252)
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.TextYAlignment = Enum.TextYAlignment.Top
            lbl.TextWrapped = true
            lbl.Text = text
            lbl.ZIndex = 3
            lbl.Parent = scroll

            lineCount = lineCount + 1
            task.defer(function()
                if scroll.Parent then
                    scroll.CanvasPosition = Vector2.new(0, math.huge)
                end
            end)
        end

        UI.log = {
            Log = appendLine,
            Clear = function()
                for _, k in ipairs(scroll:GetChildren()) do
                    if k:IsA("TextLabel") then k:Destroy() end
                end
                lineCount = 0
            end,
        }

        -- Replay anything logged before the widget existed.
        for _, line in ipairs(Debug.lines()) do
            appendLine(line)
        end
        Debug.attachUI(appendLine)
    else
        Debug.warn("Debug tab frame unavailable")
    end

    UI.panel = panel

    local safeN = tostring(math_floor(Config.SubmitAfter + 0.5))
    if UI.kvState  then UI.kvState.SetValue("READY") end
    if UI.kvSolved then UI.kvSolved.SetValue("0") end
    if UI.kvBuffer then UI.kvBuffer.SetValue("0 / " .. safeN) end

    return UI
end

-- =========================================================================
-- Status mirror
-- =========================================================================

local function refreshStatus()
    if not UI or not UI.kvState then return end
    local status
    if not Config.Enabled then
        status = "DISABLED"
    elseif #State.buffer > 0 then
        status = "COLLECTING"
    elseif State.typedCount > 0 then
        status = "TYPING"
    else
        status = "READY"
    end
    if UI.kvState.SetValue then UI.kvState.SetValue(status) end
    if UI.kvSolved and UI.kvSolved.SetValue then
        UI.kvSolved.SetValue(tostring(State.solvedCount))
    end
    if UI.kvBuffer and UI.kvBuffer.SetValue then
        local n = tostring(math_floor(Config.SubmitAfter + 0.5))
        UI.kvBuffer.SetValue(#State.buffer .. " / " .. n)
    end
end

-- =========================================================================
-- Notification handling
-- =========================================================================

local function handleRiddle(text)
    if not Config.AIRiddles then return false end
    if not RiddleWorker.ready then
        Debug.warn("Riddle worker not configured — skipping riddle")
        return false
    end

    Debug.log("Sending to AI: " .. text:sub(1, 120))

    local answer, source = RiddleWorker.solve(text)
    if not answer or answer == "" then
        Debug.warn("AI returned nothing (" .. tostring(source) .. ")")
        return false
    end

    Debug.log(string_format("AI answer (%s): %s", tostring(source), answer))

    if Config.AIAutoSubmit then
        local ok, why = submitCode(answer)
        if ok then
            State.solvedCount = State.solvedCount + 1
            Skibidi.ShowNotification({
                Title = "AI Answer",
                Text = answer,
                Icon = "sparkles",
            })
        else
            Debug.warn("AI submit failed: " .. tostring(why))
            Skibidi.ShowNotification({
                Title = "AI Submit Failed",
                Text = tostring(why),
                Icon = "error",
            })
        end
        refreshStatus()
    else
        local box = findCodeBox()
        if box then pcall(function() box.Text = answer end) end
        Skibidi.ShowNotification({
            Title = "AI Ready",
            Text = answer,
            Icon = "info",
        })
    end

    return true
end

local function handleNotification(raw)
    Debug.log("Notification: " .. tostring(raw):sub(1, 200))

    if type(raw) ~= "string" then return end

    local text = cleanText(raw)
    if text:gsub("%s", "") == "" then return end

    local now = os_clock()
    if text == State.lastSeen and now - State.lastSeenAt < 0.35 then return end
    State.lastSeen, State.lastSeenAt = text, now

    local lower = text:gsub("<[^>]->", " "):lower()
    if containsAny(lower, IGNORE_EXPIRED) or containsAny(lower, IGNORE_REDEEMED) then
        Debug.log("Notification marked done/expired")
        refreshStatus()
        return
    end

    if not Config.Enabled then
        Debug.log("Disabled — ignoring")
        return
    end

    if Config.AIRiddles and looksLikeRiddle(text) then
        local ok = try("handleRiddle", handleRiddle, text)
        if ok then return end
    end

    if not Config.AutoTypeCodes then
        Debug.log("Auto-type off — ignoring")
        return
    end

    local frag = extractFragment(text)
    if not frag then
        Debug.log("No usable fragment")
        return
    end

    State.buffer[#State.buffer + 1] = frag
    Debug.log(string_format("Buffered %s (%d/%d)", frag, #State.buffer, Config.SubmitAfter))
    refreshStatus()

    if #State.buffer < Config.SubmitAfter then return end

    local joined = stripAllWhitespace(table_concat(State.buffer))
    State.buffer = {}
    refreshStatus()

    Debug.log("Submitting buffer: " .. joined)
    local ok, why = submitCode(joined)

    if ok then
        State.typedCount  = State.typedCount + 1
        State.solvedCount = State.solvedCount + 1
    else
        Debug.warn("Submit failed: " .. tostring(why))
        Skibidi.ShowNotification({
            Title = "Submit Failed",
            Text = tostring(why),
            Icon = "error",
        })
    end

    refreshStatus()
end

-- =========================================================================
-- PlayerGui TextLabel watcher
-- =========================================================================

local NOTIFY_PHRASES = {
    "invalid code", "code is invalid", "expired",
    "already redeemed", "already used",
    "doesn't exist", "does not exist",
    "not found", "rejected", "code is",
    "use code",
}

local function watchTextObject(inst)
    if not (inst:IsA("TextLabel") or inst:IsA("TextButton")) then return end
    if isOwnUI(inst) then return end

    local function check()
        local t = tostring(inst.Text or ""):lower()
        for _, phrase in ipairs(NOTIFY_PHRASES) do
            if t:find(phrase, 1, true) then
                pcall(handleNotification, inst.Text)
                return
            end
        end
    end

    table.insert(State.connections, inst:GetPropertyChangedSignal("Text"):Connect(check))
end

-- =========================================================================
-- Entry
-- =========================================================================

local function main()
    Debug.log("=== Jewski Code Sniper starting ===")
    Debug.log("Riddle worker ready: " .. tostring(RiddleWorker.ready))

    if not game:IsLoaded() then
        Debug.log("Waiting for game load...")
        game.Loaded:Wait()
    end

    local parent = (gethui and gethui()) or cloneref(game:GetService("CoreGui"))
    if not parent then
        Debug.error("No UI parent available")
        return
    end

    local ui = try("buildUI", buildUI, parent)
    if not ui then
        Debug.error("buildUI failed")
        return
    end
    Debug.log("UI attached")

    local remote = try("findNotificationRemote", findNotificationRemote)
    if remote then
        State.connections[#State.connections + 1] =
            remote.OnClientEvent:Connect(function(...)
                local args = table_pack(...)
                local preview = {}
                for i = 1, math_min(args.n, 5) do
                    preview[#preview + 1] = tostring(args[i])
                end
                Debug.log("[REMOTE] n=" .. args.n .. " | " .. table_concat(preview, " | "))

                local body = args[1]
                if type(body) == "string" and body ~= "" then
                    try("handleNotification", handleNotification, body)
                end
            end)
        Debug.log("Remote hooked: " .. remote:GetFullName())
    else
        Debug.warn("Remote not found — relying on TextLabel watcher")
    end

    task_spawn(function()
        local pg = LocalPlayer:WaitForChild("PlayerGui", 20)
        if not pg then return end
        for _, d in ipairs(pg:GetDescendants()) do
            watchTextObject(d)
        end
        local conn = pg.DescendantAdded:Connect(function(d)
            task_wait(0.04)
            pcall(watchTextObject, d)
        end)
        State.connections[#State.connections + 1] = conn
        Debug.log("Text watcher active")
    end)

    task_spawn(function()
        while not State.unloaded do
            task_wait(0.5)
            pcall(refreshStatus)
        end
    end)

    refreshStatus()
    Debug.log("=== Jewski Code Sniper ready ===")

    Skibidi.ShowNotification({
        Title = "Jewski Code Sniper",
        Text = "Loaded and watching for codes.",
        Icon = "success",
        Duration = 3,
    })

    getgenv().__jewskiSniper = {
        unload = function()
            State.unloaded = true
            for _, c in ipairs(State.connections) do
                pcall(function() c:Disconnect() end)
            end
            pcall(function() Skibidi.Unload() end)
            getgenv().__jewskiSniper = nil
        end,
        debug = Debug,
        config = Config,
        submit = submitCode,
        solveRiddle = function(text) return RiddleWorker.solve(text) end,
    }
end

local ok, err = try("main", main)
if not ok then
    Debug.error("main() crashed: " .. tostring(err))
end
