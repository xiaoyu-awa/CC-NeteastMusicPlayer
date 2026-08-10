local NeteastMusicApi = "http://frp-fly.com:12856"
local TransApi = "http://newgmapi.liulikeji.cn/api/ffmpeg"


local feature = {"id","lid","dfpwm"} --1=id 2=lid 3=dfpwm
local playMode = {"once","cycle"} --1=once 2=cycle

local mode
local id
local play = false
local shuffle = false

--[[==================  GUI 基础设施  ==================]]

local PAGE = "MENU"   -- MENU / INPUT / PLAY
local termSizeX, termSizeY = term.getSize()
local dfpwm = require("cc.audio.dfpwm")
local speaker = peripheral.find("speaker")
local decoder = dfpwm.make_decoder()

-- GUI 状态
local gui_input_id = ""
local gui_input_start = "1"
local gui_loop = false
local gui_shuffle = false
local gui_focus = "id"  -- 当前焦点输入框：id / start
local gui_mode = nil     -- 1/2/3，由菜单选择
local gui_play_stopped = false  -- 用户按下停止
local gui_playing = false       -- 播放协程正在运行（防止重复进入）
local gui_current_song_name = ""
local gui_log = {}  -- 播放日志（滚动显示）

local chunk_size = 6000
local bytes_read = 0
local total_length, total_size = 0, 0
local i = 1  -- 歌单切歌用

