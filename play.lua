local NeteastMusicApi = "http://frp-fly.com:12856"
local TransApi = "http://newgmapi.liulikeji.cn/api/ffmpeg"


local feature = {"id","lid","dfpwm"} --1=id 2=lid 3=dfpwm
local playMode = {"once","cycle"} --1=once 2=cycle

local mode
local id
local play = false
local shuffle = false

--[[==================  GUI Infrastructure  ==================]]

local PAGE = "MENU"   -- MENU / INPUT / PLAY
local termSizeX, termSizeY = term.getSize()
local dfpwm = require("cc.audio.dfpwm")
local speaker = peripheral.find("speaker")
local decoder = dfpwm.make_decoder()

-- GUI state
local gui_input_id = ""
local gui_input_start = "1"
local gui_loop = false
local gui_shuffle = false
local gui_focus = "id"  -- current focused input: id / start
local gui_mode = nil     -- 1/2/3, selected from menu
local gui_play_stopped = false  -- user pressed stop
local gui_playing = false       -- play coroutine running (prevent reentry)
local gui_current_song_name = ""
local gui_log = {}  -- scrollable playback log

local chunk_size = 6000
local bytes_read = 0
local total_length, total_size = 0, 0
local i = 1  -- playlist seek index

function GuiLog(msg)
    gui_log[#gui_log + 1] = msg
    if #gui_log > (termSizeY - 9) then
        table.remove(gui_log, 1)
    end
end

-- Hit test
local function PointInRect(px, py, x, y, w, h)
    return px >= x and px < x + w and py >= y and py < y + h
end

-- Filled rect (spaces + bg color)
local function DrawRect(x, y, w, h, bg)
    term.setBackgroundColor(bg)
    local line = string.rep(" ", w)
    for yy = y, y + h - 1 do
        term.setCursorPos(x, yy)
        term.write(line)
    end
end

-- Border box
local function DrawBorder(x, y, w, h, fg)
    if w < 2 or h < 2 then return end
    term.setTextColor(fg)
    term.setBackgroundColor(colors.black)
    term.setCursorPos(x, y)
    term.write(string.char(151) .. string.rep(string.char(131), w - 2) .. string.char(148))
    for yy = y + 1, y + h - 2 do
        term.setCursorPos(x, yy)
        term.write(string.char(149))
        term.setCursorPos(x + w - 1, yy)
        term.write(string.char(149))
    end
    term.setCursorPos(x, y + h - 1)
    term.write(string.char(138) .. string.rep(string.char(131), w - 2) .. string.char(133))
end

-- Button (compact, returns rect for hit test)
local function DrawButton(x, y, w, h, label, active)
    local bg = active and colors.lime or colors.gray
    local fg = colors.black
    DrawRect(x, y, w, h, bg)
    term.setTextColor(fg)
    term.setBackgroundColor(bg)
    local ll = #label
    local lx = x + math.max(0, math.floor((w - ll) / 2))
    local ly = y + math.floor(h / 2)
    term.setCursorPos(lx, ly)
    if ll > w then ll = w end
    term.write(label:sub(1, ll))
    DrawBorder(x, y, w, h, colors.lightGray)
    return {x = x, y = y, w = w, h = h}
end

-- Labeled input box (compact)
local function DrawInput(x, y, w, label, value, focused, placeholder)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.cyan)
    term.setCursorPos(x, y)
    term.write(label)
    local bg = focused and colors.yellow or colors.gray
    local fg = focused and colors.black or colors.white
    DrawRect(x, y + 1, w, 3, bg)
    DrawBorder(x, y + 1, w, 3, focused and colors.orange or colors.lightGray)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    term.setCursorPos(x + 1, y + 2)
    local maxIn = math.max(1, w - 2)
    if #value == 0 and placeholder then
        term.setTextColor(colors.lightGray)
        term.write(placeholder:sub(1, maxIn))
    else
        local display = value
        if #display > maxIn then
            display = display:sub(#display - maxIn + 1, -1)
        end
        term.write(display)
        if focused then
            term.setTextColor(colors.red)
            if #display < maxIn then term.write("_") end
        end
    end
end

-- Checkbox (short label)
local function DrawCheckbox(x, y, label, checked)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.setCursorPos(x, y)
    term.write("[")
    term.setTextColor(checked and colors.lime or colors.gray)
    term.write(checked and "X" or " ")
    term.setTextColor(colors.white)
    term.write("] " .. label)
end

-- Progress bar
local function DrawProgressBar(x, y, w, percent)
    percent = math.max(0, math.min(1, percent))
    DrawRect(x, y, w, 1, colors.gray)
    local filled = math.floor(percent * w)
    if filled > 0 then
        DrawRect(x, y, filled, 1, colors.green)
    end
    term.setBackgroundColor(colors.black)
end

-- Page title bar (compact, 1 line instead of 2)
local function DrawTitle(text)
    DrawRect(1, 1, termSizeX, 1, colors.blue)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.yellow)
    local t = text:sub(1, termSizeX)
    term.setCursorPos(math.max(1, math.floor((termSizeX - #t) / 2)), 1)
    term.write(t)
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

--[[==================  Playback core (refactored)  ==================]]

local function PlayMusicCore(url)
    bytes_read = 0
    local function get_total_duration(u)
        local handle, err = http.get(u)
        if not handle then
            error("No duration: " .. (err or "?"))
        end
        local d = handle.readAll()
        handle.close()
        local totalLength = (#d * 8) / 48000
        return totalLength, #d
    end
    if url then
        total_length, total_size = get_total_duration(url)
    end
    local file = http.get(url)
    while bytes_read < total_size and not gui_play_stopped do
        local chunk
        if file then
            chunk = file.read(chunk_size)
        end
        local buffer
        if chunk and #chunk > 0 then
            buffer = decoder(chunk)
        end
        if buffer and #buffer > 0 then
            local t0 = os.clock()
            while not speaker.playAudio(buffer) and not gui_play_stopped do
                os.startTimer(0.1)
                local ev = os.pullEvent()
                if ev == "timer" then
                    if os.clock() - t0 > 2 then break end
                elseif ev == "speaker_audio_empty" then
                    break
                end
            end
        end
        bytes_read = bytes_read + chunk_size
    end
    if file then file.close() end
end

-- Actual playback flow dispatcher (compact log strings)
local function PlayFlow()
    bytes_read = 0
    total_length = 0
    total_size = 0
    gui_play_stopped = false

    if gui_mode == 1 then  -- Single track
        local mid = (mode == 1 and id) or gui_input_id
        GuiLog("Get: " .. mid)
        gui_current_song_name = GetSongName(mid)
        local url = GetMusicUrl(mid)
        local count = 1
        repeat
            GuiLog("#" .. count .. " " .. gui_current_song_name)
            PlayMusicCore(url)
            count = count + 1
        until (not gui_loop) or gui_play_stopped
        GuiLog(gui_play_stopped and "Stopped" or "Done")

    elseif gui_mode == 2 then  -- Playlist
        local pid = (mode == 2 and id) or gui_input_id
        GuiLog("List: " .. pid)
        local data = http.get(NeteastMusicApi .. "/playlist/detail?s=0&id=" .. pid).readAll()
        local musicList = textutils.unserialiseJSON(data)
        local List = musicList["playlist"]["tracks"]
        local idList = {}
        for index, value in pairs(List) do
            idList[#idList + 1] = value["id"]
        end
        GuiLog(tostring(#idList) .. " trk" .. (gui_shuffle and " RND" or ""))

        local startIdx = tonumber(gui_input_start) or 1
        local loopCount = 1
        repeat
            if gui_shuffle then ShuffleArray(idList) end
            i = math.max(1, math.min(startIdx, #idList))
            startIdx = 1
            GuiLog("Lp" .. loopCount .. " @" .. "#" .. i)
            while not (i > #idList) and not gui_play_stopped do
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
        until (not gui_loop) or gui_play_stopped
        GuiLog(gui_play_stopped and "Stopped" or "Done")

    elseif gui_mode == 3 then  -- Local DFPWM file
        local fn = (mode == 3 and id) or gui_input_id
        GuiLog("File: " .. fn)
        gui_current_song_name = fn
        local loopCount = 1
        repeat
            GuiLog("#" .. loopCount)
            bytes_read = 0
            local f = io.open(fn, "rb")
            if f then
                local all = f:read("*a")
                f:close()
                total_size = #all
                total_length = (total_size * 8) / 48000
                local pos = 1
                while pos < total_size and not gui_play_stopped do
                    local chunk = all:sub(pos, pos + chunk_size - 1)
                    pos = pos + chunk_size
                    bytes_read = bytes_read + chunk_size
                    local buffer = decoder(chunk)
                    if buffer and #buffer > 0 then
                        while not speaker.playAudio(buffer) and not gui_play_stopped do
                            os.startTimer(0.1)
                            local ev = os.pullEvent()
                            if ev == "speaker_audio_empty" then break end
                        end
                    end
                end
            else
                GuiLog("File ERR")
                sleep(1)
                break
            end
            loopCount = loopCount + 1
        until (not gui_loop) or gui_play_stopped
        GuiLog(gui_play_stopped and "Stopped" or "Done")
    end
end

--[[==================  Page renderers (COMPACT for 26x20 pocket)  ==================]]

local function RenderMenu()
    term.clear()
    term.setBackgroundColor(colors.black)
    DrawTitle("<< Netease Player >>")
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    term.setCursorPos(2, 3)
    term.write("Pick mode:")
    local bw = termSizeX - 4
    DrawButton(2, 4, bw, 3, "1 Single", false)
    DrawButton(2, 8, bw, 3, "2 Playlist", false)
    DrawButton(2, 12, bw, 3, "3 Local DFPWM", false)
    term.setCursorPos(2, termSizeY - 1)
    term.setTextColor(colors.lightGray)
    term.write("Click or 1/2/3")
    term.setCursorPos(2, termSizeY)
    term.write("CLI: play id <id>")
end

local function RenderInput()
    term.clear()
    local sub = gui_mode == 1 and "Single" or gui_mode == 2 and "List" or "File"
    DrawTitle("Setup: " .. sub)

    -- ID input: box takes most width
    local boxW = termSizeX - 4
    DrawInput(2, 3, boxW, "ID/Path:", gui_input_id, gui_focus == "id",
              gui_mode == 3 and "song.dfpwm" or "33894312")

    -- Start index: only for playlist, compact inline
    local cy = 7
    if gui_mode == 2 then
        DrawInput(2, 7, 8, "Start #:", gui_input_start, gui_focus == "start", "1")
        cy = 11
    end

    DrawCheckbox(2, cy, "Loop", gui_loop)
    DrawCheckbox(2, cy + 1, "Shuffle", gui_shuffle)

    -- Two buttons at bottom
    local bw = math.floor((termSizeX - 4) / 2)
    local by = termSizeY - 3
    DrawButton(2, by, bw, 3, "B Back", false)
    DrawButton(3 + bw, by, bw, 3, "E Play", true)

    -- Hint at very bottom, 1 line
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    term.setCursorPos(2, termSizeY)
    term.write("Tab=sw Spc=ok Ent=go")
end

local function RenderPlay()
    term.clear()
    -- Title with flags: L=Loop S=Shuffle
    local flags = ""
    if gui_loop then flags = flags .. "L" end
    if gui_shuffle then flags = flags .. "S" end
    local title = "PLAY"
    if #flags > 0 then title = title .. " [" .. flags .. "]" end
    DrawTitle(title)

    -- Song name (short): line 2
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    term.setCursorPos(1, 2)
    term.clearLine()
    local name = gui_current_song_name
    if #name > termSizeX then name = name:sub(1, termSizeX - 3) .. "..." end
    term.setCursorPos(math.max(1, math.floor((termSizeX - #name) / 2)), 2)
    term.write(name)

    -- Progress bar: line 3
    local pw = termSizeX - 2
    local percent = 0
    if total_size and total_size > 0 then
        percent = bytes_read / total_size
    end
    DrawProgressBar(1, 3, pw, percent)

    -- Time text: line 4 (short format)
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    local cur = 0
    local tot = total_length or 0
    if total_size and total_size > 0 then
        cur = (bytes_read * 8) / 48000
    end
    term.setCursorPos(1, 4)
    term.clearLine()
    local timeStr = tostring(math.floor(cur)) .. "s/" .. tostring(math.ceil(tot)) .. "s "
    local pctStr = tostring(math.floor(percent * 100)) .. "%"
    local info = timeStr .. pctStr
    term.setCursorPos(math.max(1, math.floor((termSizeX - #info) / 2)), 4)
    term.write(info)

    -- Control buttons: line 5-7 (h=3)
    if gui_mode == 2 then
        -- 3 equal buttons
        local gap = 1
        local totalW = termSizeX - 2
        local bw = math.floor((totalW - 2 * gap) / 3)
        DrawButton(1, 5, bw, 3, "<Prev", false)
        DrawButton(1 + bw + gap, 5, bw, 3, "Stop", true)
        DrawButton(1 + 2 * (bw + gap), 5, bw, 3, "Next>", false)
    else
        DrawButton(1, 5, termSizeX, 3, "STOP (X)", true)
    end

    -- Log header + log region: starts line 9 to end (termSizeY line reserved)
    local logY = 9
    local logH = termSizeY - logY
    if logH < 2 then logH = 2 end
    -- Log header (tiny)
    DrawRect(1, logY - 1, termSizeX, 1, colors.gray)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.setCursorPos(1, logY - 1)
    term.write(" Log")
    -- Log lines (truncate heavily)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    for idx = 1, logH do
        term.setCursorPos(1, logY + idx - 1)
        term.clearLine()
        local line = gui_log[#gui_log - (logH - idx)]
        if line then
            if #line > termSizeX then line = line:sub(1, termSizeX - 3) .. ".." end
            term.write(line)
        end
    end
end

--[[==================  Event dispatchers  ==================]]

local function HandleMenuClick(x, y)
    local bw = termSizeX - 4
    if PointInRect(x, y, 2, 4, bw, 3) then
        gui_mode = 1; gui_input_id = ""; gui_input_start = "1"; PAGE = "INPUT"
    elseif PointInRect(x, y, 2, 8, bw, 3) then
        gui_mode = 2; gui_input_id = ""; gui_input_start = "1"; PAGE = "INPUT"
    elseif PointInRect(x, y, 2, 12, bw, 3) then
        gui_mode = 3; gui_input_id = ""; PAGE = "INPUT"
    end
end

local function HandleInputClick(x, y)
    local boxW = termSizeX - 4
    if PointInRect(x, y, 2, 4, boxW, 3) then
        gui_focus = "id"
    elseif gui_mode == 2 and PointInRect(x, y, 2, 8, 8, 3) then
        gui_focus = "start"
    end
    -- Checkboxes (y depends on mode)
    local cy = gui_mode == 2 and 11 or 7
    if y == cy and x >= 2 and x <= 10 then
        gui_loop = not gui_loop
    elseif y == cy + 1 and x >= 2 and x <= 12 then
        gui_shuffle = not gui_shuffle
    end
    -- Buttons at bottom
    local bw = math.floor((termSizeX - 4) / 2)
    local by = termSizeY - 3
    if PointInRect(x, y, 2, by, bw, 3) then
        PAGE = "MENU"
    elseif PointInRect(x, y, 3 + bw, by, bw, 3) then
        StartFromGui()
    end
end

local function HandlePlayClick(x, y)
    if gui_mode == 2 then
        local gap = 1
        local totalW = termSizeX - 2
        local bw = math.floor((totalW - 2 * gap) / 3)
        if PointInRect(x, y, 1, 5, bw, 3) then
            if i > 1 then i = i - 2 end
            bytes_read = total_size
        elseif PointInRect(x, y, 1 + bw + gap, 5, bw, 3) then
            gui_play_stopped = true
        elseif PointInRect(x, y, 1 + 2 * (bw + gap), 5, bw, 3) then
            bytes_read = total_size
        end
    else
        if PointInRect(x, y, 1, 5, termSizeX, 3) then
            gui_play_stopped = true
        end
    end
end

--[[==================  Start playback from GUI  ==================]]

function StartFromGui()
    mode = gui_mode
    id = gui_input_id
    play = gui_loop
    shuffle = gui_shuffle
    if gui_mode == 2 then
        arg[4] = gui_input_start
    end
    gui_log = {}
    gui_playing = false
    PAGE = "PLAY"
end

--[[==================  Main event loop  ==================]]

local function GuiMainLoop()
    local dirty = true
    while true do
        if dirty then
            if PAGE == "MENU" then
                RenderMenu()
            elseif PAGE == "INPUT" then
                RenderInput()
            elseif PAGE == "PLAY" then
                RenderPlay()
            end
            dirty = false
        end
        local ev = {os.pullEvent()}
        local type = ev[1]

        if PAGE == "MENU" then
            if type == "mouse_click" then
                HandleMenuClick(ev[3], ev[4]); dirty = true
            elseif type == "char" then
                local c = ev[2]
                if c == "1" then gui_mode = 1; PAGE = "INPUT"; dirty = true
                elseif c == "2" then gui_mode = 2; PAGE = "INPUT"; dirty = true
                elseif c == "3" then gui_mode = 3; PAGE = "INPUT"; dirty = true
                end
            elseif type == "key" and ev[2] == keys.backspace then
                return
            end

        elseif PAGE == "INPUT" then
            if type == "mouse_click" then
                HandleInputClick(ev[3], ev[4]); dirty = true
            elseif type == "char" then
                local c = ev[2]
                if c == "b" or c == "B" then
                    PAGE = "MENU"; dirty = true
                elseif gui_focus == "id" then
                    gui_input_id = gui_input_id .. c; dirty = true
                elseif gui_focus == "start" then
                    if c >= "0" and c <= "9" then
                        gui_input_start = gui_input_start .. c; dirty = true
                    end
                end
            elseif type == "key" then
                local key = ev[2]
                if key == keys.backspace then
                    if gui_focus == "id" then gui_input_id = gui_input_id:sub(1, -2)
                    elseif gui_focus == "start" then gui_input_start = gui_input_start:sub(1, -2) end
                    dirty = true
                elseif key == keys.tab then
                    if gui_mode == 2 then
                        gui_focus = (gui_focus == "id") and "start" or "id"
                    end
                    dirty = true
                elseif key == keys.space then
                    gui_loop = not gui_loop; dirty = true
                elseif key == keys.enter then
                    StartFromGui(); dirty = true
                end
            elseif type == "mouse_scroll" then
                if ev[2] == -1 then gui_loop = not gui_loop; dirty = true
                elseif ev[2] == 1 then gui_shuffle = not gui_shuffle; dirty = true
                end
            end

        elseif PAGE == "PLAY" then
            if type == "mouse_click" then
                HandlePlayClick(ev[3], ev[4]); dirty = true
            elseif type == "char" then
                local c = ev[2]
                if c == "x" or c == "X" then
                    gui_play_stopped = true; dirty = true
                elseif c == "<" or c == "," then
                    if gui_mode == 2 and i > 1 then i = i - 2 end
                    bytes_read = total_size; dirty = true
                elseif c == ">" or c == "." then
                    bytes_read = total_size; dirty = true
                end
            elseif type == "timer" or type == "speaker_audio_empty" then
                dirty = true
            elseif type == "play_end" then
                PAGE = "MENU"; dirty = true
            else
                dirty = true
            end
        end
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

    gui_mode = mode
    gui_input_id = id
    gui_loop = play
    gui_shuffle = shuffle
    gui_input_start = arg[4] and tostring(arg[4]) or "1"

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

-- GUI mode: UI loop + playback coroutine run in parallel
local function PlayWrapper()
    while true do
        if PAGE == "PLAY" and not gui_playing then
            gui_playing = true
            local ok, err = pcall(PlayFlow)
            if not ok then
                GuiLog("[!] " .. tostring(err))
                sleep(1)
            end
            PAGE = "MENU"
            gui_playing = false
            os.queueEvent("play_end")
        else
            sleep(0.1)
        end
    end
end

parallel.waitForAny(GuiMainLoop, PlayWrapper)
