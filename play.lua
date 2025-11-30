local NeteastMusicApi = "http://music168.liulikeji.cn:15843/"
local TransApi = "http://newgmapi.liulikeji.cn/api/ffmpeg"


local feature = {"id","lid"} --1=id 2=lid
local playMode = {"once","cycle"} --1=once 2=cycle

local mode
local id
local play = false

--init vars
if arg[1]==nil then
    print("play [id/lid] [id] {once/cycle}")
    print(" id/uid: select musicid or playlist id")
    print(" id: the id of music or playlist")
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

function PlayMusic(url)
    print("")
    local function get_total_duration(url)
        if _G.Playprint then printlog("Calculating duration...") end
        local handle, err = http.get(url)
        if not handle then
            error("Could not get duration: " .. (err or "Unknown error"))
        end
        
        local data = handle.readAll()
        handle.close()
        
        -- DFPWM: 每字节8个样本，48000采样率
        local total_length = (#data * 8) / 48000
        return total_length, #data
    end



    local total_length, total_size
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
        
        local posx,posy = term.getCursorPos()
        term.setCursorPos(1, posy-1)
        print(("Playing: %ds / %ds"):format(math.floor(bytes_read / 6000), math.ceil(total_length)))
    end
end


if mode==1 then
    local url =GetMusicUrl(id)

    if play then
        print("play in loop mode")
        local count = 1
        while play do
            print("play count:"..tostring(count))
            PlayMusic(url)
            count = count+1
        end
    else
        print("play music once")
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
            print("play count:"..tostring(count))
            for index, value in pairs(idList) do
                print("playing id: "..value)
                local url =GetMusicUrl(value)
                PlayMusic(url)
            end
            count = count+1
        end
    else
        print("play music lists once")
        for index, value in pairs(idList) do
            print("playing id: "..value)
            local url =GetMusicUrl(value)
            PlayMusic(url)
        end
        print("play completely")
    end
end
