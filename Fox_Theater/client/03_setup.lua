function SetupMovie(projectionName, movieName)
    local projection = Config.Projections[projectionName]
    local movie = Config.Movies[movieName]

    if not projection or not movie then
        return nil
    end

    Config.Shows.MOVIE.animscene[1] = movie.animscene or "script@shows@magic_lantern@ig2_projectionist@thebear"
    Config.Shows.MOVIE.position = projection.originPos
    Config.Shows.MOVIE.rotation = projection.originRot

    if not LoadModelWithTimeout(projection.targetModel) then
        return nil
    end

    local screen = CreateObjectNoOffset(
        projection.targetModel,
        projection.screenPos.x,
        projection.screenPos.y,
        projection.screenPos.z,
        false,
        false,
        false,
        true
    )

    if not screen or screen == 0 then
        SetModelAsNoLongerNeeded(projection.targetModel)
        return nil
    end

    SetEntityRotation(
        screen,
        projection.screenRot.x,
        projection.screenRot.y,
        projection.screenRot.z,
        2,
        true
    )
    SetEntityVisible(screen, false)
    SetEntityDynamic(screen, false)
    SetEntityProofs(screen, 31, false)
    FreezeEntityPosition(screen, true)
    SetModelAsNoLongerNeeded(projection.targetModel)

    if not IsNamedRendertargetRegistered(projection.renderTarget) then
        RegisterNamedRendertarget(projection.renderTarget, false)
    end

    LinkNamedRendertarget(projection.targetModel)

    if not IsNamedRendertargetLinked(projection.targetModel) then
        if IsNamedRendertargetRegistered(projection.renderTarget) then
            ReleaseNamedRendertarget(projection.renderTarget)
        end

        DeleteEntity(screen)
        return nil
    end

    TrackCreatedEntry("ENTITY", screen)

    return {
        screen = screen,
        renderTarget = GetNamedRendertargetRenderId(projection.renderTarget)
    }
end

function IsMovieValid(projectionName, movieName)
    return Config.Projections[projectionName] ~= nil and Config.Movies[movieName] ~= nil
end

function GetShowCurtain(showName)
    local showData = Config.Shows[showName]
    if not showData or not showData.curtain then
        return nil
    end

    local curtain = Config.Curtains[showData.curtain]
    if type(curtain) ~= "table" or not curtain.animscene then
        return nil
    end

    return curtain, showData.curtain
end

function PlayCurtainSound(soundName)
    if not soundName then
        soundName = math.random(1, 2) == 2 and "Curtain_Opens_Music" or "Curtain_Open_Music"
    end

    local soundset = Config.Soundsets[soundName]
    if not soundset then
        return nil
    end

    local attempts = 0
    while not LoadStream(soundName, soundset) and attempts < 5 do
        attempts = attempts + 1
        Wait(25)
    end

    local streamHandle = N_0x0556c784fa056628(soundName, soundset)
    if streamHandle == -1 then
        return nil
    end

    N_0x839c9f124be74d94(streamHandle, 0, 2548.749, -1305.267, 50.01453)
    N_0x839c9f124be74d94(streamHandle, 1, 2543.801, -1305.251, 50.01453)
    PlayStreamFromPosition(2548.749, -1305.267, 50.01453, streamHandle)

    return streamHandle
end

function CreateCurtains()
    local curtainModel = -262339715
    if not LoadModelWithTimeout(curtainModel) then
        print("^1[Fox_Theater] Não foi possível carregar o modelo da cortina.^7")
        return false
    end

    for curtainName, curtainData in pairs(Config.Curtains) do
        if type(curtainData) ~= "table" or not curtainData.animscene then
            local coords = curtainData
            local curtainObject = CreateObject(
                curtainModel,
                coords.x,
                coords.y,
                coords.z,
                false,
                false,
                false,
                false,
                false
            )

            local animscene = Citizen.InvokeNative(
                2290811462204274611,
                "script@shows@curtains@curtains",
                0,
                "PBL_IDLE_CLOSED",
                false,
                true
            )

            Config.Curtains[curtainName] = {
                coords = coords,
                object = curtainObject,
                animscene = animscene
            }

            SetAnimSceneEntity(animscene, "CURTAIN", curtainObject, 0)
        end
    end

    SetModelAsNoLongerNeeded(curtainModel)
    return true
end

function ResetCurtain(curtainName)
    local curtain = Config.Curtains[curtainName]
    if not curtain or type(curtain) ~= "table" then
        return false
    end

    ResetAnimScene(curtain.animscene, 0)
    SetAnimSceneEntity(curtain.animscene, "CURTAIN", curtain.object, 0)
    ApplyPlaybackList(curtain.animscene, "PBL_IDLE_CLOSED")

    return true
end

function CreateNooseRope(animscene)
    local nooseActor = Citizen.InvokeNative(-335953130118502380, animscene, "Noose", false)
    if not DoesEntityExist(nooseActor) then
        return nil, nil
    end

    local nooseModel = -911874060
    if not LoadModelWithTimeout(nooseModel) then
        return nil, nil
    end

    local offset = GetOffsetFromEntityInWorldCoords(nooseActor, 0.0, -0.6, 0.6023343)
    local nooseObject = CreateObject(
        nooseModel,
        offset.x,
        offset.y,
        offset.z,
        false,
        false,
        false,
        false,
        false
    )

    local rope = Citizen.InvokeNative(
        -1601698823280313703,
        2546.724,
        -1309.638,
        50.76665,
        0.0,
        0.0,
        0.0,
        0.3,
        1,
        0,
        -1,
        -1082130432
    )

    N_0x462ff2a432733a44(
        rope,
        nooseObject,
        nooseActor,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0,
        0
    )
    N_0x522fa3f490e2f7ac(rope, 1, 1)

    SetModelAsNoLongerNeeded(nooseModel)
    return rope, nooseObject
end

function _LoadStream(soundset)
    local attempts = 0

    while attempts <= 4 do
        if LoadStream("Audience", soundset) then
            return true
        end

        attempts = attempts + 1
        Wait(25)
    end

    return false
end

function _IsAnimSceneLoaded(animscene)
    return Citizen.InvokeNative(5147934026226366824, animscene, 1, 0)
end

function _IsAnimSceneStarted(animscene)
    return Citizen.InvokeNative(-3747989785349922080, animscene, true)
end

function _IsAnimSceneFinished(animscene)
    return _GetAnimsceneProgress(animscene) >= 0.999
end

function _IsAnimSceneFinished_2(animscene)
    return Citizen.InvokeNative(-2871804856677023445, animscene, 0)
end

function _GetAnimsceneProgress(animscene)
    return Citizen.InvokeNative(4592615340341649343, animscene, Citizen.ResultAsFloat())
end
