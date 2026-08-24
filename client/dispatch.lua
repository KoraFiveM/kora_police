-- Renders dispatch alerts (qbcore ships no NUI/UI of its own for these --
-- see Core.dispatch's own header). Legacy `police:client:policeAlert` is
-- fired automatically by qbcore's Core.dispatch.alert; this file renders
-- both the modern and legacy payload shape.

local activeBlips = {}

local function renderAlert(payload)
    if type(payload) ~= 'table' then payload = { message = tostring(payload) } end
    Police.notify(payload.title or 'Dispatch', payload.message and 'warning' or 'info')
    if payload.message then Police.notify(payload.message, 'warning') end

    if payload.coords then
        local blipOpts = payload.blip or {}
        local blip = QB.blips.create(payload.coords, {
            sprite = blipOpts.sprite or 161,
            color = blipOpts.color or 1,
            scale = blipOpts.scale or 1.0,
            label = payload.title or 'Dispatch',
            route = true,
        })
        if blip then
            activeBlips[#activeBlips + 1] = blip
            SetTimeout(blipOpts.duration or 60000, function()
                QB.blips.remove(blip)
            end)
        end
    end
end

RegisterNetEvent('qbcore:client:dispatchAlert', renderAlert)

RegisterNetEvent('police:client:policeAlert', function(message, coords)
    renderAlert({ title = 'Dispatch', message = message, coords = coords })
end)

RegisterNetEvent('qbpolice:client:updateCopCount', function(count)
    Police.copCount = count
end)
RegisterNetEvent('police:client:UpdateCurrentCops', function(count)
    Police.copCount = count
end)
RegisterNetEvent('police:client:SetCopCount', function(count)
    Police.copCount = count
end)

RegisterCommand('backup', function()
    if not Police.isOnDuty() then return end
    local coords = QB.cache.coords()
    TriggerServerEvent('qbpolice:server:requestBackup', { message = 'Officer requesting backup', coords = coords })
end, false)