function GuiLog(msg)
    gui_log[#gui_log + 1] = msg
    if #gui_log > (termSizeY - 9) then
        table.remove(gui_log, 1)
    end
end

-- 命中测试
local function PointInRect(px, py, x, y, w, h)
    return px >= x and px < x + w and py >= y and py < y + h
end

-- 画填充矩形（用空格+背景色）
local function DrawRect(x, y, w, h, bg)
    term.setBackgroundColor(bg)
    local line = string.rep(" ", w)
    for yy = y, y + h - 1 do
        term.setCursorPos(x, yy)
        term.write(line)
    end
end

-- 画边框
local function DrawBorder(x, y, w, h, fg)
    term.setTextColor(fg)
    term.setBackgroundColor(colors.black)
    -- 顶/底
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

-- 画按钮（返回矩形数据供点击判定）
local function DrawButton(x, y, w, h, label, active)
    local bg = active and colors.lime or colors.gray
    local fg = colors.black
    DrawRect(x, y, w, h, bg)
    term.setTextColor(fg)
    term.setBackgroundColor(bg)
    local lx = x + math.floor((w - #label) / 2)
    local ly = y + math.floor(h / 2)
    term.setCursorPos(lx, ly)
    term.write(label)
    DrawBorder(x, y, w, h, colors.lightGray)
    return {x = x, y = y, w = w, h = h}
end

-- 画带标签的输入框
local function DrawInput(x, y, w, label, value, focused, placeholder)
    -- 标签
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.cyan)
    term.setCursorPos(x, y)
    term.write(label)
    -- 框
    local bg = focused and colors.yellow or colors.gray
    local fg = focused and colors.black or colors.white
    DrawRect(x, y + 1, w, 3, bg)
    DrawBorder(x, y + 1, w, 3, focused and colors.orange or colors.lightGray)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    term.setCursorPos(x + 1, y + 2)
    if #value == 0 and placeholder then
        term.setTextColor(colors.lightGray)
        term.write(placeholder:sub(1, w - 2))
    else
        local display = value
        if #display > w - 2 then
            display = display:sub(#display - (w - 3), -1)
        end
        term.write(display)
        if focused then
            term.setTextColor(colors.red)
            term.write("_")
        end
    end
end

-- 画复选框
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

-- 画进度条
local function DrawProgressBar(x, y, w, percent)
    percent = math.max(0, math.min(1, percent))
    DrawRect(x, y, w, 1, colors.gray)
    local filled = math.floor(percent * w)
    if filled > 0 then
        DrawRect(x, y, filled, 1, colors.green)
    end
    term.setBackgroundColor(colors.black)
end

-- 画页面标题
local function DrawTitle(text)
    DrawRect(1, 1, termSizeX, 2, colors.blue)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.yellow)
    term.setCursorPos(math.floor((termSizeX - #text) / 2), 2)
    term.write(text)
end

--[[==================  业务工具函数  ==================]]

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
        return detail.songs[1].name or ("ID:" .. music_id)
    end
    return "ID:" .. music_id
end

--[[==================  播放核心（改造版）  ==================]]

local function PlayMusicCore(url)
    bytes_read = 0
    local function get_total_duration(u)
        local handle, err = http.get(u)
        if not handle then
            error("Could not get duration: " .. (err or "Unknown error"))
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
                -- 等待最多 0.5s，避免卡死错过停止信号
                os.startTimer(0.1)
                local ev, p1 = os.pullEvent()
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

-- 实际播放流程
local function PlayFlow()
    bytes_read = 0
    total_length = 0
    total_size = 0
    gui_play_stopped = false

    if gui_mode == 1 then  -- 单曲
        local mid = (mode == 1 and id) or gui_input_id
        GuiLog("获取音乐: " .. mid)
        gui_current_song_name = GetSongName(mid)
        local url = GetMusicUrl(mid)
        local count = 1
        repeat
            GuiLog("播放 #" .. count .. ": " .. gui_current_song_name)
            PlayMusicCore(url)
            count = count + 1
        until (not gui_loop) or gui_play_stopped
        if gui_play_stopped then
            GuiLog("用户停止")
        else
            GuiLog("播放完成")
        end

    elseif gui_mode == 2 then  -- 歌单
        local pid = (mode == 2 and id) or gui_input_id
        GuiLog("加载歌单: " .. pid)
        local data = http.get(NeteastMusicApi .. "/playlist/detail?s=0&id=" .. pid).readAll()
        local musicList = textutils.unserialiseJSON(data)
        local List = musicList["playlist"]["tracks"]
        local idList = {}
        for index, value in pairs(List) do
            idList[#idList + 1] = value["id"]
        end
        GuiLog("歌单共 " .. #idList .. " 首" .. (gui_shuffle and "（随机）" or ""))

        local startIdx = tonumber(gui_input_start) or 1
        local loopCount = 1
        repeat
            if gui_shuffle then ShuffleArray(idList) end
            i = math.max(1, math.min(startIdx, #idList))
            startIdx = 1
            GuiLog("轮次 " .. loopCount .. "，从第 " .. i .. " 首开始")
            while not (i > #idList) and not gui_play_stopped do
                local mid = idList[i]
                gui_current_song_name = GetSongName(mid)
                GuiLog(string.format("[%d/%d] %s", i, #idList, gui_current_song_name))
                local ok, url = pcall(GetMusicUrl, mid)
                if ok and url then
                    PlayMusicCore(url)
                else
                    GuiLog("获取失败，跳过")
                end
                i = i + 1
            end
            loopCount = loopCount + 1
        until (not gui_loop) or gui_play_stopped
        GuiLog(gui_play_stopped and "用户停止" or "播放完成")

    elseif gui_mode == 3 then  -- 本地 DFPWM
        local fn = (mode == 3 and id) or gui_input_id
        GuiLog("本地文件: " .. fn)
        gui_current_song_name = fn
        local loopCount = 1
        repeat
            GuiLog("播放 #" .. loopCount)
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
                GuiLog("无法打开文件")
                sleep(1)
                break
            end
            loopCount = loopCount + 1
        until (not gui_loop) or gui_play_stopped
        GuiLog(gui_play_stopped and "用户停止" or "播放完成")
    end
end

--[[==================  页面渲染  ==================]]

local function RenderMenu()
    term.clear()
    term.setBackgroundColor(colors.black)
    DrawTitle("   ~ 网易云音乐播放器 ~")
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    term.setCursorPos(2, 4)
    term.write("请选择播放模式：")
    local bw = termSizeX - 8
    DrawButton(4, 6, bw, 3, "[1] 单曲播放（ID）", false)
    DrawButton(4, 10, bw, 3, "[2] 歌单播放（ID）", false)
    DrawButton(4, 14, bw, 3, "[3] 本地 DFPWM 文件", false)
    -- 底部提示
    term.setCursorPos(2, termSizeY - 1)
    term.setTextColor(colors.lightGray)
    term.write("点击按钮或按 1/2/3 键")
    term.setCursorPos(2, termSizeY)
    term.write("或使用命令行: play id <id> cycle shuffle")
end

local function RenderInput()
    term.clear()
    local title = "参数设置 - " .. (gui_mode == 1 and "单曲" or gui_mode == 2 and "歌单" or "本地DFPWM")
    DrawTitle(title)
    -- ID 输入框
    local ph = gui_mode == 3 and "例如: music.dfpwm" or "例如: 33894312"
    DrawInput(3, 4, termSizeX - 6, "ID / 文件名：", gui_input_id, gui_focus == "id", ph)
    -- 起始序号（歌单模式才显示）
    if gui_mode == 2 then
        DrawInput(3, 8, 10, "起始序号：", gui_input_start, gui_focus == "start", "1")
    end
    -- 复选框
    local cy = gui_mode == 2 and 13 or 9
    DrawCheckbox(3, cy, "循环播放", gui_loop)
    DrawCheckbox(3, cy + 1, "随机播放（仅歌单有效）", gui_shuffle)
    -- 按钮
    local bw = math.floor((termSizeX - 8) / 2)
    DrawButton(3, termSizeY - 4, bw, 3, "[B] 返回", false)
    DrawButton(5 + bw, termSizeY - 4, bw, 3, "[ENTER] 开始播放", true)
    -- 提示
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    term.setCursorPos(2, termSizeY)
    term.write("Tab 切换输入框, 空格打勾, 字母键点击")
end

local function RenderPlay()
    term.clear()
    DrawTitle("  播放中  |  " .. (gui_loop and "[循环] " or "") .. (gui_shuffle and "[随机]" or ""))

    -- 歌曲名
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    term.setCursorPos(2, 4)
    local name = gui_current_song_name
    if #name > termSizeX - 4 then name = name:sub(1, termSizeX - 7) .. "..." end
    term.write(name)

    -- 进度条
    local percent = 0
    if total_size and total_size > 0 then
        percent = bytes_read / total_size
    end
    DrawProgressBar(2, 6, termSizeX - 3, percent)
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    local cur = 0
    local tot = total_length or 0
    if total_size and total_size > 0 then
        cur = (bytes_read * 8) / 48000
    end
    term.setCursorPos(2, 7)
    term.write(string.format("%ds / %ds   进度 %d%%",
        math.floor(cur), math.ceil(tot), math.floor(percent * 100)))

    -- 控制按钮（歌单显示上下首）
    local bw = math.floor((termSizeX - 8) / 3)
    if gui_mode == 2 then
        DrawButton(2, 9, bw, 3, "[<] 上一首", false)
        DrawButton(3 + bw, 9, bw, 3, "[X] 停止", true)
        DrawButton(4 + 2 * bw, 9, bw, 3, "[>] 下一首", false)
    else
        local stopW = termSizeX - 10
        DrawButton(5, 9, stopW, 3, "[X] 停止并返回", true)
    end

    -- 日志区域
    local logY = 12
    local logH = termSizeY - logY - 1
    DrawRect(2, logY - 1, termSizeX - 3, 1, colors.gray)
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.gray)
    term.setCursorPos(2, logY - 1)
    term.write(" 播放日志 ")
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    for idx = 1, logH do
        term.setCursorPos(2, logY + idx - 1)
        term.clearLine()
        local line = gui_log[#gui_log - (logH - idx)]
        if line then
            if #line > termSizeX - 4 then line = line:sub(1, termSizeX - 7) .. "..." end
            term.write(line)
        end
    end
end

--[[==================  事件分发  ==================]]

-- 菜单点击
local function HandleMenuClick(x, y)
    local bw = termSizeX - 8
    if PointInRect(x, y, 4, 6, bw, 3) then
        gui_mode = 1
        gui_input_id = ""
        gui_input_start = "1"
        PAGE = "INPUT"
    elseif PointInRect(x, y, 4, 10, bw, 3) then
        gui_mode = 2
        gui_input_id = ""
        gui_input_start = "1"
        PAGE = "INPUT"
    elseif PointInRect(x, y, 4, 14, bw, 3) then
        gui_mode = 3
        gui_input_id = ""
        PAGE = "INPUT"
    end
end

-- 输入页点击
local function HandleInputClick(x, y)
    -- 焦点切换
    if PointInRect(x, y, 3, 5, termSizeX - 6, 3) then
        gui_focus = "id"
    elseif gui_mode == 2 and PointInRect(x, y, 3, 9, 10, 3) then
        gui_focus = "start"
    end
    -- 复选框
    local cy = gui_mode == 2 and 13 or 9
    if PointInRect(x, y, 3, cy, 12, 1) then
        gui_loop = not gui_loop
    end
    if PointInRect(x, y, 3, cy + 1, 28, 1) then
        gui_shuffle = not gui_shuffle
    end
    -- 按钮
    local bw = math.floor((termSizeX - 8) / 2)
    if PointInRect(x, y, 3, termSizeY - 4, bw, 3) then
        PAGE = "MENU"
    elseif PointInRect(x, y, 5 + bw, termSizeY - 4, bw, 3) then
        StartFromGui()
    end
end

-- 播放页点击
local function HandlePlayClick(x, y)
    local bw = math.floor((termSizeX - 8) / 3)
    if gui_mode == 2 then
        if PointInRect(x, y, 2, 9, bw, 3) then
            -- 上一首
            if i > 1 then i = i - 2 end
            bytes_read = total_size
        elseif PointInRect(x, y, 3 + bw, 9, bw, 3) then
            -- 停止
            gui_play_stopped = true
        elseif PointInRect(x, y, 4 + 2 * bw, 9, bw, 3) then
            -- 下一首
            bytes_read = total_size
        end
    else
        local stopW = termSizeX - 10
        if PointInRect(x, y, 5, 9, stopW, 3) then
            gui_play_stopped = true
        end
    end
end

--[[==================  GUI 启动播放  ==================]]

function StartFromGui()
    -- 同步到全局变量
    mode = gui_mode
    id = gui_input_id
    play = gui_loop
    shuffle = gui_shuffle
    -- 歌单模式起始序号写回 arg[4]（兼容旧逻辑）
    if gui_mode == 2 then
        arg[4] = gui_input_start
    end
    gui_log = {}
    gui_playing = false
    PAGE = "PLAY"
end

--[[==================  主事件循环  ==================]]

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
                HandleMenuClick(ev[3], ev[4])
                dirty = true
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
                HandleInputClick(ev[3], ev[4])
                dirty = true
            elseif type == "char" then
                local c = ev[2]
                if c == "b" or c == "B" then
                    PAGE = "MENU"; dirty = true
                elseif gui_focus == "id" then
                    gui_input_id = gui_input_id .. c
                    dirty = true
                elseif gui_focus == "start" then
                    if c >= "0" and c <= "9" then
                        gui_input_start = gui_input_start .. c
                        dirty = true
                    end
                end
            elseif type == "key" then
                local key = ev[2]
                if key == keys.backspace then
                    if gui_focus == "id" then
                        gui_input_id = gui_input_id:sub(1, -2)
                    elseif gui_focus == "start" then
                        gui_input_start = gui_input_start:sub(1, -2)
                    end
                    dirty = true
                elseif key == keys.tab then
                    if gui_mode == 2 then
                        gui_focus = (gui_focus == "id") and "start" or "id"
                    end
                    dirty = true
                elseif key == keys.space then
                    -- 打勾：先循环，再随机
                    if gui_focus == "id" or gui_focus == "start" then
                        -- noop
                    else
                        gui_loop = not gui_loop; dirty = true
                    end
                    dirty = true
                elseif key == keys.enter then
                    StartFromGui()
                    dirty = true
                elseif key == keys.backspace and (gui_input_id == "" and gui_input_start == "") then
                    PAGE = "MENU"; dirty = true
                end
            elseif type == "mouse_scroll" then
                -- 空格打勾切换
                if ev[2] == -1 then gui_loop = not gui_loop; dirty = true
                elseif ev[2] == 1 then gui_shuffle = not gui_shuffle; dirty = true
                end
            end

        elseif PAGE == "PLAY" then
            if type == "mouse_click" then
                HandlePlayClick(ev[3], ev[4])
                dirty = true
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
                dirty = true  -- 刷新进度
            elseif type == "play_end" then
                PAGE = "MENU"
                dirty = true
            else
                dirty = true  -- 其他事件也刷新 UI（日志区）
            end
        end
    end
end

--[[==================  兼容旧命令行  ==================]]

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
    -- 命令行模式：沿用旧逻辑
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
        print("Error arguments")
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
                write(("%ds / %ds"):format(math.floor((bytes_read * 8) / 48000), math.ceil(total_length)))
                if mode == 2 then
                    term.setCursorPos(termSizeX - 8, termSizeY - 2)
                    write("         ")
                    term.setCursorPos(termSizeX - 8, termSizeY - 1)
                    write("         ")
                    term.setCursorPos(termSizeX - 8, termSizeY)
                    write("| < | > |")
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
                    if x < termSizeX and x > termSizeX - 4 then
                        bytes_read = total_size
                    elseif x < termSizeX - 4 and x > termSizeX - 8 then
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

    -- 用 GUI 的 PlayFlow（但要先同步 gui_mode 等）
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

--[[==================  无参数，进入 GUI 模式  ==================]]

shell.run("clear")
if not speaker then
    term.setTextColor(colors.red)
    print("错误: 未找到 speaker 外设！请连接扬声器。")
    term.setTextColor(colors.white)
    return
end

-- GUI 模式：UI 循环 + 播放协程 并行
local function PlayWrapper()
    while true do
        if PAGE == "PLAY" and not gui_playing then
            gui_playing = true
            local ok, err = pcall(PlayFlow)
            if not ok then
                GuiLog("[错误] " .. tostring(err))
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
