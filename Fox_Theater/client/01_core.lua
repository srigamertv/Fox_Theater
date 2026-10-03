PromptsEnabled = false
ShowRunning = false
CancelCurrentShow = false
ActiveShowState = nil
TicketRequestPending = false

function DebugPrint(...)
    if Config.Debug then
        print("^3[Fox_Theater]^7", ...)
    end
end

function TrackCreatedEntry(entryType, handle)
    if not handle or handle == 0 then
        return
    end

    Config.CreatedEntries[#Config.CreatedEntries + 1] = {
        type = entryType,
        handle = handle
    }
end

function RemoveTrackedEntry(entryType, handle)
    for index = #Config.CreatedEntries, 1, -1 do
        local entry = Config.CreatedEntries[index]
        if entry.type == entryType and entry.handle == handle then
            table.remove(Config.CreatedEntries, index)
            return
        end
    end
end

function LoadModelWithTimeout(model)
    if not model or not IsModelInCdimage(model) then
        return false
    end

    RequestModel(model)

    local timeoutAt = GetGameTimer() + Config.LoadTimeout
    while not HasModelLoaded(model) do
        if GetGameTimer() >= timeoutAt or CancelCurrentShow then
            return false
        end

        Wait(10)
        RequestModel(model)
    end

    return true
end

function WaitForAnimSceneLoaded(animscene)
    local timeoutAt = GetGameTimer() + Config.LoadTimeout

    while not _IsAnimSceneLoaded(animscene) do
        if GetGameTimer() >= timeoutAt or CancelCurrentShow then
            return false
        end

        Wait(10)
    end

    return true
end

function WaitForAnimSceneStarted(animscene)
    local timeoutAt = GetGameTimer() + Config.LoadTimeout

    while not _IsAnimSceneStarted(animscene) do
        if GetGameTimer() >= timeoutAt or CancelCurrentShow then
            return false
        end

        Wait(10)
    end

    return true
end

function WaitForAnimSceneProgress(animscene, targetProgress)
    local timeoutAt = GetGameTimer() + Config.SceneTimeout

    while _GetAnimsceneProgress(animscene) < targetProgress do
        if GetGameTimer() >= timeoutAt or CancelCurrentShow then
            return false
        end

        Wait(10)
    end

    return true
end

function WaitForAnimSceneFinished(animscene)
    local timeoutAt = GetGameTimer() + Config.SceneTimeout

    while not _IsAnimSceneFinished(animscene) do
        if GetGameTimer() >= timeoutAt or CancelCurrentShow then
            return false
        end

        Wait(10)
    end

    return true
end

function ApplyPlaybackList(animscene, playbackList)
    if not animscene or animscene == 0 or not playbackList then
        return false
    end

    SetAnimScenePlaybackList(animscene, playbackList)
    Citizen.InvokeNative(1538415758025153662, animscene, playbackList, true)
    return true
end

