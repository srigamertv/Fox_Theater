function RegisterPrompts()
    local registeredPrompts = {}

    for _, promptData in ipairs(Config.Prompts) do
        local prompt = Citizen.InvokeNative(358456065073976345, Citizen.ResultAsInteger())
        Citizen.InvokeNative(
            6759949783219178967,
            prompt,
            CreateVarString(10, "LITERAL_STRING", promptData.label)
        )
        Citizen.InvokeNative(-5389353599369182632, prompt, promptData.control or 0xCEFD9220)
        Citizen.InvokeNative(-7780182363162449029, prompt, promptData.time or 1000)
        Citizen.InvokeNative(-600625171892873031, prompt)
        Citizen.InvokeNative(-8498375165399069407, prompt, false)
        Citizen.InvokeNative(8151896636996482542, prompt, false)

        TrackCreatedEntry("PROMPT", prompt)
        registeredPrompts[promptData.id] = prompt
    end

    Config.Prompts = registeredPrompts
    return true
end

function TogglePrompts(promptIds, state)
    local prompts = promptIds

    if promptIds == "ALL" or promptIds == nil then
        prompts = Config.Prompts
    end

    for key, value in pairs(prompts or {}) do
        local prompt = nil

        if promptIds == "ALL" or promptIds == nil then
            prompt = value
        elseif type(key) == "number" then
            prompt = Config.Prompts[value]
        else
            prompt = Config.Prompts[key]
        end

        if type(prompt) == "number" then
            Citizen.InvokeNative(-8498375165399069407, prompt, state == true)
            Citizen.InvokeNative(8151896636996482542, prompt, state == true)
        end
    end

    PromptsEnabled = state == true
end

function IsPromptCompleted(promptId)
    local prompt = Config.Prompts[promptId]
    if not prompt then
        return false
    end

    return Citizen.InvokeNative(-2236495684479023593, prompt)
end

function IsPromptEnabled(promptId)
    local prompt = Config.Prompts[promptId]
    if not prompt then
        return false
    end

    return PromptIsEnabled(prompt)
end

function CreateBlips()
    if not Config.EnableBlips then
        return
    end

    for _, theatre in pairs(Config.Theatres) do
        local blip = Citizen.InvokeNative(6146742050375520258, 2957021944, theatre.coords)
        Citizen.InvokeNative(
            -7155760889824349182,
            blip,
            CreateVarString(10, "LITERAL_STRING", theatre.label or "Theatre")
        )
        SetBlipSprite(blip, -417940443)
        TrackCreatedEntry("BLIP", blip)
    end
end

function GetNearestTheatre()
    local playerCoords = GetEntityCoords(PlayerPedId())
    local nearestName = nil
    local nearestDistance = math.huge

    for theatreName, theatre in pairs(Config.Theatres) do
        local distance = #(playerCoords - theatre.coords)
        if distance < nearestDistance then
            nearestName = theatreName
            nearestDistance = distance
        end
    end

    return nearestName, nearestDistance
end

function NotifyClient(message, duration)
    message = tostring(message)
    duration = duration or 4000

    if GetResourceState('vorp_core') == 'started' then
        local success, core = pcall(function() return exports.vorp_core:GetCore() end)
        if success and core and core.NotifyRightTip then
            core.NotifyRightTip(message, duration)
            return
        end
        TriggerEvent('vorp:TipRight', message, duration)
        return
    end

    if GetResourceState('rsg-core') == 'started' then
        local success, core = pcall(function() return exports['rsg-core']:GetCoreObject() end)
        if success and core and core.Functions and core.Functions.Notify then
            core.Functions.Notify(message, 'primary', duration)
            return
        end
    end

    TriggerEvent('chat:addMessage', {
        color = {255, 255, 255},
        multiline = true,
        args = {'THEATER', message}
    })
end

function CleanupCreatedEntries()
    for _, entry in ipairs(Config.CreatedEntries) do
        if entry.type == "ENTITY" then
            if DoesEntityExist(entry.handle) then
                DeleteEntity(entry.handle)
            end
        elseif entry.type == "BLIP" then
            RemoveBlip(entry.handle)
        elseif entry.type == "PROMPT" then
            Citizen.InvokeNative(66965263061602137, entry.handle)
        elseif entry.type == "CAM" and DoesCamExist(entry.handle) then
            RenderScriptCams(false, false, 0, false, false, false)
            DestroyCam(entry.handle)
        end
    end

    Config.CreatedEntries = {}
end

RegisterNetEvent("Fox_Theater:client:startShow")
AddEventHandler("Fox_Theater:client:startShow", function(payload)
    CreateThread(function()
        if type(payload) == "table" then
            StartShow("MOVIE", payload.town, payload.name)
        else
            StartShow(payload)
        end
    end)
end)

RegisterNetEvent("Fox_Theater:client:ticketResult")
AddEventHandler("Fox_Theater:client:ticketResult", function(success, message)
    TicketRequestPending = false

    if message and message ~= "" then
        NotifyClient(message, success and 4000 or 5000)
    end
end)

RegisterNetEvent("Fox_Theater:client:forceStop")
AddEventHandler("Fox_Theater:client:forceStop", function()
    CancelCurrentShow = true
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    CancelCurrentShow = true
    CleanupActiveShow()
    CleanupCreatedEntries()

    for _, curtain in pairs(Config.Curtains) do
        if type(curtain) == "table" then
            if curtain.object and DoesEntityExist(curtain.object) then
                DeleteEntity(curtain.object)
            end

            if curtain.animscene then
                Citizen.InvokeNative(-8867909632368771072, curtain.animscene)
            end
        end
    end
end)

CreateThread(function()
    RegisterPrompts()
    CreateBlips()
    CreateCurtains()

    while true do
        local sleep = 1000
        local theatreName, distance = GetNearestTheatre()
        local canInteract = theatreName ~= nil
            and distance <= Config.InteractionDistance
            and not ShowRunning
            and not TicketRequestPending

        if canInteract then
            sleep = 0

            if not PromptsEnabled then
                TogglePrompts("ALL", true)
            end

            if IsPromptCompleted("BUY_TICKET") then
                TicketRequestPending = true
                TogglePrompts("ALL", false)
                TriggerServerEvent("Fox_Theater:server:buyTicket", theatreName)

                SetTimeout(7000, function()
                    TicketRequestPending = false
                end)
            end
        elseif PromptsEnabled then
            TogglePrompts("ALL", false)
        end

        Wait(sleep)
    end
end)
