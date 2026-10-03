local VorpCore = nil
local RSGCore = nil
local PurchaseCooldowns = {}
local TicketUseCooldowns = {}
local TheatreLocks = {}
local ActiveTheatreShows = {}
local RegisteredTicketFramework = nil

local function debugPrint(...)
    if Config.Debug then
        print('^3[Fox_Theater:server]^7', ...)
    end
end

local function detectFramework()
    local configured = string.lower(Config.Framework or 'auto')
    if configured ~= 'auto' then return configured end
    if GetResourceState('rsg-core') == 'started' then return 'rsg' end
    if GetResourceState('vorp_core') == 'started' then return 'vorp' end
    return 'standalone'
end

local function loadVorpCore()
    if VorpCore then return true end
    if GetResourceState('vorp_core') ~= 'started' then return false end
    local ok, core = pcall(function() return exports.vorp_core:GetCore() end)
    if ok and core then VorpCore = core end
    return VorpCore ~= nil
end

local function loadRsgCore()
    if RSGCore then return true end
    if GetResourceState('rsg-core') ~= 'started' then return false end
    local ok, core = pcall(function() return exports['rsg-core']:GetCoreObject() end)
    if ok and core then RSGCore = core end
    return RSGCore ~= nil
end

local function getVorpCharacter(src)
    if not loadVorpCore() or not VorpCore.getUser then return nil end
    local user = VorpCore.getUser(src)
    return user and user.getUsedCharacter or nil
end

local function takePayment(src, amount)
    amount = math.max(0, tonumber(amount) or 0)
    if amount <= 0 or detectFramework() == 'standalone' then return true end

    if detectFramework() == 'rsg' then
        if not loadRsgCore() then return false, 'RSG Core não está disponível.' end
        local player = RSGCore.Functions.GetPlayer(src)
        if not player then return false, 'Seu personagem ainda não está carregado.' end
        if (player.Functions.GetMoney('cash') or 0) < amount then
            return false, ('Você precisa de %s$ para comprar o ingresso.'):format(amount)
        end
        player.Functions.RemoveMoney('cash', amount, 'fox-theater-ticket')
        return true
    end

    local character = getVorpCharacter(src)
    if not character then return false, 'Seu personagem ainda não está carregado.' end
    local money = tonumber(character.money) or 0
    if money < amount then return false, ('Você precisa de %s$ para comprar o ingresso.'):format(amount) end
    character.removeCurrency(0, amount)
    return true
end

local function refundPayment(src, amount)
    amount = math.max(0, tonumber(amount) or 0)
    if amount <= 0 or detectFramework() == 'standalone' then return end

    if detectFramework() == 'rsg' then
        if loadRsgCore() then
            local player = RSGCore.Functions.GetPlayer(src)
            if player then player.Functions.AddMoney('cash', amount, 'fox-theater-refund') end
        end
        return
    end

    local character = getVorpCharacter(src)
    if character then character.addCurrency(0, amount) end
end

local function sendResult(src, success, message)
    TriggerClientEvent('Fox_Theater:client:ticketResult', src, success == true, message or '')
end

local function getPlayerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return GetEntityCoords(ped)
end

local function isNearTheatre(src, theatre)
    local coords = getPlayerCoords(src)
    return coords and theatre and theatre.coords and #(coords - theatre.coords) <= (tonumber(Config.ServerValidationDistance) or 4.0)
end

local function findNearestTheatre(src)
    local coords = getPlayerCoords(src)
    if not coords then return nil end
    local nearestName, nearestDistance = nil, math.huge
    for name, theatre in pairs(Config.Theatres or {}) do
        local distance = #(coords - theatre.coords)
        if distance < nearestDistance then
            nearestName, nearestDistance = name, distance
        end
    end
    if nearestDistance <= (tonumber(Config.ServerValidationDistance) or 4.0) then
        return nearestName
    end
    return nil
end

local function rateLimited(bucket, src)
    local now = GetGameTimer()
    local previous = bucket[src] or 0
    local cooldown = tonumber(Config.PlayerCooldown) or 5000
    if now - previous < cooldown then return true end
    bucket[src] = now
    return false