function CreateShowEntity(animscene, entityData)
    if not entityData or not entityData.fields or not entityData.model then
        return nil
    end

    local model = entityData.model
    local entity = 0

    if type(model) == "string" then
        local weaponHash = GetHashKey(model)
        if not IsWeaponValid(weaponHash) then
            DebugPrint("Arma inválida ignorada:", model)
            return nil
        end

        entity = Citizen.InvokeNative(
            -7455597945410846861,
            weaponHash,
            0,
            vector3(0.0, 0.0, 0.0),
            true,
            1.0
        )
    else
        if not LoadModelWithTimeout(model) then
            DebugPrint("Modelo inválido ou não carregado:", tostring(model))
            return nil
        end

        if IsModelAPed(model) then
            entity = CreatePed(model, 0.0, 0.0, -500.0, 0.0, false, false, true, true)

            if DoesEntityExist(entity) then
                AddEntityToAudioMixGroup(entity, "Default_Show_Performers_Group", -1.0)
                Citizen.InvokeNative(2898480469501981438, entity, true)

                for _, flag in ipairs(entityData.flags or {}) do
                    SetPedConfigFlag(entity, flag, true)
                end

                if entityData.ragdoll ~= nil then
                    SetPedCanRagdoll(entity, entityData.ragdoll == true)
                end

                if entityData.ragdollFlag then
                    SetRagdollBlockingFlags(entity, entityData.ragdollFlag)
                end
            end
        elseif IsModelAVehicle(model) then
            entity = CreateVehicle(model, 0.0, 0.0, -500.0, 0.0, false, false, false, false)
        else
            entity = CreateObject(model, 0.0, 0.0, -500.0, false, false, false, true, true)
        end

        SetModelAsNoLongerNeeded(model)
    end

    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return nil
    end

    SetAnimSceneEntity(animscene, entityData.fields[1], entity, entityData.fields[2] or 0)
    TrackCreatedEntry("ENTITY", entity)
    ActiveShowState.entities[#ActiveShowState.entities + 1] = entity

    return entity
end

function CreateShowEntities(animscene, showData)
    for _, entityData in ipairs(showData.entities or {}) do
        if CancelCurrentShow then
            return false
        end

        CreateShowEntity(animscene, entityData)
    end

    return true
end

function SelectPlaybackList(sequenceEntry)
    if type(sequenceEntry) ~= "table" then
        return sequenceEntry
    end

    if #sequenceEntry == 0 then
        return nil
    end

    if Config.RandomTransitions then
        return sequenceEntry[math.random(1, #sequenceEntry)]
    end

    return sequenceEntry[1]
end

function OpenShowCurtain(showName, animscene)
    local curtain, curtainName = GetShowCurtain(showName)
    if not curtain then
        StartAnimScene(animscene)
        return WaitForAnimSceneStarted(animscene), nil
    end

    ResetCurtain(curtainName)

    if not _IsAnimSceneLoaded(curtain.animscene) then
        LoadAnimScene(curtain.animscene)
        if not WaitForAnimSceneLoaded(curtain.animscene) then
            return false, curtain
        end
    end

    StartAnimScene(animscene)
    SetAnimScenePaused(animscene, true)

    StartAnimScene(curtain.animscene)
    if not WaitForAnimSceneStarted(curtain.animscene) then
        return false, curtain
    end

    ActiveShowState.curtainStream = PlayCurtainSound(Config.Shows[showName].music)
    ApplyPlaybackList(curtain.animscene, "PBL_OPEN_SLOW")

    if showName == "ESCAPENOOSE" and not ActiveShowState.rope then
        ActiveShowState.rope, ActiveShowState.nooseObject = CreateNooseRope(animscene)
    end

    if not WaitForAnimSceneProgress(curtain.animscene, 0.5) then
        return false, curtain
    end

    ApplyPlaybackList(curtain.animscene, "PBL_IDLE_OPEN")
    SetAnimScenePaused(animscene, false)

    return true, curtain
end

function CloseShowCurtain(curtain)
    if not curtain or not curtain.animscene then
        return true
    end

    ApplyPlaybackList(curtain.animscene, "PBL_CLOSE_SLOW")

    if not WaitForAnimSceneStarted(curtain.animscene) then
        return false
    end

    if not WaitForAnimSceneProgress(curtain.animscene, 0.5) then
        return false
    end

    ApplyPlaybackList(curtain.animscene, "PBL_IDLE_CLOSED")
    return true
end

function PlayShowSequence(showName, animscene, showData)
    if not showData.sequence then
        return true
    end

    for index, sequenceEntry in ipairs(showData.sequence) do
        if CancelCurrentShow then
            return false
        end

        local playbackList = SelectPlaybackList(sequenceEntry)
        if not playbackList then
            return false
        end

        ApplyPlaybackList(animscene, playbackList)

        if not WaitForAnimSceneStarted(animscene) then
            return false
        end

        if showName == "ESCAPENOOSE" and playbackList == "PL_E_Shoot_Rope" and ActiveShowState.rope then
            local nooseActor = Citizen.InvokeNative(-335953130118502380, animscene, "Noose", false)
            if DoesEntityExist(nooseActor) then
                DetachRopeFromEntity(ActiveShowState.rope, nooseActor)
            end
        end

        local isLastEntry = index == #showData.sequence
        if not (isLastEntry and showData.endAtProgress) then
            if not WaitForAnimSceneFinished(animscene) then
                return false
            end
        end
    end

    return true
end
