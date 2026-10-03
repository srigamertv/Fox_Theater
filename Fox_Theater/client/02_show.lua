function PlayMovie(projection, movie, movieSetup, animscene)
    if not projection or not movie or not movieSetup then
        return false
    end

    ApplyPlaybackList(animscene, "pl_action")
    WaitForAnimSceneStarted(animscene)

    SetTvAudioFrontend(false)
    SetTvVolume(projection.volume or 1.0)
    AttachTvAudioToEntity(movieSetup.screen)
    N_0xf49574e2332a8f06(movieSetup.screen, 5.0)
    N_0x04d1d4e411ce52d0(movieSetup.screen, movieSetup.renderTarget)

    SetTvChannel(-1)
    SetTvChannelPlaylist(0, movie.clip, true)
    SetTvChannel(0)

    _LoadStream(movie.audio)

    local streamHandle = N_0x0556c784fa056628("Audience", movie.audio)
    ActiveShowState.movieStream = streamHandle

    if streamHandle and streamHandle ~= -1 then
        PlayStreamFromPosition(
            projection.audiencePos.x,
            projection.audiencePos.y,
            projection.audiencePos.z,
            streamHandle
        )
    end

    Wait(100)
    SetEntityVisible(movieSetup.screen, true)

    local timeoutAt = GetGameTimer() + Config.SceneTimeout
    while streamHandle and streamHandle ~= -1 and IsStreamPlaying(streamHandle) do
        if CancelCurrentShow or GetGameTimer() >= timeoutAt then
            break
        end

        local canRender = true
        if projection.radius then
            local distance = #(GetEntityCoords(PlayerPedId()) - projection.audiencePos)
            canRender = distance <= projection.radius
        end

        if canRender then
            SetTextRenderId(movieSetup.renderTarget)
            DrawTvChannel(
                projection.renderX or 0.5,
                projection.renderY or 0.5,
                projection.renderScaleX or 1.0,
                projection.renderScaleY or 1.0,
                0.0,
                255,
                255,
                255,
                128
            )
        end

        Wait(5)
    end

    SetTextRenderId(0)
    return true
end

function RunShow(showName, projectionName, movieName)
    showName = tostring(showName or ""):upper()

    local showData = Config.Shows[showName]
    if not showData then
        return false, "Show inválido: " .. showName
    end

    local projection = nil
    local movie = nil
    local movieSetup = nil

    if showName == "MOVIE" then
        projectionName = tostring(projectionName or ""):upper()
        movieName = tostring(movieName or ""):upper()

        if not IsMovieValid(projectionName, movieName) then
            return false, "Filme ou projeção inválida."
        end

        projection = Config.Projections[projectionName]
        movie = Config.Movies[movieName]
        movieSetup = SetupMovie(projectionName, movieName)

        if not movieSetup then
            return false, "Não foi possível preparar a tela do cinema."
        end

        showData = Config.Shows.MOVIE
    end

    local animscene = Citizen.InvokeNative(2290811462204274611, table.unpack(showData.animscene))
    if not animscene or animscene == 0 then
        return false, "Não foi possível criar a cena."
    end

    ActiveShowState.animscene = animscene
    ActiveShowState.movie = movieSetup
    ActiveShowState.projection = projection

    if showData.position then
        SetAnimSceneOrigin(animscene, showData.position, showData.rotation or vector3(0.0, 0.0, 0.0), 2)
    end

    CreateShowEntities(animscene, showData)

    LoadAnimScene(animscene)
    if not WaitForAnimSceneLoaded(animscene) then
        return false, "Tempo limite ao carregar a cena."
    end

    local opened, curtain = OpenShowCurtain(showName, animscene)
    if not opened then
        return false, "Não foi possível iniciar a cena."
    end

    if showName == "ESCAPENOOSE" and not ActiveShowState.rope then
        ActiveShowState.rope, ActiveShowState.nooseObject = CreateNooseRope(animscene)
    end

    if not _IsAnimSceneStarted(animscene) then
        StartAnimScene(animscene)
    end

    if not WaitForAnimSceneStarted(animscene) then
        return false, "Tempo limite ao iniciar a cena."
    end

    if showName == "MOVIE" then
        PlayMovie(projection, movie, movieSetup, animscene)
        return true
    end

    if not WaitForAnimSceneFinished(animscene) then
        return false, "A cena principal excedeu o tempo limite."
    end

    if not PlayShowSequence(showName, animscene, showData) then
        return false, "A sequência do show foi interrompida."
    end

    if showData.endAtProgress then
        WaitForAnimSceneProgress(animscene, showData.endAtProgress)
    end

    CloseShowCurtain(curtain)
    WaitForAnimSceneFinished(animscene)

    return true
end

function CleanupMovieState(movieSetup, projection)
    SetTvChannel(-1)
    SetTextRenderId(0)

    if ActiveShowState and ActiveShowState.movieStream and ActiveShowState.movieStream ~= -1 then
        if IsStreamPlaying(ActiveShowState.movieStream) then
            StopStream(ActiveShowState.movieStream)
        end
    end

    if movieSetup and movieSetup.screen and DoesEntityExist(movieSetup.screen) then
        DeleteEntity(movieSetup.screen)
        RemoveTrackedEntry("ENTITY", movieSetup.screen)
    end

    if projection and projection.renderTarget and IsNamedRendertargetRegistered(projection.renderTarget) then
        ReleaseNamedRendertarget(projection.renderTarget)
    end
end

function CleanupActiveShow()
    if not ActiveShowState then
        return
    end

    CleanupMovieState(ActiveShowState.movie, ActiveShowState.projection)

    if ActiveShowState.curtainStream and ActiveShowState.curtainStream ~= -1 then
        if IsStreamPlaying(ActiveShowState.curtainStream) then
            StopStream(ActiveShowState.curtainStream)
        end
    end

    if ActiveShowState.rope then
        DeleteRope(ActiveShowState.rope)
    end

    if ActiveShowState.nooseObject and DoesEntityExist(ActiveShowState.nooseObject) then
        DeleteEntity(ActiveShowState.nooseObject)
    end

    for _, entity in ipairs(ActiveShowState.entities or {}) do
        if DoesEntityExist(entity) then
            SetEntityAsMissionEntity(entity, true, true)
            DeleteEntity(entity)
        end
        RemoveTrackedEntry("ENTITY", entity)
    end

    if ActiveShowState.animscene and ActiveShowState.animscene ~= 0 then
        Citizen.InvokeNative(-8867909632368771072, ActiveShowState.animscene)
    end

    ActiveShowState = nil
end

function StartShow(showName, projectionName, movieName)
    if ShowRunning then
        DebugPrint("Um show já está em execução neste cliente.")
        return false
    end

    ShowRunning = true
    CancelCurrentShow = false
    ActiveShowState = {
        entities = {},
        animscene = nil,
        rope = nil,
        nooseObject = nil,
        movie = nil,
        projection = nil,
        movieStream = nil,
        curtainStream = nil
    }

    TogglePrompts("ALL", false)

    local success, result, errorMessage = xpcall(RunShow, debug.traceback, showName, projectionName, movieName)

    CleanupActiveShow()
    ShowRunning = false
    CancelCurrentShow = false

    if not success then
        print("^1[Fox_Theater] Erro ao executar show:^7\n" .. tostring(result))
        return false
    end

    if result == false then
        DebugPrint(errorMessage or "O show não pôde ser executado.")
        return false
    end

    return true
end
