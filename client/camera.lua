-- Security cameras (stock `police:client:ActiveCamera(id)`, `0` closes). Purely a
-- local view: nothing here reads or writes server state. Camera online flags are
-- per client, set by `DisableAllCameras` / `EnableAllCameras` / `SetCamera`.

local activeCam, activeId = nil, 0
local online = {}

local function isOnline(id)
    if online[id] ~= nil then return online[id] end
    return Config.cameras.list[id].isOnline == true
end

local function camera(id)
    return Config.cameras.list[id]
end

local function close()
    if not activeCam then return end
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(activeCam, false)
    activeCam, activeId = nil, 0
    ClearTimecycleModifier()
    SetFocusEntity(PlayerPedId())
    if Config.cameras.hideRadar then DisplayRadar(true) end
end

local looping = false
local function startLoop()
    if looping then return end
    looping = true
    CreateThread(function()
        while activeCam do
            if IsControlJustPressed(1, 177) then
                DoScreenFadeOut(250)
                while not IsScreenFadedOut() do Wait(0) end
                close()
                DoScreenFadeIn(250)
            elseif camera(activeId) and camera(activeId).canRotate then
                local rotation = GetCamRot(activeCam, 2)
                local pitch, yaw = rotation.x, rotation.z
                if IsControlPressed(0, 32) and pitch <= 0.0 then pitch = pitch + 0.7 end
                if IsControlPressed(0, 8) and pitch >= -50.0 then pitch = pitch - 0.7 end
                if IsControlPressed(0, 34) then yaw = yaw + 0.7 end
                if IsControlPressed(0, 9) then yaw = yaw - 0.7 end
                SetCamRot(activeCam, pitch, 0.0, yaw, 2)
            end
            Wait(5)
        end
        looping = false
    end)
end

local function open(id)
    local definition = camera(id)
    if not definition then return Police.notify(Kora.lang('Notify.camera_missing'), 'error') end
    if not isOnline(id) then return Police.notify(('%s is offline.'):format(definition.label), 'error') end
    close()
    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Wait(0) end
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, definition.coords.x, definition.coords.y, definition.coords.z)
    SetCamRot(cam, definition.r.x, definition.r.y, definition.r.z, 2)
    SetFocusArea(definition.coords.x, definition.coords.y, definition.coords.z, 0.0, 0.0, 0.0)
    RenderScriptCams(true, false, 0, true, true)
    SetTimecycleModifier('scanline_cam_cheap')
    SetTimecycleModifierStrength(1.0)
    if Config.cameras.hideRadar then DisplayRadar(false) end
    activeCam, activeId = cam, id
    startLoop()
    DoScreenFadeIn(250)
    Police.notify(definition.label, 'info')
end

RegisterNetEvent('police:client:ActiveCamera', function(cameraId)
    cameraId = tonumber(cameraId)
    if cameraId == 0 then
        close()
    elseif cameraId and Police.isOnDuty() then
        open(cameraId)
    end
end)

RegisterNetEvent('police:client:DisableAllCameras', function()
    for id in pairs(Config.cameras.list) do online[id] = false end
end)

RegisterNetEvent('police:client:EnableAllCameras', function()
    for id in pairs(Config.cameras.list) do online[id] = true end
end)

RegisterNetEvent('police:client:SetCamera', function(key, isOnlineFlag)
    local keys = type(key) == 'table' and key or { key }
    for _, id in ipairs(keys) do
        if type(id) == 'number' and camera(id) then online[id] = isOnlineFlag == true end
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then close() end
end)