end

local function isBusy(name)
    local active = ActiveTheatreShows[name]
    if not active then return false end
    if os.time() >= active.expiresAt then
        ActiveTheatreShows[name] = nil
        return false
    end
    return true
end

local function randomShowName()
    local shows = {}
    for name in pairs(Config.Shows or {}) do
        if name ~= 'MOVIE' then shows[#shows+1] = name end
    end
    return #shows > 0 and shows[math.random(1,#shows)] or nil
end

local function randomMovieName()
    local movies = {}
    for name in pairs(Config.Movies or {}) do movies[#movies+1] = name end
    return #movies > 0 and movies[math.random(1,#movies)] or nil
end

local function buildPayload(theatre)
    if theatre.mode == 'movie' then
        local movie = randomMovieName()
        if not movie or not theatre.projection then return nil end
        return {town = theatre.projection, name = movie}
    end
    return randomShowName()
end

local function payloadLabel(payload)
    if type(payload) == 'table' then return tostring(payload.name):gsub('_',' ') end
    return tostring(payload):gsub('_',' ')
end

local function broadcastShow(theatreName, payload, purchaserSource)
    local theatre = Config.Theatres[theatreName]
    if not theatre then return 0 end
    local maxDistance = tonumber(Config.BroadcastDistance) or 120.0
    local sent = 0
    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)
        local shouldReceive = target == tonumber(purchaserSource)
        if not shouldReceive then
            local coords = getPlayerCoords(target)
            shouldReceive = coords and #(coords - theatre.coords) <= maxDistance
        end
        if shouldReceive then
            TriggerClientEvent('Fox_Theater:client:startShow', target, payload)
            sent = sent + 1
        end
    end
    return sent
end

local function markBusy(name, payload)
    local ms = tonumber(Config.ShowCooldown) or 180000
    ActiveTheatreShows[name] = {payload=payload, expiresAt=os.time()+math.max(1, math.ceil(ms/1000))}
end

local function startConfiguredShow(name, payload, src)
    if not Config.Theatres[name] or not payload then return false end
    markBusy(name, payload)
    local recipients = broadcastShow(name, payload, src)
    debugPrint('Show iniciado:', name, payloadLabel(payload), 'público:', recipients)
    return recipients > 0
end

local function ticketMetadata(theatreName)
    local theatre = Config.Theatres[theatreName]
    return {
        theatre = theatreName,
        theatreLabel = theatre and theatre.label or theatreName,
        price = tonumber(Config.Price) or 0
    }
end

local function giveTicket(src, theatreName)
    local item = Config.Ticket.Item
    local metadata = ticketMetadata(theatreName)
    local framework = detectFramework()

    if framework == 'vorp' then
        if GetResourceState('vorp_inventory') ~= 'started' then return false, 'vorp_inventory não está iniciado.' end
        local canCarry = exports.vorp_inventory:canCarryItem(src, item, 1)
        if not canCarry then return false, 'Você não tem espaço para carregar o ingresso.' end
        exports.vorp_inventory:addItem(src, item, 1, metadata)
        return true
    end

    if framework == 'rsg' then
        if not loadRsgCore() then return false, 'RSG Core não está disponível.' end
        if not RSGCore.Shared.Items[item] then return false, ('O item %s não existe no RSG Shared.Items.'):format(item) end
        if GetResourceState('rsg-inventory') ~= 'started' then return false, 'rsg-inventory não está iniciado.' end
        if not exports['rsg-inventory']:CanAddItem(src, item, 1) then return false, 'Você não tem espaço para carregar o ingresso.' end
        local ok = exports['rsg-inventory']:AddItem(src, item, 1, nil, metadata, 'fox-theater-ticket')
        return ok ~= false
    end

    return false, 'Inventário não disponível no modo standalone.'
end

local function addTicketBack(src, metadata)
    local item = Config.Ticket.Item
    if detectFramework() == 'vorp' and GetResourceState('vorp_inventory') == 'started' then
        exports.vorp_inventory:addItem(src, item, 1, metadata or {})
    elseif detectFramework() == 'rsg' and GetResourceState('rsg-inventory') == 'started' then
        exports['rsg-inventory']:AddItem(src, item, 1, nil, metadata or {}, 'fox-theater-refund-ticket')
    end
end

local function removeTicket(src, itemData)
    local item = Config.Ticket.Item
    if detectFramework() == 'vorp' then
        local id = itemData and (itemData.id or itemData.mainid)
        if id then return exports.vorp_inventory:subItemById(src, id, nil, false, 1) ~= false end
        return exports.vorp_inventory:subItem(src, item, 1) ~= false
    end
    if detectFramework() == 'rsg' then
        return exports['rsg-inventory']:RemoveItem(src, item, 1, itemData and itemData.slot or nil, 'fox-theater-use') ~= false
    end
    return true
end

local function getItemMetadata(itemData)
    if not itemData then return {} end
    return itemData.metadata or itemData.info or {}
end

local function useTicket(src, itemData)
    if rateLimited(TicketUseCooldowns, src) then
        sendResult(src, false, 'Aguarde um momento antes de usar outro ingresso.')
        return
    end

    local metadata = getItemMetadata(itemData)
    local theatreName = tostring(metadata.theatre or ''):upper()
    if theatreName == '' then theatreName = findNearestTheatre(src) end
    local theatre = theatreName and Config.Theatres[theatreName] or nil

    if not theatre or not isNearTheatre(src, theatre) then
        sendResult(src, false, 'Este ingresso só pode ser usado na bilheteria/local correspondente.')
        return
    end

    if TheatreLocks[theatreName] then
        sendResult(src, false, 'Este local está processando outro ingresso.')
        return
    end
    TheatreLocks[theatreName] = true

    if isBusy(theatreName) then
        TheatreLocks[theatreName] = nil
        sendResult(src, false, 'Já existe uma apresentação acontecendo neste local.')
        return
    end

    local payload = buildPayload(theatre)
    if not payload then
        TheatreLocks[theatreName] = nil
        sendResult(src, false, 'Nenhuma apresentação está configurada para este local.')
        return
    end

    if not removeTicket(src, itemData) then
        TheatreLocks[theatreName] = nil
        sendResult(src, false, 'Não foi possível consumir o ingresso.')
        return
    end

    local started = startConfiguredShow(theatreName, payload, src)
    TheatreLocks[theatreName] = nil

    if not started then
        ActiveTheatreShows[theatreName] = nil
        addTicketBack(src, metadata)
        sendResult(src, false, 'Não foi possível iniciar a apresentação. O ingresso foi devolvido.')
        return
    end

    sendResult(src, true, ('Ingresso utilizado. Apresentação: %s.'):format(payloadLabel(payload)))
end

local function registerTicketItem()
    if not Config.Ticket.Enabled or RegisteredTicketFramework then return end
    local framework = detectFramework()
    local item = Config.Ticket.Item

    if framework == 'vorp' then
        if GetResourceState('vorp_inventory') ~= 'started' then return end
        exports.vorp_inventory:registerUsableItem(item, function(data)
            local src = data and data.source
            if not src then return end
            if Config.Ticket.CloseInventory then exports.vorp_inventory:closeInventory(src) end
            useTicket(src, data.item)
        end, GetCurrentResourceName())
        RegisteredTicketFramework = 'vorp'
        return
    end

    if framework == 'rsg' then
        if not loadRsgCore() or not RSGCore.Shared.Items[item] then return end
        RSGCore.Functions.CreateUseableItem(item, function(src, data)
            if Config.Ticket.CloseInventory and GetResourceState('rsg-inventory') == 'started' then
                TriggerClientEvent('rsg-inventory:client:closeinv', src)
            end
            useTicket(src, data)
        end)
        RegisteredTicketFramework = 'rsg'
    end
end

RegisterNetEvent('Fox_Theater:server:buyTicket', function(theatreName)
    local src = source
    theatreName = tostring(theatreName or ''):upper()
    local theatre = Config.Theatres[theatreName]
    if not theatre then return sendResult(src, false, 'Teatro inválido.') end
    if rateLimited(PurchaseCooldowns, src) then return sendResult(src, false, 'Aguarde um momento antes de tentar novamente.') end
    if not isNearTheatre(src, theatre) then return sendResult(src, false, 'Você está longe demais da bilheteria.') end

    if detectFramework() == 'standalone' or not Config.Ticket.Enabled then
        if isBusy(theatreName) then return sendResult(src, false, 'Já existe uma apresentação acontecendo neste local.') end
        local payload = buildPayload(theatre)
        if not payload then return sendResult(src, false, 'Nenhuma apresentação está configurada para este local.') end
        if startConfiguredShow(theatreName, payload, src) then
            return sendResult(src, true, ('Apresentação iniciada: %s.'):format(payloadLabel(payload)))
        end
        return sendResult(src, false, 'Não foi possível iniciar a apresentação.')
    end

    local price = math.max(0, tonumber(Config.Price) or 0)
    local paid, paymentError = takePayment(src, price)
    if not paid then return sendResult(src, false, paymentError) end

    local added, itemError = giveTicket(src, theatreName)
    if not added then
        refundPayment(src, price)
        return sendResult(src, false, itemError or 'Não foi possível entregar o ingresso.')
    end

    sendResult(src, true, ('Ingresso comprado por %s$ para %s. Use o item %s no local.'):format(price, theatre.label or theatreName, Config.Ticket.Label))
end)

RegisterCommand('theater', function(src, args)
    local mode = tostring(args[1] or ''):lower()
    if mode == 'show' then
        local show = tostring(args[2] or ''):upper()
        if show == '' or show == 'MOVIE' or not Config.Shows[show] then
            print('Uso: /theater show NOME_DO_SHOW')
            return
        end
        startConfiguredShow('SAINTDENIS_STAGE', show, src)
        return
    end
    if mode == 'movie' then
        local projection = tostring(args[2] or ''):upper()
        local movie = tostring(args[3] or ''):upper()
        local theatre = Config.Theatres[projection]
        if not theatre or theatre.mode ~= 'movie' or not Config.Movies[movie] then
            print('Uso: /theater movie SAINTDENIS|VALENTINE|BLACKWATER NOME_DO_FILME')
            return
        end
        startConfiguredShow(projection, {town=theatre.projection, name=movie}, src)
        return
    end
    print('Uso: /theater show NOME_DO_SHOW | /theater movie CIDADE NOME_DO_FILME')
end, true)

RegisterCommand('theaterstop', function(src, args)
    local theatreName = tostring(args[1] or ''):upper()
    local theatre = Config.Theatres[theatreName]
    if not theatre then
        print('Uso: /theaterstop SAINTDENIS_STAGE|SAINTDENIS|VALENTINE|BLACKWATER')
        return
    end
    ActiveTheatreShows[theatreName] = nil
    local maxDistance = tonumber(Config.BroadcastDistance) or 120.0
    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)
        local coords = getPlayerCoords(target)
        if coords and #(coords-theatre.coords) <= maxDistance then
            TriggerClientEvent('Fox_Theater:client:forceStop', target)
        end
    end
end, true)

AddEventHandler('playerDropped', function()
    PurchaseCooldowns[source] = nil
    TicketUseCooldowns[source] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if RegisteredTicketFramework == 'vorp' and GetResourceState('vorp_inventory') == 'started' then
        exports.vorp_inventory:unRegisterUsableItem(Config.Ticket.Item)
    end
end)

CreateThread(function()
    math.randomseed(os.time() + GetGameTimer())
    math.random(); math.random(); math.random()
    for _=1,20 do
        Wait(500)
        registerTicketItem()
        if RegisteredTicketFramework or detectFramework() == 'standalone' then break end
    end
    print(('^2[Fox_Theater] Iniciado. Framework: %s | Ticket: %s^7'):format(detectFramework(), Config.Ticket.Enabled and Config.Ticket.Item or 'desativado'))
end)
