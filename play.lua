local NeteastMusicApi = "http://music168.liulikeji.cn:15843/"
local TransApi = "http://newgmapi.liulikeji.cn/api/ffmpeg"


local feature = {"id","lid","dfpwm"} --1=id 2=lid 3=dfpwm
local playMode = {"once","cycle"} --1=once 2=cycle

local mode
local id
local play = false

shell.run("clear")
--init vars
if arg[1]==nil then
    print("play [id/lid/dfpwm] [id] {once/cycle}")
    print(" id/uid: select musicid or playlist id")
    print(" id: the id of music or playlist | filename when using dfpwm mode")
    print(" once/cycle: play mode(default:once)")
end

for index, value in ipairs(feature) do
    if arg[1]==value then
        mode=index
    end
end
id = arg[2]
for index, value in ipairs(playMode) do
    if arg[3]==value then
        if index==2 then
            play=true
        end
    end
end
if mode==nil then
    print("Error arguments")
    return
end

local i = 1 --歌单模式切歌用
local termSizeX, termSizeY = term.getSize()
local dfpwm = require("cc.audio.dfpwm")
local speaker = peripheral.find("speaker")
local decoder = dfpwm.make_decoder()
-- end init


function GetMusicUrl(music_id)
    local getMusic="/api/song/url?id="..music_id

    local data = http.get(NeteastMusicApi..getMusic).readAll()
    local music_get = textutils.unserialiseJSON(data)
    local musicUrl=music_get["data"][1]["url"]

    local json = {
        input_url = musicUrl,
        args = { "-vn", "-ar", "48000", "-ac", "1" },
        output_format = "dfpwm"
    }
    local response = http.post(TransApi,textutils.serializeJSON(json),{ ["Content-Type"] = "application/json" })
    data = textutils.unserializeJSON(response.readAll())

    return data["download_url"]
end

local chunk_size = 6000
local bytes_read = 0
local total_length, total_size =0,0
function PlayMusic(url)
    bytes_read = 0
    local function get_total_duration(url)
        local handle, err = http.get(url)
        if not handle then
            error("Could not get duration: " .. (err or "Unknown error"))
        end
        
        local data = handle.readAll()
        handle.close()
        
        local totalLength = (#data * 8) / 48000
        return totalLength, #data
    end


    if url then
        total_length, total_size = get_total_duration(url)
    end

    local file = http.get(url)
    while bytes_read < total_size do
        local chunk
        if file then
            chunk = file.read(chunk_size)
        end
        local buffer
        if chunk and #chunk > 0 then
            buffer = decoder(chunk)
        end

        if buffer and #buffer > 0 then
            while not speaker.playAudio(buffer) do
                os.pullEvent("speaker_audio_empty")
            end
        end
        bytes_read = bytes_read+chunk_size
    end
end

local playMusic = function ()
    if mode==1 then
        local url =GetMusicUrl(id)

        if play then
            print("play in loop mode")
            local count = 1
            while play do
                print("loop count:"..tostring(count))
                PlayMusic(url)
                count = count+1
            end
        else
            print("play music once")
            print("music id:"..id)
            PlayMusic(url)
            print("play completely")
        end
        

    elseif mode==2 then
        local listid="/api/playlist/detail?s=0&id="..id
        local data = http.get(NeteastMusicApi..listid).readAll()
        local musicList = textutils.unserialiseJSON(data)
        local List=musicList["playlist"]["tracks"]

        local idList = {}
        for index, value in pairs(List) do
            idList[#idList + 1] = value["id"]
        end


        if play then
            print("play list in loop mode")
            local count = 1
            while play do
                i=1
                print("loop count:"..tostring(count))
                while not (i>#idList) do
                    local mid = idList[i]
                    print("playing id: "..mid.." ("..i.."/"..#idList..")")
                    local url =GetMusicUrl(mid)
                    PlayMusic(url)
                    i=i+1
                end
                count = count+1
            end
        else
            print("play music list once")
            while not (i>#idList) do
                local mid = idList[i]
                print("playing id: "..mid.." ("..i.."/"..#idList..")")
                local url =GetMusicUrl(mid)
                PlayMusic(url)
                i=i+1
            end
            print("play completely")
        end
    elseif mode==3 then
        if play then
            print("play dfpwm in loop mode")
            local count = 1
            while play do
                print("loop count:"..tostring(count))
                for chunk in io.lines(id, 16 * 1024) do
                    local buffer = decoder(chunk)
                    while not speaker.playAudio(buffer) do
                        os.pullEvent("speaker_audio_empty")
                    end
                end
                count = count+1
            end
        else
            print("play dfpwm once")
            for chunk in io.lines(id, 16 * 1024) do
                local buffer = decoder(chunk)
                while not speaker.playAudio(buffer) do
                    os.pullEvent("speaker_audio_empty")
                end
            end
            print("play completely")
        end
    end
end

local showControl = function ()
    while true do
        if bytes_read>1 then
            local posx,posy = term.getCursorPos()
            term.setCursorPos(1, termSizeY)
            write("            ")
            term.setCursorPos(1, termSizeY)
            write(("%ds / %ds"):format(math.floor(bytes_read / 6000), math.ceil(total_length)))
            if mode==2 then
                local x,y = term.getCursorPos()
                term.setCursorPos(termSizeX-8,termSizeY-2)
                write("         ")
                term.setCursorPos(termSizeX-8,termSizeY-1)
                write("         ")
                term.setCursorPos(termSizeX-8,termSizeY)
                write("| < | > |")
            end
            if posy>termSizeY-3 then
                term.scroll(4)
                term.setCursorPos(posx, termSizeY-4)
                term.clearLine()
                term.setCursorPos(posx, posy-4)
            else
                term.setCursorPos(posx, posy)
            end
            sleep(1)
        else
            sleep(0.05)
        end
    end
end

local event = function ()
    while true do
        if mode==2 then
            local event, button, x, y = os.pullEvent("mouse_click")
            
            if y==termSizeY then
                if x<termSizeX and x>termSizeX-4 then
                    bytes_read=total_size
                elseif x<termSizeX-4 and x>termSizeX-8 then
                    if i>1 then
                        i=i-2
                        bytes_read=total_size
                    end
                end
            end
        else
            sleep(0.05)
        end
    end
end

parallel.waitForAny(event, playMusic, showControl)