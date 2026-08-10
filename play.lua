local NeteastMusicApi = "http://frp-fly.com:12856"
local TransApi = "http://newgmapi.liulikeji.cn/api/ffmpeg"


local feature = {"id","lid","dfpwm"} --1=id 2=lid 3=dfpwm
local playMode = {"once","cycle"} --1=once 2=cycle

local mode
local id
local play = false
local shuffle = false

--[[==================  Startup-style UI infrastructure  ==================]]
-- Mirrors the conventions from startup.lua:
--   * genStr(s,n) helper
--   * absTextField  + newTextField  : paint via term.blit with color-code strings
--   * absSelectBox + newSelectBox   : horizontal options, selected inverted

local genStr = function(s, count)
    local result = ""
    for i = 1, count, 1 do
        result = result .. s
    end
    return result
end

local termUtil = {
    cpX = 1,
    cpY = 1,
    fieldTb = {},
    selectBoxTb = {}
}

local absTextField = {
    x = 1,
    y = 1,
    len = 15,
    textColor = "0",
    backgroundColor = "8",
    focusTextColor = "0",
    focusBackgroundColor = "e"
}

function absTextField:paint()
    local str = ""
    local value_text = tostring(self.key[self.value])
    for i = 1, self.len, 1 do
        local ch = string.sub(value_text, i, i)
        if #ch > 0 then
            str = str .. ch
        else
            str = str .. string.rep(" ", self.len - #str)
            break
        end
    end
    local focused = termUtil.cpY == self.y and
                    termUtil.cpX >= self.x and termUtil.cpX <= self.x + self.len
    local tc = focused and self.focusTextColor or self.textColor
    local bc = focused and self.focusBackgroundColor or self.backgroundColor
    term.setCursorPos(self.x, self.y)
    term.blit(str, genStr(tc, #str), genStr(bc, #str))
end

function absTextField:inputChar(char)
    local xPos = termUtil.cpX
    xPos = xPos + 1 - self.x
    local field = tostring(self.key[self.value])
    if #field < self.len then
        if self.type == "number" then
            if char >= '0' and char <= '9' then
                if field == "0" then
                    field = char
                else
                    field = string.sub(field, 1, xPos) .. char .. string.sub(field, xPos + 1, #field)
                end
                self.key[self.value] = tonumber(field)
                termUtil.cpX = termUtil.cpX + 1
            end
        elseif self.type == "string" then
            field = string.sub(field, 1, xPos) .. char .. string.sub(field, xPos + 1, #field)
            self.key[self.value] = field
            termUtil.cpX = termUtil.cpX + 1
        end
    end
end

function absTextField:inputKey(key)
    local field = tostring(self.key[self.value])
    local minXp = self.x
    local maxXp = minXp + #field
    if key == 259 or key == 261 then -- backspace
        if termUtil.cpX > minXp then
            termUtil.cpX = termUtil.cpX - 1
            if #field > 0 then
                local index = termUtil.cpX - self.x
                field = string.sub(field, 1, index) .. string.sub(field, index + 2, #field)
            end
            if self.type == "number" then
                local number = tonumber(field)
                if not number then self.key[self.value] = 0
                else self.key[self.value] = number end
            else
                self.key[self.value] = field
            end
        end
    elseif key == 262 or key == 263 then -- right / left
        if key == 262 then termUtil.cpX = termUtil.cpX + 1
        else termUtil.cpX = termUtil.cpX - 1 end
    end
    maxXp = minXp + #tostring(self.key[self.value])
    if termUtil.cpX > maxXp then termUtil.cpX = maxXp end
    if termUtil.cpX < minXp then termUtil.cpX = minXp end
end

function absTextField:click(x, y)
    local xPos = self.x
    if x >= xPos then
        local l = #tostring(self.key[self.value])
        if x < xPos + l then
            termUtil.cpX, termUtil.cpY = x, y
        else
            termUtil.cpX, termUtil.cpY = xPos + l, y
        end
    end
end

local newTextField = function(key, value, x, y, len, tc, bc, ftc, fbc)
    local obj = setmetatable({
        key = key,
        value = value,
        type = type(key[value]),
        x = x,
        y = y,
        len = len or 15,
        textColor = tc or "0",
        backgroundColor = bc or "8",
        focusTextColor = ftc or "0",
        focusBackgroundColor = fbc or "e"
    }, { __index = absTextField })
    return obj
end

-- Horizontal SelectBox (same style as startup.lua absSelectBox):
--   contents[] displayed horizontally with interval spaces.
--   Selected item blits inverted (background swaps with select).
local absSelectBox = {
    x = 1,
    y = 1,
    label = "",
    contents = {},
    count = 0,
    interval = 1,
    fontColor = "8",
    backgroundColor = "f",
    selectColor = "e"
}

function absSelectBox:paint()
    -- label
    if self.label and #self.label > 0 then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.lightGray)
        term.setCursorPos(self.x, self.y)
        term.write(self.label)
    end
    -- options (next cell)
    local select = tostring(self.key[self.value])
    local xc = self.x + (self.labelXOff or 0)
    term.setCursorPos(xc, self.y)
    for i = 1, #self.contents, 1 do
        local str = tostring(self.contents[i])
        if select == str then
            term.blit(str, genStr(self.backgroundColor, #str), genStr(self.selectColor, #str))
        else
            term.blit(str, genStr(self.fontColor, #str), genStr(self.backgroundColor, #str))
        end
        for j = 1, self.interval, 1 do term.write(" ") end
    end
end

function absSelectBox:click(x, y)
    if y ~= self.y then return end
    local xc = self.x + (self.labelXOff or 0)
    local xPos = x + 1 - xc
    local index = 0
    for i = 1, #self.contents, 1 do
        local w = #tostring(self.contents[i])
        if xPos >= index + 1 and xPos <= index + w then
            self.key[self.value] = self.contents[i]
            break
        end
        index = index + w + self.interval
    end
end

local newSelectBox = function(key, value, interval, x, y, label, labelXOff, fontColor, backgroundColor, selectColor, ...)
    return setmetatable({
        key = key,
        value = value,
        interval = interval,
        x = x,
        y = y,
        label = label or "",
        labelXOff = labelXOff or 0,
        type = type(key[value]),
        fontColor = fontColor or "8",
        backgroundColor = backgroundColor or "f",
        selectColor = selectColor or "e",
        contents = {...}
    }, { __index = absSelectBox })
end

--[[==================  GUI state  ==================]]

local PAGE = "MENU"   -- MENU / INPUT / PLAY
local termSizeX, termSizeY = term.getSize()
local dfpwm = require("cc.audio.dfpwm")
local speaker = peripheral.find("speaker")
local decoder = dfpwm.make_decoder()

-- GUI state tables used by the TextField/SelectBox widgets (same pattern as
-- startup.lua's `properties` table).
local gui_cfg = {
    mode_name = "Single",
    input_id = "",
    input_start = 1,
    loop_sel = "OFF",
    shuffle_sel = "OFF"
}

local gui_mode = nil        -- 1/2/3, translated from gui_cfg.mode_name
local gui_play_stopped = false
local gui_loop_break_once = false
local gui_playing = false
local gui_current_song_name = ""
local gui_log = {}

local chunk_size = 6000
local bytes_read = 0
local total_length, total_size = 0, 0
local i = 1  -- playlist seek index

function GuiLog(msg)
    gui_log[#gui_log + 1] = msg
    local logMax = math.max(3, termSizeY - 9)
    if #gui_log > logMax then
        table.remove(gui_log, 1)
    end
end

--[[==================  Business helpers  ==================]]

function ShuffleArray(arr)
    math.randomseed(os.epoch("utc"))
    for i = #arr, 2, -1 do
        local j = math.random(i)
        arr[i], arr[j] = arr[j], arr[i]
    end
    return arr
end

function GetMusicUrl(music_id)
    local getMusic = "/song/url?id=" .. music_id
    local data = http.get(NeteastMusicApi .. getMusic).readAll()
    local music_get = textutils.unserialiseJSON(data)
    local musicUrl = music_get["data"][1]["url"]

    local json = {
        input_url = musicUrl,
        args = { "-vn", "-ar", "48000", "-ac", "1" },
        output_format = "dfpwm"
    }
    local response = http.post(TransApi, textutils.serializeJSON(json), { ["Content-Type"] = "application/json" })
    data = textutils.unserializeJSON(response.readAll())

    return data["download_url"]
end

function GetSongName(music_id)
    local ok, data = pcall(function()
        return http.get(NeteastMusicApi .. "/song/detail?ids=" .. music_id).readAll()
    end)
    if not ok then return "ID:" .. music_id end
    local detail = textutils.unserialiseJSON(data)
    if detail and detail.songs and detail.songs[1] then
        local n = detail.songs[1].name
        if n and type(n) == "string" and #n > 0 then
            local stripped = n:gsub("[^\32-\126]", "?")
            if #stripped > 0 then return stripped end
        end
    end
    return "ID:" .. music_id
end

-- Helper: translate gui_cfg.mode_name <-> numeric mode
local function ModeNameToNum(name)
    if name == "Single" then return 1 end
    if name == "List" then return 2 end
    if name == "File" then return 3 end
    return 1
end

--[[==================  Pure-blocking playback (original design)  ==================]]

local function PlayMusicCore(url)
    bytes_read = 0
    local function get_total_duration(u)
        local handle, err = http.get(u)
        if not handle then error("No duration: " .. (err or "?")) end
        local d = handle.readAll()
        handle.close()
        return (#d * 8) / 48000, #d
    end
    if url then
        total_length, total_size = get_total_duration(url)
    end
    local file = http.get(url)
    while bytes_read < total_size do
        local chunk = file and file.read(chunk_size)
        if chunk and #chunk > 0 then
            local buffer = decoder(chunk)
            if buffer and #buffer > 0 then
                while not speaker.playAudio(buffer) do
                    os.pullEvent("speaker_audio_empty")
                end
            end
        end
        bytes_read = bytes_read + chunk_size
    end
    if file then file.close() end
end

local function PlayFlow()
    bytes_read = 0
    total_length = 0
    total_size = 0
    gui_play_stopped = false
    gui_loop_break_once = false
    local loop_en = (gui_cfg.loop_sel == "ON")
    local shuf_en = (gui_cfg.shuffle_sel == "ON")

    if gui_mode == 1 then
        local mid = (mode == 1 and id) or gui_cfg.input_id
        GuiLog("Get: " .. mid)
        gui_current_song_name = GetSongName(mid)
        local url = GetMusicUrl(mid)
        local count = 1
        repeat
            if gui_loop_break_once then break end
            GuiLog("#" .. count .. " " .. gui_current_song_name)
            PlayMusicCore(url)
            count = count + 1
        until (not loop_en) or gui_loop_break_once
        GuiLog(gui_loop_break_once and "Stopped" or "Done")

    elseif gui_mode == 2 then
        local pid = (mode == 2 and id) or gui_cfg.input_id
        GuiLog("List: " .. pid)
        local data = http.get(NeteastMusicApi .. "/playlist/detail?s=0&id=" .. pid).readAll()
        local musicList = textutils.unserialiseJSON(data)
        local List = musicList["playlist"]["tracks"]
        local idList = {}
        for _, v in pairs(List) do idList[#idList + 1] = v["id"] end
        GuiLog(tostring(#idList) .. " trk" .. (shuf_en and " RND" or ""))

        local startIdx = tonumber(gui_cfg.input_start) or 1
        local loopCount = 1
        repeat
            if gui_loop_break_once then break end
            if shuf_en then ShuffleArray(idList) end
            i = math.max(1, math.min(startIdx, #idList))
            startIdx = 1
            GuiLog("Lp" .. loopCount .. " @" .. "#" .. i)
            while not (i > #idList) and not gui_loop_break_once do
                local mid = idList[i]
                gui_current_song_name = GetSongName(mid)
                GuiLog("[" .. i .. "/" .. #idList .. "] " .. gui_current_song_name)
                local ok, url = pcall(GetMusicUrl, mid)
                if ok and url then
                    PlayMusicCore(url)
                else
                    GuiLog("Skip: err")
                end
                i = i + 1
            end
            loopCount = loopCount + 1
        until (not loop_en) or gui_loop_break_once
        GuiLog(gui_loop_break_once and "Stopped" or "Done")

    elseif gui_mode == 3 then
        local fn = (mode == 3 and id) or gui_cfg.input_id
        GuiLog("File: " .. fn)
        gui_current_song_name = fn
        local loopCount = 1
        repeat
            if gui_loop_break_once then break end
            GuiLog("#" .. loopCount)
            bytes_read = 0
            local f = io.open(fn, "rb")
            if f then
                local all = f:read("*a")
                f:close()
                total_size = #all
                total_length = (total_size * 8) / 48000
                local pos = 1
                while pos < total_size and not gui_loop_break_once do
                    local chunk = all:sub(pos, pos + chunk_size - 1)
                    pos = pos + chunk_size
                    bytes_read = bytes_read + chunk_size
                    local buffer = decoder(chunk)
                    if buffer and #buffer > 0 then
                        while not speaker.playAudio(buffer) do
                            os.pullEvent("speaker_audio_empty")
                        end
                    end
                end
            else
                GuiLog("File ERR")
                sleep(1)
                break
            end
            loopCount = loopCount + 1
        until (not loop_en) or gui_loop_break_once
        GuiLog(gui_loop_break_once and "Stopped" or "Done")
    end
end

--[[==================  Page-specific widget tables  ==================]]

-- MENU page
local function SetupMenuWidgets()
    termUtil.fieldTb = {}
    termUtil.selectBoxTb = {
        mode = newSelectBox(
            gui_cfg, "mode_name",
            1,                         -- interval between options
            2, 4,                      -- x, y
            "Mode:",                   -- label
            6,                         -- labelXOff: options start 6 chars right of x
            "0", "f", "e",             -- fontColor / backgroundColor / selectColor
            "Single", "List", "File"
        )
    }
end

-- INPUT page widgets: ID / Start / Loop / Shuffle
local W_INPUT_ID_LEN, W_INPUT_START_LEN = 20, 4
local function SetupInputWidgets()
    termUtil.fieldTb = {
        input_id    = newTextField(gui_cfg, "input_id",    5, 4,  W_INPUT_ID_LEN,    "0", "8", "0", "e"),
        input_start = newTextField(gui_cfg, "input_start", 5, 7,  W_INPUT_START_LEN, "0", "8", "0", "e"),
    }
    termUtil.selectBoxTb = {
        loop_sel    = newSelectBox(gui_cfg, "loop_sel",    2, 2, 10, "Loop:", 6, "0", "f", "e", "OFF", "ON"),
        shuffle_sel = newSelectBox(gui_cfg, "shuffle_sel", 2, 2, 12, "Shuf:", 6, "0", "f", "e", "OFF", "ON"),
    }
end

--[[==================  Startup-style page renderers  ==================]]

-- Small blit-rect helper to paint a row of colored characters safely.
local function BlitRow(x, y, chars, tcolor, bcolor)
    local n = #chars
    term.setCursorPos(x, y)
    term.blit(chars, genStr(tcolor, n), genStr(bcolor, n))
end

-- Paint a solid background row, then overlay a label centered in it.
-- Uses term.blit safely: all three blit() args always have equal length.
local function BlitLabelBar(x, y, w, label, tcolor, bcolor)
    BlitRow(x, y, string.rep(" ", w), tcolor, bcolor)
    if label and #label > 0 then
        local ll = math.min(#label, w)
        local lab = label:sub(1, ll)
        local lx = x + math.floor((w - ll) / 2)
        term.setCursorPos(lx, y)
        term.blit(lab, genStr(tcolor, ll), genStr(bcolor, ll))
    end
end

local function RenderMenu()
    term.clear()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    -- Title (row 1): same blit style as startup uses for headings.
    local title = "Netease Player"
    local padL = math.max(0, math.floor((termSizeX - #title) / 2))
    term.setCursorPos(1, 1)
    term.blit(
        string.rep(" ", padL) .. title .. string.rep(" ", math.max(0, termSizeX - padL - #title)),
        genStr("0", termSizeX), genStr("3", termSizeX)
    )
    -- Instructions
    term.setTextColor(colors.lightGray)
    term.setBackgroundColor(colors.black)
    term.setCursorPos(2, 3)
    term.write("Pick mode, click line")
    term.setCursorPos(2, termSizeY - 1)
    term.write("Enter=next B=back")
    term.setCursorPos(2, termSizeY)
    term.write("CLI: play id <id>")

    -- Paint the startup-style horizontal SelectBox (mode row)
    termUtil.selectBoxTb.mode:paint()

    -- Mode-specific short descriptions (extra rows below the selectbox for clarity)
    term.setBackgroundColor(colors.black)
    local mode_text
    if gui_cfg.mode_name == "Single" then mode_text = "by track ID"
    elseif gui_cfg.mode_name == "List" then mode_text = "by playlist ID"
    else mode_text = "local .dfpwm path" end
    term.setTextColor(colors.cyan)
    term.setCursorPos(2, 6)
    term.write(string.rep(" ", termSizeX - 1))
    term.setCursorPos(2, 6)
    term.write("> " .. mode_text)

    -- Big "START" button using blit (row 8-10, but compact: one line row 9)
    local btnW = math.min(termSizeX - 4, 18)
    local bx = math.floor((termSizeX - btnW) / 2)
    local by = 9
    BlitLabelBar(bx, by, btnW, "ENTER Start", "0", "5")
    -- Border
    BlitRow(bx, by - 1, string.rep("-", btnW), "8", "0")
    BlitRow(bx, by + 1, string.rep("-", btnW), "8", "0")
end

local function RenderInput()
    term.clear()
    term.setBackgroundColor(colors.black)
    -- Title bar
    local sub = gui_cfg.mode_name
    local title = "Setup: " .. sub
    local padL = math.max(0, math.floor((termSizeX - #title) / 2))
    term.setCursorPos(1, 1)
    term.blit(
        string.rep(" ", padL) .. title .. string.rep(" ", math.max(0, termSizeX - padL - #title)),
        genStr("0", termSizeX), genStr("3", termSizeX)
    )

    -- Row labels (startup-style: text + term.blit field right after)
    term.setTextColor(colors.lightGray)
    term.setBackgroundColor(colors.black)
    if gui_mode == 3 then
        term.setCursorPos(2, 4)
        term.write("File:")
    else
        term.setCursorPos(2, 4)
        term.write("ID  :")
    end

    if gui_mode == 2 then
        term.setCursorPos(2, 7)
        term.write("St# :")
    end

    -- Paint fields & selectboxes
    for _, v in pairs(termUtil.fieldTb) do v:paint() end
    for _, v in pairs(termUtil.selectBoxTb) do v:paint() end

    -- Bottom buttons: BACK + START (blit bars)
    local bw = math.floor((termSizeX - 6) / 2)
    local by = termSizeY - 3
    BlitLabelBar(2, by, bw, "B Back", "f", "8")
    BlitLabelBar(4 + bw, by, bw, "ENT Play", "0", "5")

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    term.setCursorPos(2, termSizeY)
    term.write("Tab=sw B=back")
end

local function RenderPlay()
    term.clear()
    -- Title
    local flags = ""
    if gui_cfg.loop_sel == "ON" then flags = flags .. "L" end
    if gui_cfg.shuffle_sel == "ON" then flags = flags .. "S" end
    local title = "PLAY"
    if #flags > 0 then title = title .. " [" .. flags .. "]" end
    local padL = math.max(0, math.floor((termSizeX - #title) / 2))
    term.setCursorPos(1, 1)
    term.blit(
        string.rep(" ", padL) .. title .. string.rep(" ", math.max(0, termSizeX - padL - #title)),
        genStr("0", termSizeX), genStr("3", termSizeX)
    )

    -- Song name (row 2): yellow
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    term.setCursorPos(1, 2)
    term.clearLine()
    local name = gui_current_song_name
    if #name > termSizeX then name = name:sub(1, termSizeX - 3) .. ".." end
    term.setCursorPos(math.max(1, math.floor((termSizeX - #name) / 2)), 2)
    term.write(name)

    -- Progress bar (row 3): startup-style via blit filled/empty char pairs
    local pw = termSizeX
    local percent = 0
    if total_size and total_size > 0 then
        percent = math.min(1, bytes_read / total_size)
    end
    local filled = math.floor(percent * pw)
    local empty = pw - filled
    term.setCursorPos(1, 3)
    if filled > 0 then
        term.blit(string.rep(" ", filled), genStr("d", filled), genStr("d", filled))
    end
    if empty > 0 then
        term.blit(string.rep(" ", empty), genStr("8", empty), genStr("8", empty))
    end

    -- Row 4: time + % (blit background black, text white)
    local cur = 0
    local tot = total_length or 0
    if total_size and total_size > 0 then
        cur = (bytes_read * 8) / 48000
    end
    local info = ("%ds/%ds %d%%"):format(math.floor(cur), math.ceil(tot), math.floor(percent * 100))
    BlitRow(1, 4, info .. string.rep(" ", math.max(0, termSizeX - #info)), "f", "0")

    -- Control buttons (row 5): blit color bars (startup selectbox-like colors)
    if gui_mode == 2 then
        local gap = 1
        local totalW = termSizeX - 2
        local bw = math.floor((totalW - 2 * gap) / 3)
        BlitLabelBar(1, 5, bw, "<Prev", "f", "8")
        BlitLabelBar(1 + bw + gap, 5, bw, "Stop", "0", "e")
        BlitLabelBar(1 + 2 * (bw + gap), 5, bw, "Next>", "f", "8")
    else
        BlitLabelBar(1, 5, termSizeX, "X STOP & BACK", "0", "e")
    end

    -- Log header + log region
    local logH = math.max(2, termSizeY - 9)
    local logY = 9
    -- Header row (row 8)
    BlitRow(1, logY - 1, " Log" .. string.rep(" ", math.max(0, termSizeX - 4)), "f", "8")
    -- Log lines
    for idx = 1, logH do
        term.setCursorPos(1, logY + idx - 1)
        term.clearLine()
        local line = gui_log[#gui_log - (logH - idx)]
        if line then
            if #line > termSizeX then line = line:sub(1, termSizeX - 3) .. ".." end
            local disp = line .. string.rep(" ", math.max(0, termSizeX - #line))
            term.blit(disp, genStr("7", #disp), genStr("0", #disp))
        end
    end
end

--[[==================  Hit-test helpers for non-widget elements  ==================]]

local function HitMenuMode(x, y)
    -- Delegate click to the mode select box
    termUtil.selectBoxTb.mode:click(x, y)
end

local function HitMenuStart(x, y)
    -- "START" blit button
    local btnW = math.min(termSizeX - 4, 18)
    local bx = math.floor((termSizeX - btnW) / 2)
    local by = 9
    return x >= bx and x < bx + btnW and y == by
end

local function HitInputButtons(x, y)
    local bw = math.floor((termSizeX - 6) / 2)
    local by = termSizeY - 3
    if y == by then
        if x >= 2 and x < 2 + bw then return "back" end
        if x >= 4 + bw and x < 4 + 2 * bw then return "play" end
    end
    return nil
end

local function HitPlayButtons(x, y)
    if y ~= 5 then return nil end
    if gui_mode == 2 then
        local gap = 1
        local totalW = termSizeX - 2
        local bw = math.floor((totalW - 2 * gap) / 3)
        if x >= 1 and x < 1 + bw then return "prev" end
        if x >= 1 + bw + gap and x < 1 + 2 * bw + gap then return "stop" end
        if x >= 1 + 2 * (bw + gap) and x <= termSizeX then return "next" end
    else
        if x >= 1 and x <= termSizeX then return "stop" end
    end
    return nil
end

--[[==================  Start playback  ==================]]

local function StartFromGui()
    gui_mode = ModeNameToNum(gui_cfg.mode_name)
    mode = gui_mode
    id = gui_cfg.input_id
    play = (gui_cfg.loop_sel == "ON")
    shuffle = (gui_cfg.shuffle_sel == "ON")
    -- Default start index for playlist to 1 if user emptied the field (tonumber 0)
    if gui_mode == 2 and (not tonumber(gui_cfg.input_start) or tonumber(gui_cfg.input_start) < 1) then
        gui_cfg.input_start = 1
    end
    gui_log = {}
    gui_playing = false
    PAGE = "PLAY"
end

--[[==================  Main GUI event loop (startup events style)  ==================]]

local function GuiMainLoop()
    local dirty = true
    while true do
        if dirty then
            if PAGE == "MENU" then
                SetupMenuWidgets()
                RenderMenu()
            elseif PAGE == "INPUT" then
                gui_mode = ModeNameToNum(gui_cfg.mode_name)
                SetupInputWidgets()
                RenderInput()
            elseif PAGE == "PLAY" then
                RenderPlay()
            end
            term.setCursorPos(termUtil.cpX, termUtil.cpY)
            term.setCursorBlink(PAGE == "INPUT")
            dirty = false
        end
        local ev = {os.pullEvent()}
        local type = ev[1]

        if PAGE == "MENU" then
            if type == "mouse_click" then
                HitMenuMode(ev[3], ev[4])
                if HitMenuStart(ev[3], ev[4]) then
                    PAGE = "INPUT"
                    termUtil.cpX = 5; termUtil.cpY = 4
                end
                dirty = true
            elseif type == "char" then
                local c = ev[2]
                if c == "1" then gui_cfg.mode_name = "Single"; dirty = true
                elseif c == "2" then gui_cfg.mode_name = "List"; dirty = true
                elseif c == "3" then gui_cfg.mode_name = "File"; dirty = true
                elseif c == "\n" or c == "\r" then
                    -- handled in key enter too
                end
            elseif type == "key" then
                if ev[2] == keys.enter then
                    PAGE = "INPUT"
                    termUtil.cpX = 5; termUtil.cpY = 4
                    dirty = true
                elseif ev[2] == keys.backspace then
                    return
                end
            end

        elseif PAGE == "INPUT" then
            if type == "mouse_click" then
                local x, y = ev[3], ev[4]
                -- field click
                for _, v in pairs(termUtil.fieldTb) do
                    if y == v.y and x >= v.x and x <= v.x + v.len then v:click(x, y) end
                end
                -- selectbox click
                for _, v in pairs(termUtil.selectBoxTb) do v:click(x, y) end
                -- back/play buttons
                local b = HitInputButtons(x, y)
                if b == "back" then PAGE = "MENU"
                elseif b == "play" then StartFromGui() end
                dirty = true
            elseif type == "char" then
                local c = ev[2]
                if c == "b" or c == "B" then
                    PAGE = "MENU"; dirty = true
                else
                    for _, v in pairs(termUtil.fieldTb) do
                        if termUtil.cpY == v.y and termUtil.cpX >= v.x and termUtil.cpX <= v.x + v.len then
                            v:inputChar(c)
                        end
                    end
                    dirty = true
                end
            elseif type == "key" then
                local key = ev[2]
                if key == keys.backspace then
                    for _, v in pairs(termUtil.fieldTb) do
                        if termUtil.cpY == v.y and termUtil.cpX >= v.x and termUtil.cpX <= v.x + v.len then
                            v:inputKey(key)
                        end
                    end
                    dirty = true
                elseif key == keys.tab then
                    -- swap focus fields in input page (Start only when mode==2)
                    if gui_mode == 2 then
                        if termUtil.cpY == 4 then
                            termUtil.cpX, termUtil.cpY = 5, 7
                        else
                            termUtil.cpX, termUtil.cpY = 5, 4
                        end
                    end
                    dirty = true
                elseif key == keys.space then
                    gui_cfg.loop_sel = (gui_cfg.loop_sel == "ON") and "OFF" or "ON"
                    dirty = true
                elseif key == keys.enter then
                    StartFromGui(); dirty = true
                end
            elseif type == "mouse_scroll" then
                if ev[2] == -1 then
                    gui_cfg.loop_sel = (gui_cfg.loop_sel == "ON") and "OFF" or "ON"; dirty = true
                elseif ev[2] == 1 then
                    gui_cfg.shuffle_sel = (gui_cfg.shuffle_sel == "ON") and "OFF" or "ON"; dirty = true
                end
            end

        elseif PAGE == "PLAY" then
            -- PLAY page events are handled by PlayWrapper's gui_ctrl_coro.
            -- Main loop here only redraws occasionally and returns to MENU
            -- when the "play_end" event is queued.
            if type == "play_end" then
                PAGE = "MENU"
                termUtil.cpX, termUtil.cpY = 1, 1
                dirty = true
            else
                sleep(0.05)
                dirty = true
            end
        end
    end
end

--[[==================  Playback parallel coroutines (original CLI-style)  ==================]]

local function gui_render_coro()
    while true do
        if gui_playing and PAGE == "PLAY" then
            RenderPlay()
        end
        sleep(0.25)
    end
end

local function gui_ctrl_coro()
    while true do
        if not (gui_playing and PAGE == "PLAY") then
            sleep(0.05)
        else
            local ev = {os.pullEvent("mouse_click", "char", "key")}
            if not (gui_playing and PAGE == "PLAY") then
                -- skip, playback ended mid-pull
            elseif ev[1] == "mouse_click" then
                local action = HitPlayButtons(ev[3], ev[4])
                if action == "prev" then
                    if gui_mode == 2 and i > 1 then i = i - 2 end
                    bytes_read = total_size
                elseif action == "stop" then
                    bytes_read = total_size
                    gui_loop_break_once = true
                elseif action == "next" then
                    bytes_read = total_size
                end
            elseif ev[1] == "char" then
                local c = ev[2]
                if c == "x" or c == "X" then
                    bytes_read = total_size
                    gui_loop_break_once = true
                elseif c == "<" or c == "," then
                    if gui_mode == 2 and i > 1 then i = i - 2 end
                    bytes_read = total_size
                elseif c == ">" or c == "." then
                    bytes_read = total_size
                end
            end
        end
    end
end

local function gui_play_coro()
    gui_loop_break_once = false
    local ok, err = pcall(PlayFlow)
    if not ok then
        GuiLog("[!] " .. tostring(err))
        sleep(1)
    end
end

--[[==================  Legacy CLI compatibility  ==================]]

local function HasCliArgs()
    local m = nil
    for index, value in ipairs(feature) do
        if arg[1] == value then m = index end
    end
    if m == nil then return false end
    if arg[2] == nil then return false end
    return true
end

if HasCliArgs() then
    for index, value in ipairs(feature) do
        if arg[1] == value then mode = index end
    end
    id = arg[2]
    for k, v in ipairs(arg) do
        for index, value in ipairs(playMode) do
            if v == value then
                if index == 2 then play = true end
            end
        end
        if v == "shuffle" then shuffle = true end
    end
    if mode == nil then
        print("Bad args")
        return
    end
    shell.run("clear")

    -- Map CLI mode into gui_mode and friends so PlayFlow works unchanged
    gui_mode = mode
    gui_cfg.input_id = id
    gui_cfg.loop_sel = play and "ON" or "OFF"
    gui_cfg.shuffle_sel = shuffle and "ON" or "OFF"
    gui_cfg.input_start = tonumber(arg[4]) or 1

    local cli_showControl = function()
        while true do
            if bytes_read > 1 then
                local posx, posy = term.getCursorPos()
                term.setCursorPos(1, termSizeY)
                write("            ")
                term.setCursorPos(1, termSizeY)
                write(("%ds/%ds"):format(math.floor((bytes_read * 8) / 48000), math.ceil(total_length)))
                if mode == 2 then
                    term.setCursorPos(termSizeX - 7, termSizeY - 2)
                    write("       ")
                    term.setCursorPos(termSizeX - 7, termSizeY - 1)
                    write("       ")
                    term.setCursorPos(termSizeX - 7, termSizeY)
                    write("|<|>|")
                end
                if posy > termSizeY - 3 then
                    term.scroll(4)
                    term.setCursorPos(posx, termSizeY - 4)
                    term.clearLine()
                    term.setCursorPos(posx, posy - 4)
                else
                    term.setCursorPos(posx, posy)
                end
                sleep(1)
            else
                sleep(0.05)
            end
        end
    end

    local cli_event = function()
        while true do
            if mode == 2 then
                local ev, button, x, y = os.pullEvent("mouse_click")
                if y == termSizeY then
                    if x < termSizeX and x > termSizeX - 3 then
                        bytes_read = total_size
                    elseif x < termSizeX - 3 and x > termSizeX - 7 then
                        if i > 1 then
                            i = i - 2
                            bytes_read = total_size
                        end
                    end
                end
            else
                sleep(0.05)
            end
        end
    end

    local cli_play = function()
        PlayFlow()
        os.queueEvent("cli_done")
    end

    parallel.waitForAny(cli_event, cli_play, cli_showControl)
    return
end

--[[==================  No args => enter GUI mode  ==================]]

shell.run("clear")
if not speaker then
    term.setTextColor(colors.red)
    print("No speaker!")
    term.setTextColor(colors.white)
    return
end

local function PlayWrapper()
    while true do
        if PAGE == "PLAY" and not gui_playing then
            gui_playing = true
            gui_loop_break_once = false
            local p = function()
                parallel.waitForAny(gui_play_coro, gui_ctrl_coro, gui_render_coro)
            end
            pcall(p)
            PAGE = "MENU"
            gui_playing = false
            os.queueEvent("play_end")
        else
            sleep(0.1)
        end
    end
end

parallel.waitForAny(GuiMainLoop, PlayWrapper)
