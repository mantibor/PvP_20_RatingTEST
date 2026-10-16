    local addonName, ns = ...

    -- ============================================================================
    -- LOCAL CONSTANTS
    -- ============================================================================
    local QueueState = { IDLE = 0, QUEUED = 1, MATCHED = 2 }

    local customQueues = {
        { key = "SOLO_SHUFFLE", title = PVP_RATED_SOLO_SHUFFLE, maxPlayers = 6,  orderIndex = 999  },
        { key = "ARENA_5V5",    title = ARENA_BATTLES_5V5,      maxPlayers = 10, orderIndex = 1000 },
    }

    -- ============================================================================
    -- STATE
    -- ============================================================================
    local currentState = QueueState.IDLE
    local heartbeatTimers = {}
    local myQueueStartTime = 0
    local myQueueServerTime = 0

    local QueueRoster = {}
    local lastRosterEcho = {}

    -- RoleCheck
    local roleCheckActive = false
    local roleCheckTimer = nil
    local roleCheckResults = {}
    local roleCheckLeader = nil
    local roleCheckExpectedPlayers = {}
    local soundLastPlayed = {}

    -- Community scan
    local communityScanScheduled = false
    local communityMembers = nil

    -- UI hooks flags
    local hostNotified = {}
    local wgPopupQueueKey = nil
    local readyDialogHooked = false
    local queueUpdateHooked = false
    local queueMenuHooked = false
    local eyeFlickerFixed = false

    -- ============================================================================
    -- BASE UTILITIES
    -- ============================================================================

    local function PlaySoundThrottled(soundKit)
        if not soundKit then return end
        local now = GetTime()
        local last = soundLastPlayed[soundKit]
        if last and (now - last) < 3 then return end
        soundLastPlayed[soundKit] = now
        PlaySound(soundKit)
    end

    local function ShortName(nameRealm)
        if not nameRealm or nameRealm == "" then return nameRealm end
        local name, realm = nameRealm:match("^(.+)%-(.+)$")
        if not name then return nameRealm end
        local myRealm = GetNormalizedRealmName()
        if myRealm and realm == myRealm then return name end
        return nameRealm
    end

    local function AnyQueueActive()
        for _, q in ipairs(customQueues) do
            if q.startTime then return true end
        end
        return false
    end

    local function RefreshFrames()
        if QueueStatusFrame and QueueStatusFrame.Update then
            QueueStatusFrame:Update()
        end
    end

    local function GetQueue(key)
        for _, q in ipairs(customQueues) do
            if q.key == key then return q end
        end
        return nil
    end

    local function GetActiveQueue()
        for _, q in ipairs(customQueues) do
            if q.startTime then return q end
        end
        return nil
    end

    local function GetConstraints(queueKey)
        if not queueKey then
            local q = GetActiveQueue()
            queueKey = q and q.key
        end
        if queueKey == "ARENA_5V5" then
            return { teamSize = 5, totalPlayers = 10, healersPerTeam = 2, minSubscribersPerTeam = 1 }
        end
        return { teamSize = 3, totalPlayers = 6, healersPerTeam = 1, minSubscribersPerTeam = 1 }
    end

    local function GetRosterSize(queueKey)
        return GetConstraints(queueKey).totalPlayers
    end

    local function RosterBucket(queueKey)
        if not queueKey then return nil end
        QueueRoster[queueKey] = QueueRoster[queueKey] or {}
        return QueueRoster[queueKey]
    end

    local function RosterGet(queueKey, nameRealm)
        local bucket = queueKey and QueueRoster[queueKey]
        if not bucket or not nameRealm then return nil end
        return bucket[nameRealm]
    end

    local function RoleFlags(roles)
        local tank, heal, dps = false, false, false
        if type(roles) == "string" then
            for token in roles:gmatch("[THD]") do
                if token == "T" then tank = true
                elseif token == "H" then heal = true
                elseif token == "D" then dps = true end
            end
        end
        return tank, heal, dps
    end

    local function AssignTeamRoles(queueKey, team, constraints)
        local bucket = QueueRoster[queueKey]
        if not bucket then return nil end
        local must, flex, other = {}, {}, {}
        local subscribers = 0
        for _, name in ipairs(team) do
            local data = bucket[name]
            if not data then return nil end
            if data.subscribed then subscribers = subscribers + 1 end
            local tank, heal, dps = RoleFlags(data.roles)
            if heal and not tank and not dps then
                must[#must + 1] = name
            elseif heal then
                flex[#flex + 1] = name
            else
                other[#other + 1] = { name = name, tank = tank, dps = dps }
            end
        end
        if subscribers < constraints.minSubscribersPerTeam then return nil end
        local need = constraints.healersPerTeam
        if #must > need or (#must + #flex) < need then return nil end
        local assign = {}
        for _, name in ipairs(must) do assign[name] = "HEALER" end
        local flexHeal = need - #must
        for i, name in ipairs(flex) do
            if i <= flexHeal then assign[name] = "HEALER"
            else
                local _, _, dps = RoleFlags(bucket[name].roles)
                local tank = RoleFlags(bucket[name].roles)
                assign[name] = (not dps and tank) and "TANK" or "DAMAGER"
            end
        end
        -- танк+боец — боец, как и у гибких выше: танк только если больше ничего не отмечено
        for _, entry in ipairs(other) do
            assign[entry.name] = (entry.tank and not entry.dps) and "TANK" or "DAMAGER"
        end
        return assign
    end

    -- ============================================================================
    -- ONLINE CHECKS
    -- ============================================================================
    local function BNetOnline(nameRealm)
        if not nameRealm then return false end
        local acc = ns.FindBNetFriendByNameRealm(nameRealm)
        if not acc or not acc.gameAccountInfo then return false end
        return acc.gameAccountInfo.isOnline and acc.gameAccountInfo.clientProgram == BNET_CLIENT_WOW
    end

    local function CommunityOnline(clubId, memberId)
        if not (C_Club and C_Club.GetMemberInfo) then return false end
        if not clubId or not memberId then return false end
        local info = C_Club.GetMemberInfo(clubId, memberId)
        if not info then return false end
        local ONLINE = Enum and Enum.ClubMemberPresence and Enum.ClubMemberPresence.Online
        return info.presence == ONLINE
    end

    -- ============================================================================
    -- SEND QUEUE MESSAGE
    -- ============================================================================
    -- Гильдия слышит очередь без дружбы в Battle.net. Шёпот вайтлиста остаётся
    -- для тех, кто в гильдии не состоит. Офлайн по кэшу не отсекаем (он врёт),
    -- только по ответу сервера «не найден» — см. whisperOfflineUntil ниже.
    local function IsGuildMember(nameRealm)
        if not IsInGuild() or not nameRealm then return false end
        for i = 1, GetNumGuildMembers() do
            local name = GetGuildRosterInfo(i)
            if name and ns.FormatNameRealm(name) == nameRealm then return true end
        end
        return false
    end

    -- Шёпот офлайн-человеку сервер возвращает строкой «Персонаж не найден»,
    -- и так на каждое сообщение очереди: десятки строк в чате в минуту.
    -- Кэшу не верим, верим ответу сервера: кто «не найден», тому 5 минут
    -- не шепчем; любое его аддон-сообщение снимает отметку раньше.
    local OFFLINE_TTL = 300
    local whisperOfflineUntil = {}
    local whisperedAt = {}

    local function GuildNameSet()
        local set = {}
        if not IsInGuild() then return set end
        for i = 1, GetNumGuildMembers() do
            local name = GetGuildRosterInfo(i)
            if name then set[ns.FormatNameRealm(name)] = true end
        end
        return set
    end

    -- Кто из вайтлиста в сети наверняка: онлайн в сообществах (ScheduleCommunityScan
    -- уже отобрал по вайтлисту и уровню), друзья Battle.net и обычные друзья в WoW,
    -- и те, от кого за 100 с пришло аддон-сообщение (heartbeat — раз в 90 с).
    -- Шептать всему вайтлисту нельзя: офлайн-адресаты съедают очередь ChatThrottleLib,
    -- а она отдаёт шёпот примерно раз в секунду — живые сообщения опаздывают.
    local HEARD_TTL = 100
    local lastHeard = {}

    local function OnlineTargets(wl)
        local online, now = {}, GetTime()
        if communityMembers then
            for _, list in pairs(communityMembers) do
                for _, m in ipairs(list) do online[m.name] = true end
            end
        end
        for nameRealm, at in pairs(lastHeard) do
            if now - at < HEARD_TTL then online[nameRealm] = true else lastHeard[nameRealm] = nil end
        end
        if C_FriendList and C_FriendList.GetNumFriends then
            for i = 1, C_FriendList.GetNumFriends() do
                local info = C_FriendList.GetFriendInfoByIndex(i)
                if info and info.connected and info.name then online[ns.FormatNameRealm(info.name)] = true end
            end
        end
        for nameRealm in pairs(wl) do
            if type(nameRealm) == "string" and not online[nameRealm] and BNetOnline(nameRealm) then
                online[nameRealm] = true
            end
        end
        return online
    end

    -- Всё сообщение очереди — ALERT: очередь ChatThrottleLib пропускает их вперёд
    -- остального трафика аддона (кэш стычек и прочее — BULK).
    local function SendQueueMessage(payload)
        local inGuild = {}
        if IsInGuild() then
            ns.SendGuild(payload, "ALERT")
            inGuild = GuildNameSet()
        end
        local wl = ns.GetWhitelistDB()
        if type(wl) ~= "table" then return end
        local me = ns.FormatNameRealm(UnitName("player"))
        local now = GetTime()
        local online = OnlineTargets(wl)
        for nameRealm in pairs(wl) do
            if type(nameRealm) == "string" and online[nameRealm] and nameRealm ~= me
            and not ns.IsBlacklisted(nameRealm) and not inGuild[nameRealm]
            and (whisperOfflineUntil[nameRealm] or 0) < now then
                whisperedAt[nameRealm] = now
                ns.SendWhisper(payload, nameRealm, "ALERT")
            end
        end
    end

    do
        local fmt = ERR_CHAT_PLAYER_NOT_FOUND_S
        local pattern = fmt and ("^" .. fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)") .. "$")
        local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
        if pattern and addFilter then
            addFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
                if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return false end
                local name = msg:match(pattern)
                local nameRealm = name and ns.FormatNameRealm(name)
                local sentAt = nameRealm and whisperedAt[nameRealm]
                if sentAt and GetTime() - sentAt < 10 then
                    whisperOfflineUntil[nameRealm] = GetTime() + OFFLINE_TTL
                    return true
                end
                return false
            end)
        end
    end

    local function MarkHeard(sender)
        local nameRealm = ns.FormatNameRealm(sender)
        if nameRealm then
            whisperOfflineUntil[nameRealm] = nil
            lastHeard[nameRealm] = GetTime()
        end
    end

    -- ============================================================================
    -- COMMUNITY SCAN
    -- ============================================================================
    local function ScheduleCommunityScan()
        if communityScanScheduled then return end
        communityScanScheduled = true
        C_Timer.After(1.0, function()
            communityScanScheduled = false

            if not (C_Club and C_Club.GetSubscribedClubs and C_Club.GetClubMembers and C_Club.GetMemberInfo) then
                communityMembers = nil
                return
            end

            local result = {}
            local ONLINE = Enum and Enum.ClubMemberPresence and Enum.ClubMemberPresence.Online

            for _, club in ipairs(C_Club.GetSubscribedClubs() or {}) do
                local clubId = club.clubId
                if clubId then
                    local list = {}
                    for _, memberId in ipairs(C_Club.GetClubMembers(clubId) or {}) do
                        local info = C_Club.GetMemberInfo(clubId, memberId)
                        if info and info.presence == ONLINE then
                            local name, level = info.name, info.level
                            if name and not (issecretvalue and issecretvalue(name))
                            and level and not (issecretvalue and issecretvalue(level))
                            then
                                local nameRealm = ns.FormatNameRealm(name)
                                if nameRealm and ns.IsInWhitelist(nameRealm) and ns.IsLevel(level) then
                                    list[#list + 1] = {
                                        name = nameRealm,
                                        level = level,
                                        memberId = memberId,
                                    }
                                end
                            end
                        end
                    end
                    if #list > 0 then result[clubId] = list end
                end
            end

            communityMembers = next(result) and result or nil
        end)
    end

    -- ============================================================================
    -- ROSTER SELF-REGISTRATION
    -- ============================================================================
    local function GetMyInfo(queueKey)
        local q = GetQueue(queueKey)
        local info = { queue = queueKey, time = (q and q.serverTime) or myQueueServerTime }

        local roles = {}
        local tank, healer, dps = GetPVPRoles()
        if tank then roles[#roles + 1] = "T" end
        if healer then roles[#roles + 1] = "H" end
        if dps then roles[#roles + 1] = "D" end
        if #roles > 0 then info.roles = table.concat(roles, ";") end

        if not GameLimitedMode_IsActive() then info.subscribed = true end
        local _, _, _, _, _, _, _, isAppearOffline = BNGetInfo()
        if isAppearOffline then info.appearOffline = true end
        return info
    end

    local function EncodeMember(member)
        local flags = ""
        if member.subscribed then flags = flags .. "S" end
        if member.appearOffline then flags = flags .. "A" end
        return (member.name or "") .. "|" .. (member.roles or "") .. "|" .. flags
    end

    local function DecodeMember(token)
        local name, roles, flags = token:match("^([^|]+)|([^|]*)|([^|]*)$")
        if not name then return nil end
        return {
            name = name,
            roles = roles ~= "" and roles or nil,
            subscribed = flags and flags:find("S", 1, true) ~= nil or nil,
            appearOffline = flags and flags:find("A", 1, true) ~= nil or nil,
        }
    end

    local function SerializeInfo(info, echo)
        local parts = { "Q_STAT", info.queue, tostring(info.time) }
        if info.roles then parts[#parts + 1] = "R:" .. info.roles end
        if info.subscribed then parts[#parts + 1] = "S:1" end
        if info.appearOffline then parts[#parts + 1] = "A:1" end
        if echo then parts[#parts + 1] = "E:1" end
        -- Метка сборки: в /dev видно, у кого старые файлы. Старые клиенты
        -- незнакомую часть просто пропускают.
        parts[#parts + 1] = "V:" .. ns.QUEUE_BUILD
        local q = GetQueue(info.queue)
        if q and q.members and #q.members > 1 then
            local encoded = {}
            for _, member in ipairs(q.members) do
                encoded[#encoded + 1] = EncodeMember(member)
            end
            parts[#parts + 1] = "M:" .. table.concat(encoded, "~")
        end
        return table.concat(parts, ",")
    end

    local function WriteRosterEntry(queueKey, nameRealm, entry)
        local bucket = RosterBucket(queueKey)
        if not bucket or not nameRealm then return end
        bucket[nameRealm] = entry
    end

    local function RegisterSelf(queueKey, serverTime)
        local myName = ns.FormatNameRealm(UnitName("player"))
        local info = GetMyInfo(queueKey)
        local q = GetQueue(queueKey)
        local premade = (q and q.members and #q.members > 1) and myName or nil

        WriteRosterEntry(queueKey, myName, {
            time = serverTime,
            queue = queueKey,
            recvTime = GetTime(),
            roles = info.roles,
            subscribed = info.subscribed,
            appearOffline = info.appearOffline,
            premade = premade,
        })
    end

    local function RegisterPremade(queueKey, serverTime, members, leaderName)
        local bucket = RosterBucket(queueKey)
        if not bucket or not members then return end
        for _, member in ipairs(members) do
            bucket[member.name] = {
                time = serverTime,
                queue = queueKey,
                recvTime = GetTime(),
                roles = member.roles,
                subscribed = member.subscribed,
                appearOffline = member.appearOffline,
                premade = leaderName,
            }
        end
    end

    local function RefreshSelf(queueKey)
        local myName = ns.FormatNameRealm(UnitName("player"))
        local entry = RosterGet(queueKey, myName)
        if not entry then return end
        local now = GetTime()
        if entry.premade and entry.premade == myName then
            local bucket = QueueRoster[queueKey]
            for _, data in pairs(bucket) do
                if data.premade == myName then data.recvTime = now end
            end
        else
            entry.recvTime = now
        end
    end

    local function UnregisterSelf(queueKey)
        local myName = ns.FormatNameRealm(UnitName("player"))
        local bucket = queueKey and QueueRoster[queueKey]
        if not bucket then return end
        local entry = bucket[myName]
        if entry and entry.premade and entry.premade == myName then
            for name, data in pairs(bucket) do
                if data.premade == myName then bucket[name] = nil end
            end
        else
            bucket[myName] = nil
        end
    end

    -- ============================================================================
    -- HOST ELECTION
    -- ============================================================================
    local function CleanStaleRoster()
        local now = GetTime()
        for queueKey, bucket in pairs(QueueRoster) do
            if type(bucket) == "table" then
                for nameRealm, data in pairs(bucket) do
                    if type(data) == "table" and data.recvTime and (now - data.recvTime) > 100 then
                        bucket[nameRealm] = nil
                        hostNotified[queueKey] = nil
                    end
                end
            end
        end
    end

    local hostFindResults = {}

    local function CanBeHost(nameRealm, data)
        return data and (not data.premade or data.premade == nameRealm)
    end

    local function SendHostList(queueKey, hostNameRealm)
        local bucket = QueueRoster[queueKey]
        if not bucket then return end
        local validNames = {}
        for nameRealm in pairs(bucket) do
            validNames[#validNames + 1] = nameRealm
        end
        if #validNames == 0 then return end

        -- Опрос — шёпотом каждому из ростера, а не всем (решение автора).
        local message = "H_LIST," .. queueKey .. "," .. table.concat(validNames, ";")
        for nameRealm in pairs(bucket) do
            if nameRealm ~= hostNameRealm then ns.SendWhisper(message, nameRealm, "ALERT") end
        end
    end

    local function CollectHostOwnFriends(queueKey, hostNameRealm)
        local bucket = QueueRoster[queueKey]
        if not bucket then return end
        local own = {}
        for nameRealm in pairs(bucket) do
            if nameRealm ~= hostNameRealm and ns.FindBNetFriendByNameRealm(nameRealm) then
                own[nameRealm] = true
            end
        end
        hostFindResults[queueKey] = hostFindResults[queueKey] or {}
        hostFindResults[queueKey][hostNameRealm] = { friends = own }
    end

    local function ElectHost(queueKey)
        CleanStaleRoster()
        local bucket = queueKey and QueueRoster[queueKey]
        if not bucket then return end

        local count = 0
        local hostName = nil
        local minTime = math.huge

        for nameRealm, data in pairs(bucket) do
            count = count + 1
            if CanBeHost(nameRealm, data) then
                if data.time < minTime
                or (data.time == minTime and (not hostName or nameRealm < hostName)) then
                    minTime = data.time
                    hostName = nameRealm
                end
            end
        end

        local required = GetRosterSize(queueKey)
        if count >= required and hostName then
            local myName = ns.FormatNameRealm(UnitName("player"))
            if hostName == myName then
                if not hostNotified[queueKey] then
                    hostNotified[queueKey] = true
                    print("|cff00ff00[PvP20R Queue]|r Вы выбраны Хостом группы! (" .. count .. " в очереди, нужно " .. required .. ")")
                    hostFindResults[queueKey] = {}
                    CollectHostOwnFriends(queueKey, myName)
                    SendHostList(queueKey, myName)
                    C_Timer.After(8, function()
                        if hostNotified[queueKey] and ns.WargameFlow and ns.WargameFlow.HostDistributeWargames then
                            ns.WargameFlow.HostDistributeWargames(queueKey)
                        end
                    end)
                elseif ns.WargameFlow and ns.WargameFlow.HostDistributeWargames then
                    ns.WargameFlow.HostDistributeWargames(queueKey)
                end
            end
        else
            hostNotified[queueKey] = nil
        end
    end

    -- ============================================================================
    -- HEARTBEAT
    -- ============================================================================
    local function IsRealQueueSuspended()
        local inQueue, paused = false, true
        for i = 1, NUM_LE_LFG_CATEGORYS do
            local mode, submode = GetLFGMode(i)
            if mode and submode ~= "noteleport" then
                inQueue = true
                if mode == "queued" or mode == "abandonedInDungeon"
                    or mode == "rolecheck" or mode == "proposal" then
                    paused = false
                end
            end
        end
        if C_LFGList and C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo() then
            inQueue, paused = true, false
        end
        if C_LFGList and select(2, C_LFGList.GetNumApplications()) > 0 then
            inQueue = true
            for _, app in ipairs(C_LFGList.GetApplications()) do
                if select(2, C_LFGList.GetApplicationInfo(app)) == "applied" then
                    paused = false; break
                end
            end
        end
        for i = 1, GetMaxBattlefieldID() do
            local status, _, _, _, suspend = GetBattlefieldStatus(i)
            if status and status ~= "none" then
                inQueue = true
                if status == "queued" and not suspend then paused = false end
            end
        end
        for i = 1, MAX_WORLD_PVP_QUEUES do
            local status = GetWorldPVPQueueStatus(i)
            if status and status ~= "none" then
                inQueue = true
                if status == "queued" then paused = false end
            end
        end
        if C_PetBattles and C_PetBattles.GetPVPMatchmakingInfo() == "queued" then
            inQueue, paused = true, false
        end
        local inProgress, _, _, _, _, isBG = GetLFGRoleUpdate()
        if inProgress and isBG then inQueue, paused = true, false end
        local rcInProgress, rcIsBG = GetLFGReadyCheckUpdate()
        if rcInProgress and rcIsBG then inQueue, paused = true, false end
        if CanHearthAndResurrectFromArea() then inQueue, paused = true, false end
        return inQueue and paused
    end

    local function IsQueueSuspended()
        return IsRealQueueSuspended()
    end

    local function SendQueueStat(queueKey)
        if IsQueueSuspended() then return end
        if queueKey == "ARENA_5V5" and IsInGroup(1) then
            local n = GetNumGroupMembers(1) or 0
            if n > 1 then
                if not UnitIsGroupLeader("player", 1) or IsInGroup(2) then return end
                for i = 1, n do
                    local unit = "party" .. i
                    if UnitExists(unit) and UnitInOtherParty(unit) then return end
                end
            end
        end
        RefreshSelf(queueKey)
        local payload = SerializeInfo(GetMyInfo(queueKey))
        SendQueueMessage(payload)
        local q = GetQueue(queueKey)
        if q and q.grouped then ns.SendGroup(payload, "ALERT") end
    end

    local function SendQueueLeave(leavingKeys)
        if not leavingKeys or #leavingKeys == 0 then return end
        local parts = { "Q_LEAVE" }
        for _, key in ipairs(leavingKeys) do parts[#parts + 1] = key end
        local payload = table.concat(parts, ",")
        SendQueueMessage(payload)
        if IsInGroup(1) and (GetNumGroupMembers(1) or 0) > 1 then
            ns.SendGroup(payload, "ALERT")
        end
    end

    local function StartHeartbeat(queueKey)
        if not queueKey then return end
        if heartbeatTimers[queueKey] then return end
        heartbeatTimers[queueKey] = C_Timer.NewTicker(90, function()
            if not heartbeatTimers[queueKey] then return end
            local q = GetQueue(queueKey)
            if q and q.startTime then
                SendQueueStat(queueKey)
            else
                if heartbeatTimers[queueKey] then
                    heartbeatTimers[queueKey]:Cancel()
                    heartbeatTimers[queueKey] = nil
                end
            end
        end)
    end

    local function StopHeartbeat(queueKey)
        if not queueKey then
            for key, timer in pairs(heartbeatTimers) do
                timer:Cancel()
                heartbeatTimers[key] = nil
            end
            return
        end
        if heartbeatTimers[queueKey] then
            heartbeatTimers[queueKey]:Cancel()
            heartbeatTimers[queueKey] = nil
        end
    end

    -- ============================================================================
    -- SAVE / RESTORE / CLEAR
    -- ============================================================================
    local function SaveState()
        if not PvP_20_RatingDB then return end
        PvP_20_RatingDB.QueueState = PvP_20_RatingDB.QueueState or {}
        local saved = PvP_20_RatingDB.QueueState
        saved.myQueueStartTime = myQueueStartTime
        saved.myQueueServerTime = myQueueServerTime
        saved.currentState = currentState

        saved.queues = {}
        for _, q in ipairs(customQueues) do
            if q.startTime then
                saved.queues[q.key] = {
                    startTime = q.startTime,
                    serverTime = q.serverTime,
                    found = q.found,
                    grouped = q.grouped,
                    members = q.members,
                }
            end
        end

        local myName = ns.FormatNameRealm(UnitName("player"))
        saved.roster = {}
        for queueKey, bucket in pairs(QueueRoster) do
            if type(bucket) == "table" then
                local copy = {}
                for nameRealm, data in pairs(bucket) do
                    if nameRealm ~= myName or data.premade then
                        copy[nameRealm] = {
                            time = data.time, roles = data.roles,
                            subscribed = data.subscribed, appearOffline = data.appearOffline,
                            premade = data.premade,
                        }
                    end
                end
                if next(copy) then saved.roster[queueKey] = copy end
            end
        end
    end

    local function RestoreState()
        if not PvP_20_RatingDB or not PvP_20_RatingDB.QueueState then return end
        local saved = PvP_20_RatingDB.QueueState
        myQueueStartTime = saved.myQueueStartTime or 0
        myQueueServerTime = saved.myQueueServerTime or 0
        currentState = saved.currentState or QueueState.IDLE

        if saved.queues then
            for _, q in ipairs(customQueues) do
                local s = saved.queues[q.key]
                if s then
                    q.found = s.found
                    q.grouped = s.grouped
                    q.members = s.members
                    q.serverTime = s.serverTime
                    if s.serverTime then
                        q.startTime = GetTime() - math.max(0, GetServerTime() - s.serverTime)
                    else
                        q.serverTime = GetServerTime()
                        q.startTime = GetTime()
                    end
                end
            end
        end

        if saved.roster then
            for key, data in pairs(saved.roster) do
                if type(data) == "table" and data.time and data.queue then
                    WriteRosterEntry(data.queue, key, {
                        time = data.time, queue = data.queue, recvTime = GetTime(),
                        roles = data.roles, subscribed = data.subscribed,
                        appearOffline = data.appearOffline, premade = data.premade,
                    })
                elseif type(data) == "table" then
                    for nameRealm, entry in pairs(data) do
                        if type(entry) == "table" and entry.time then
                            WriteRosterEntry(key, nameRealm, {
                                time = entry.time, queue = key, recvTime = GetTime(),
                                roles = entry.roles, subscribed = entry.subscribed,
                                appearOffline = entry.appearOffline, premade = entry.premade,
                            })
                        end
                    end
                end
            end
        end

        if AnyQueueActive() then
            for _, q in ipairs(customQueues) do
                if q.startTime then
                    local iAmGroupedMember = q.grouped and IsInGroup(1) and not UnitIsGroupLeader("player", 1)
                    if not iAmGroupedMember then
                        if q.members and #q.members > 1 then
                            RegisterPremade(q.key, q.serverTime, q.members, ns.FormatNameRealm(UnitName("player")))
                        else
                            RegisterSelf(q.key, q.serverTime)
                        end
                        SendQueueStat(q.key)
                        StartHeartbeat(q.key)
                    end
                end
            end
            RefreshFrames()
        end
    end

    local function ClearState()
        if PvP_20_RatingDB then PvP_20_RatingDB.QueueState = nil end
        for _, q in ipairs(customQueues) do
            q.startTime = nil
            q.serverTime = nil
            q.found = nil
            q.grouped = nil
            q.members = nil
        end
        myQueueStartTime = 0
        myQueueServerTime = 0
        currentState = QueueState.IDLE
        wipe(QueueRoster)
        StopHeartbeat()
    end

    local function OnReload()
        -- WargameFlow обработает это
        if ns.WargameFlow and ns.WargameFlow.HandleReload then
            ns.WargameFlow.HandleReload()
        end
    end

    -- ============================================================================
    -- ROLE CHECK
    -- ============================================================================
    local StartRoleCheck

    local function CollectGroupMembers(queueKey)
        local myName = ns.FormatNameRealm(UnitName("player"))
        local info = GetMyInfo(queueKey)
        local list = {{
            name = myName,
            roles = info.roles,
            subscribed = info.subscribed,
            appearOffline = info.appearOffline,
        }}
        for name, result in pairs(roleCheckResults) do
            if name ~= myName and result.status == "OK" then
                list[#list + 1] = {
                    name = name,
                    roles = result.roles,
                    subscribed = not result.nosub,
                    appearOffline = result.offline and true or nil,
                }
            end
        end
        return list
    end

    local function ActivateLocalQueue(queueKey, serverTime, grouped)
        local q = GetQueue(queueKey)
        if not q or not serverTime or q.startTime then return end
        q.serverTime = serverTime
        q.grouped = grouped and true or nil
        q.startTime = GetTime() - math.max(0, GetServerTime() - serverTime)
        myQueueStartTime = q.startTime
        myQueueServerTime = serverTime
        currentState = QueueState.QUEUED
        PlaySoundThrottled(SOUNDKIT.PVP_ENTER_QUEUE)
        RefreshFrames()
        SaveState()
    end

    local function DropLocalQueue(queueKey)
        local q = GetQueue(queueKey)
        if q then
            q.startTime = nil
            q.serverTime = nil
            q.found = nil
            q.grouped = nil
            q.members = nil
        end
        QueueRoster[queueKey] = nil
        hostNotified[queueKey] = nil
        StopHeartbeat(queueKey)
        if not AnyQueueActive() then
            currentState = QueueState.IDLE
            myQueueStartTime = 0
            myQueueServerTime = 0
        end
        RefreshFrames()
        SaveState()
    end

    local function JoinQueueByKey(key, skipRoleCheck)
        local q = GetQueue(key)
        if not q then return false end

        if key == "ARENA_5V5" and IsInGroup(1) and (GetNumGroupMembers(1) or 0) > 1 and not UnitIsGroupLeader("player", 1) then
            return false
        end

        if q.startTime then
            UIErrorsFrame:AddMessage(ERR_BATTLEGROUND_DUPE_QUEUE, RED_FONT_COLOR:GetRGB())
            return false
        end

        if key == "ARENA_5V5" and IsInGroup(1) and (GetNumGroupMembers(1) or 0) > 1 then
            for i = 1, GetNumGroupMembers(1) - 1 do
                local unit = "party" .. i
                if UnitExists(unit) and UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") then
                    if not UnitIsConnected(unit) then
                        local msg = ERR_BATTLEGROUND_JOIN_TIMED_OUT:format(ShortName(UnitName(unit)))
                        UIErrorsFrame:AddMessage(msg, RED_FONT_COLOR:GetRGB())
                        return false
                    end
                end
            end
        end

        local groupedJoin = key == "ARENA_5V5" and IsInGroup(1) and (GetNumGroupMembers(1) or 0) > 1 and UnitIsGroupLeader("player", 1)
        if groupedJoin and not skipRoleCheck then
            StartRoleCheck(key)
            return true
        end

        local serverTime = GetServerTime()
        q.found = math.random(1, math.max(q.maxPlayers - 1, 1))
        q.serverTime = serverTime
        q.startTime = GetTime()
        q.grouped = groupedJoin and true or nil
        myQueueStartTime = q.startTime
        myQueueServerTime = serverTime
        currentState = QueueState.QUEUED

        if groupedJoin then
            q.members = CollectGroupMembers(key)
            RegisterPremade(key, serverTime, q.members, ns.FormatNameRealm(UnitName("player")))
        else
            q.members = nil
            RegisterSelf(key, serverTime)
        end

        PlaySoundThrottled(SOUNDKIT.PVP_ENTER_QUEUE)

        local inGroup = (key == "ARENA_5V5") and IsInGroup(1) and (GetNumGroupMembers(1) or 0) > 1
        local joinMsg = inGroup and ERR_GROUP_JOIN_BATTLEGROUND_S or ERR_SOLO_JOIN_BATTLEGROUND_S
        UIErrorsFrame:AddMessage(joinMsg:format(q.title), YELLOW_FONT_COLOR:GetRGB())
        DEFAULT_CHAT_FRAME:AddMessage(YELLOW_FONT_COLOR:WrapTextInColorCode(joinMsg:format(q.title)))

        SendQueueStat(key)
        StartHeartbeat(key)
        RefreshFrames()
        SaveState()
        return true
    end

    -- Только выход из очереди. Состояние варгейма (состав, сбор групп) не трогает:
    -- его сбрасывают те, кому это нужно (ResetWargame ниже). Раньше был флаг
    -- keepWargame ради единственного вызова — выхода из очереди после «Войти».
    local function LeaveQueueByKey(key)
        if IsInGroup(1) and (GetNumGroupMembers(1) or 0) > 1
        and not UnitIsGroupLeader("player", 1) and key == "ARENA_5V5" then
            return false
        end

        local wasActive = AnyQueueActive()

        local leaving = {}
        if key then
            local q = GetQueue(key)
            if q and q.startTime then leaving[#leaving + 1] = q.key end
        else
            for _, q in ipairs(customQueues) do
                if q.startTime then leaving[#leaving + 1] = q.key end
            end
        end

        if #leaving > 0 then SendQueueLeave(leaving) end

        if key == "ARENA_5V5" and IsInGroup(1) and (GetNumGroupMembers(1) or 0) > 1 then
            ns.SendGroup("G_LEAVE," .. key, "ALERT")
        end

        if key then
            local q = GetQueue(key)
            if q then
                q.startTime = nil
                q.serverTime = nil
                q.found = nil
                q.grouped = nil
                q.members = nil
            end
        else
            for _, q in ipairs(customQueues) do
                q.startTime = nil
                q.serverTime = nil
                q.found = nil
                q.grouped = nil
                q.members = nil
            end
        end

        if not AnyQueueActive() then
            currentState = QueueState.IDLE
            myQueueStartTime = 0
            myQueueServerTime = 0
            StopHeartbeat()
            wipe(QueueRoster)
            wipe(hostNotified)
            SaveState()
        else
            if key then
                UnregisterSelf(key)
                StopHeartbeat(key)
                hostNotified[key] = nil
            end
        end

        if wasActive then
            PlaySoundThrottled(SOUNDKIT.LFG_DENIED)
            UIErrorsFrame:AddMessage(ERR_LFG_LEFT_QUEUE, YELLOW_FONT_COLOR:GetRGB())
            DEFAULT_CHAT_FRAME:AddMessage(YELLOW_FONT_COLOR:WrapTextInColorCode(ERR_LFG_LEFT_QUEUE))
            RefreshFrames()
        end

        return true
    end

    local function ResetWargame()
        if ns.WargameFlow then ns.WargameFlow.ResetWargameState() end
    end

    local function LeaveGrouped()
        if not (IsInGroup(1) and (GetNumGroupMembers(1) or 0) > 1) then return end
        if ns.WargameFlow and ns.WargameFlow.IsWargamePaused() then return end

        local queuedArena = GetQueue("ARENA_5V5")
        if queuedArena and queuedArena.grouped then return end

        if roleCheckActive then
            if roleCheckTimer then roleCheckTimer:Cancel(); roleCheckTimer = nil end
            roleCheckActive = false
            roleCheckResults = {}
            roleCheckExpectedPlayers = {}
        end
        local q = GetQueue("ARENA_5V5")
        if q and q.startTime then
            LeaveQueueByKey("ARENA_5V5")
            ResetWargame()
        end
    end

    local function OnGroupRosterUpdate()
        LeaveGrouped()

        if ns.WargameFlow and ns.WargameFlow.HandleGroupRosterUpdate then
            ns.WargameFlow.HandleGroupRosterUpdate()
        end
    end

    -- ============================================================================
    -- ROLE CHECK IMPLEMENTATION
    -- ============================================================================
    local customRoleCheckAcceptButton = nil
    local customRoleCheckDeclineButton = nil
    local roleCheckOnHideHooked = false

    local function FinishRoleCheck(success, missingPlayers)
        roleCheckActive = false
        if roleCheckTimer then roleCheckTimer:Cancel(); roleCheckTimer = nil end
        if success then
            JoinQueueByKey("ARENA_5V5", true)
        else
            PlaySoundThrottled(SOUNDKIT.LFG_DENIED)
            if missingPlayers then
                for _, playerName in ipairs(missingPlayers) do
                    local msg = ERR_LFG_PLAYER_DECLINED_ROLE_CHECK:format(ShortName(playerName))
                    DEFAULT_CHAT_FRAME:AddMessage(YELLOW_FONT_COLOR:WrapTextInColorCode(msg))
                end
            end
        end
    end

    local function ShowRoleCheckPopup(queueName)
        PVPRoleCheckPopup_Display(PVPRoleCheckPopup, queueName)

        if not roleCheckOnHideHooked then
            roleCheckOnHideHooked = true
            PVPRoleCheckPopup:HookScript("OnHide", function()
                if customRoleCheckAcceptButton then customRoleCheckAcceptButton:Hide() end
                if customRoleCheckDeclineButton then customRoleCheckDeclineButton:Hide() end
                if PVPRoleCheckPopupAcceptButton then PVPRoleCheckPopupAcceptButton:Show() end
                if PVPRoleCheckPopupDeclineButton then PVPRoleCheckPopupDeclineButton:Show() end
            end)
        end

        PVPRoleCheckPopupAcceptButton:Hide()
        PVPRoleCheckPopupDeclineButton:Hide()

        if not customRoleCheckAcceptButton then
            customRoleCheckAcceptButton = CreateFrame("Button", nil, PVPRoleCheckPopup, "UIPanelButtonTemplate")
            local real = PVPRoleCheckPopupAcceptButton
            customRoleCheckAcceptButton:SetAllPoints(real)
            customRoleCheckAcceptButton:SetText(real:GetText())

            customRoleCheckAcceptButton:SetScript("OnClick", function(self)
                local roles = {}
                if PVPRoleCheckPopupRoleButtonTank.checkButton:GetChecked() then roles[#roles+1] = "T" end
                if PVPRoleCheckPopupRoleButtonHealer.checkButton:GetChecked() then roles[#roles+1] = "H" end
                if PVPRoleCheckPopupRoleButtonDPS.checkButton:GetChecked() then roles[#roles+1] = "D" end

                SetPVPRoles(
                    #roles > 0 and string.find(table.concat(roles), "T") or false,
                    #roles > 0 and string.find(table.concat(roles), "H") or false,
                    #roles > 0 and string.find(table.concat(roles), "D") or false
                )

                local hasRole = #roles > 0
                local isSubscribed = not GameLimitedMode_IsActive()
                local _, _, _, _, _, _, _, isAppearOffline = BNGetInfo()

                local response = "G_RC_RESP,"
                if not hasRole then
                    response = response .. "NO_ROLES"
                else
                    response = response .. "OK"
                    local flags = {}
                    if isAppearOffline then flags[#flags + 1] = "OFFLINE" end
                    if not isSubscribed then flags[#flags + 1] = "NOSUB" end
                    flags[#flags + 1] = "R:" .. table.concat(roles, ";")
                    response = response .. "," .. table.concat(flags, ",")
                end

                ns.SendGroup(response, "ALERT")
                PVPRoleCheckPopup:Hide()
            end)
        end

        if not customRoleCheckDeclineButton then
            customRoleCheckDeclineButton = CreateFrame("Button", nil, PVPRoleCheckPopup, "UIPanelButtonTemplate")
            local real = PVPRoleCheckPopupDeclineButton
            customRoleCheckDeclineButton:SetAllPoints(real)
            customRoleCheckDeclineButton:SetText(real:GetText())
            customRoleCheckDeclineButton:SetScript("OnClick", function(self)
                ns.SendGroup("G_RC_RESP,NO_ROLES", "ALERT")
                PVPRoleCheckPopup:Hide()
            end)
        end

        customRoleCheckAcceptButton:Show()
        customRoleCheckDeclineButton:Show()
    end

    StartRoleCheck = function(queueKey)
        if roleCheckActive then return end
        local q = GetQueue(queueKey)
        if not q then return end
        roleCheckLeader = ns.FormatNameRealm(UnitName("player"))
        ns.SendGroup("G_RC," .. q.key, "ALERT")
    end

    local function OnRoleCheck(sender, queueTitle)
        local senderNameRealm = ns.FormatNameRealm(sender)
        if not senderNameRealm or not queueTitle or queueTitle == "" then return end
        if not (IsInGroup(1) and (GetNumGroupMembers(1) or 0) > 1) then return end

        PlaySoundThrottled(SOUNDKIT.READY_CHECK)
        DEFAULT_CHAT_FRAME:AddMessage(YELLOW_FONT_COLOR:WrapTextInColorCode(ERR_LFG_ROLE_CHECK_INITIATED))
        UIErrorsFrame:AddMessage(ERR_LFG_ROLE_CHECK_INITIATED, YELLOW_FONT_COLOR:GetRGB())

        roleCheckResults = {}
        roleCheckActive = true
        roleCheckExpectedPlayers = {}

        local numMembers = GetNumGroupMembers(1) or 0
        for i = 1, numMembers - 1 do
            local unit = "party" .. i
            if UnitExists(unit) and UnitIsPlayer(unit) then
                local nameRealm = ns.FormatNameRealm(UnitName(unit))
                if nameRealm and nameRealm ~= ns.FormatNameRealm(UnitName("player")) then
                    roleCheckExpectedPlayers[nameRealm] = true
                end
            end
        end

        if UnitIsGroupLeader("player", 1) then
            local tank, healer, dps = GetPVPRoles()
            local roles = {}
            if tank then roles[#roles + 1] = "T" end
            if healer then roles[#roles + 1] = "H" end
            if dps then roles[#roles + 1] = "D" end
            if #roles > 0 then
                local rolesStr = table.concat(roles, ";")
                ns.SendGroup("G_RC_RESP,OK,R:" .. rolesStr, "ALERT")
                roleCheckResults[ns.FormatNameRealm(UnitName("player"))] = {
                    status = "OK",
                    offline = false,
                    nosub = false,
                    roles = rolesStr
                }
            end
        else
            if PVPRoleCheckPopup and PVPRoleCheckPopup:IsShown() then return end
            ShowRoleCheckPopup(queueTitle)
        end

        if roleCheckTimer then roleCheckTimer:Cancel() end
        roleCheckTimer = C_Timer.NewTimer(10, function()
            if not roleCheckActive then return end
            local missing = {}
            for nameRealm in pairs(roleCheckExpectedPlayers) do
                if not roleCheckResults[nameRealm] or roleCheckResults[nameRealm].status == "NO_ROLES" then
                    missing[#missing + 1] = nameRealm
                end
            end
            FinishRoleCheck(#missing == 0, missing)
        end)
    end

    local function OnRoleResponse(sender, rawMessage)
        local senderNameRealm = ns.FormatNameRealm(sender)
        if not senderNameRealm then return end
        local parts = {}
        for part in rawMessage:gmatch("([^,]+)") do parts[#parts + 1] = part end
        if #parts < 2 or parts[1] ~= "G_RC_RESP" then return end

        local status = parts[2]
        local flags = {}
        local rolesStr = nil
        for i = 3, #parts do
            if parts[i]:sub(1, 2) == "R:" then rolesStr = parts[i]:sub(3)
            else flags[parts[i]] = true end
        end

        if status == "OK" and rolesStr then
            local icons = {}
            for role in rolesStr:gmatch("([^;]+)") do
                if role == "T" then icons[#icons + 1] = INLINE_TANK_ICON .. " " .. TANK
                elseif role == "H" then icons[#icons + 1] = INLINE_HEALER_ICON .. " " .. HEALER
                elseif role == "D" then icons[#icons + 1] = INLINE_DAMAGER_ICON .. " " .. DAMAGE
                end
            end
            local msg = LFG_ROLE_CHECK_ROLE_CHOSEN:format(ShortName(senderNameRealm), table.concat(icons, ", "))
            DEFAULT_CHAT_FRAME:AddMessage(YELLOW_FONT_COLOR:WrapTextInColorCode(msg))
        end

        roleCheckResults[senderNameRealm] = {
            status = status, offline = flags["OFFLINE"] or false,
            nosub = flags["NOSUB"] or false, roles = rolesStr,
        }

        local numMembers = GetNumGroupMembers(1) or 0
        if numMembers <= 1 then
            FinishRoleCheck(true)
            return
        end

        local allReady = true
        for i = 1, numMembers - 1 do
            local unit = "party" .. i
            if UnitExists(unit) and UnitIsPlayer(unit) then
                local nameRealm = ns.FormatNameRealm(UnitName(unit))
                if nameRealm and nameRealm ~= ns.FormatNameRealm(UnitName("player")) then
                    local r = roleCheckResults[nameRealm]
                    if not r or r.status == "NO_ROLES" then allReady = false end
                end
            end
        end
        if allReady then FinishRoleCheck(true) end
    end

    -- ============================================================================
    -- HOST FIND
    -- ============================================================================
    local function OnHostList(sender, rawMessage)
        local senderNameRealm = ns.FormatNameRealm(sender)
        if not senderNameRealm then return end
        local queueKey, nameList = rawMessage:match("^H_LIST,([^,]+),(.+)$")
        if not queueKey or not RosterGet(queueKey, senderNameRealm) then return end

        local found = {}
        local myName = ns.FormatNameRealm(UnitName("player"))
        for nameRealm in nameList:gmatch("([^;]+)") do
            if nameRealm ~= "" and nameRealm ~= myName then
                if ns.FindBNetFriendByNameRealm(nameRealm) then
                    found[#found + 1] = nameRealm
                end
            end
        end

        local report = string.format("H_LIST_RESP,%s,%s,%d,%s",
            queueKey, myName, #found, table.concat(found, ";"))
        -- Ответ нужен только хосту — шёпотом ему, а не всем (просьба автора).
        ns.SendWhisper(report, senderNameRealm, "ALERT")
    end

    local function AnalyzeConnections(queueKey)
        local known = hostFindResults[queueKey] or {}
        for player, data in pairs(known) do
            local names = {}
            for name in pairs(data.friends) do names[#names + 1] = name end
            if #names > 0 then
                print(("|cff00ff00%s|r дружит с: %s"):format(player, table.concat(names, ", ")))
            else
                print(("|cffff0000%s|r не имеет BNet-друзей среди участников"):format(player))
            end
        end
    end

    local function OnFindOk(sender, rawMessage)
        local senderNameRealm = ns.FormatNameRealm(sender)
        if not senderNameRealm then return end
        local parts = {}
        for part in rawMessage:gmatch("([^,]+)") do parts[#parts + 1] = part end

        if #parts >= 4 and parts[1] == "H_LIST_RESP" then
            local queueKey = parts[2]
            local reporter = parts[3]
            local bucket = QueueRoster[queueKey]
            if not bucket then return end
            local found = {}
            if parts[5] and parts[5] ~= "" then
                for name in parts[5]:gmatch("([^;]+)") do found[name] = true end
            end
            hostFindResults[queueKey] = hostFindResults[queueKey] or {}
            hostFindResults[queueKey][reporter] = { friends = found, totalFound = tonumber(parts[4]) or 0 }

            local expected, received = 0, 0
            for nameRealm in pairs(bucket) do
                expected = expected + 1
                if hostFindResults[queueKey][nameRealm] then received = received + 1 end
            end

            if ns.QLog and hostNotified[queueKey] then
                ns.QLog(("хост: ответили на опрос %d/%d"):format(received, expected))
            end
            if received >= expected and expected > 0 then
                local myName = ns.FormatNameRealm(UnitName("player"))
                local hostName, minTime = nil, math.huge
                for nameRealm, data in pairs(bucket) do
                    if CanBeHost(nameRealm, data) and (data.time < minTime
                    or (data.time == minTime and (not hostName or nameRealm < hostName))) then
                        minTime = data.time
                        hostName = nameRealm
                    end
                end
                if hostName == myName then
                    AnalyzeConnections(queueKey)
                    if ns.WargameFlow and ns.WargameFlow.HostDistributeWargames then
                        ns.WargameFlow.HostDistributeWargames(queueKey)
                    end
                end
            end
        end
    end

    -- ============================================================================
    -- MESSAGE HANDLERS
    -- ============================================================================
    local function OnQueueStatus(sender, rawMessage)
        local senderNameRealm = ns.FormatNameRealm(sender)
        if not senderNameRealm then return end
        if not ns.IsInWhitelist(senderNameRealm) and not IsGuildMember(senderNameRealm) then return end
        local parts = {}
        for part in rawMessage:gmatch("([^,]+)") do parts[#parts + 1] = part end

        if #parts >= 3 and parts[1] == "Q_STAT" then
            local queueKey = parts[2]
            local qTime = tonumber(parts[3])
            if not qTime or not GetQueue(queueKey) then return end
            local roles, subscribed, appearOffline, echo, build
            local members
            for i = 4, #parts do
                local part = parts[i]
                if part:sub(1, 2) == "R:" then roles = part:sub(3)
                elseif part == "S:1" then subscribed = true
                elseif part == "A:1" then appearOffline = true
                elseif part == "E:1" then echo = true
                elseif part:sub(1, 2) == "V:" then build = part:sub(3)
                elseif part:sub(1, 2) == "M:" then
                    members = {}
                    for token in part:sub(3):gmatch("[^~]+") do
                        local member = DecodeMember(token)
                        if member then members[#members + 1] = member end
                    end
                end
            end

            local bucket = RosterBucket(queueKey)
            if members and #members > 0 then
                for name, data in pairs(bucket) do
                    if data.premade == senderNameRealm then bucket[name] = nil end
                end
                for _, member in ipairs(members) do
                    bucket[member.name] = {
                        time = qTime, queue = queueKey, recvTime = GetTime(),
                        roles = member.roles, subscribed = member.subscribed,
                        appearOffline = member.appearOffline, premade = senderNameRealm,
                    }
                end
            else
                bucket[senderNameRealm] = {
                    time = qTime, queue = queueKey, recvTime = GetTime(),
                    roles = roles, subscribed = subscribed, appearOffline = appearOffline,
                    build = build,
                }
            end
            ElectHost(queueKey)
            RefreshFrames()

            local myName = ns.FormatNameRealm(UnitName("player"))
            local q = GetQueue(queueKey)
            if not echo and q and q.startTime and myName ~= senderNameRealm then
                local stampKey = queueKey .. "\0" .. senderNameRealm
                local now = GetTime()
                if not lastRosterEcho[stampKey] or now - lastRosterEcho[stampKey] > 20 then
                    lastRosterEcho[stampKey] = now
                    -- Эхо — только новичку: остальные в очереди уже знают нас по heartbeat.
                    -- Раньше уходило всем (гильдия + шёпот по списку) от каждого стоящего.
                    ns.SendWhisper(SerializeInfo(GetMyInfo(queueKey), true), senderNameRealm, "ALERT")
                end
            end
            if myName ~= senderNameRealm and members then
                for _, member in ipairs(members) do
                    if member.name == myName then
                        ActivateLocalQueue(queueKey, qTime, true)
                        break
                    end
                end
            end
        end
    end

    local function OnQueueLeave(sender, rawMessage)
        local senderNameRealm = ns.FormatNameRealm(sender)
        if not senderNameRealm then return end
        local parts = {}
        for part in rawMessage:gmatch("([^,]+)") do parts[#parts + 1] = part end
        if #parts < 2 or parts[1] ~= "Q_LEAVE" then return end

        local myName = ns.FormatNameRealm(UnitName("player"))
        for i = 2, #parts do
            local queueKey = parts[i]
            local bucket = QueueRoster[queueKey]
            local entry = bucket and bucket[senderNameRealm]
            if entry then
                if entry.premade and entry.premade == senderNameRealm then
                    for name, data in pairs(bucket) do
                        if data.premade == senderNameRealm then bucket[name] = nil end
                    end
                else
                    bucket[senderNameRealm] = nil
                end
                hostNotified[queueKey] = nil
                local q = GetQueue(queueKey)
                if q and q.grouped and senderNameRealm ~= myName and not UnitIsGroupLeader("player", 1) then
                    DropLocalQueue(queueKey)
                else
                    ElectHost(queueKey)
                end
                RefreshFrames()
            end
        end
    end

    local function OnQueueGroupLeave(sender, rawMessage)
        local senderNameRealm = ns.FormatNameRealm(sender)
        if not senderNameRealm then return end
        
        local parts = {}
        for part in rawMessage:gmatch("([^,]+)") do parts[#parts + 1] = part end
        if #parts < 2 or parts[1] ~= "G_LEAVE" then return end
        
        local queueKey = parts[2]
        if queueKey ~= "ARENA_5V5" then return end
        
        -- Проигрываем звук выхода
        PlaySoundThrottled(SOUNDKIT.LFG_DENIED)
        
        -- Показываем сообщение в чат
        DEFAULT_CHAT_FRAME:AddMessage(YELLOW_FONT_COLOR:WrapTextInColorCode(ERR_LFG_LEFT_QUEUE))
        
        -- Показываем сообщение в ErrorFrame
        UIErrorsFrame:AddMessage(ERR_LFG_LEFT_QUEUE, YELLOW_FONT_COLOR:GetRGB())
        
        -- Скрываем глаз только если нет других активных кастомных очередей
        -- Blizzard сам управляет глазом для оригинальных очередей
        if not AnyQueueActive() then
            if QueueStatusButton and QueueStatusButton.Eye then
                QueueStatusButton.Eye:SetStaticMode(true)
                QueueStatusButton.Eye:StopAnimating()
                if QueueStatusButton.Eye.SetSearchingAnimation then
                    QueueStatusButton.Eye:SetSearchingAnimation(false)
                end
            end
        end
        
        -- Обновляем фрейм статуса очереди
        RefreshFrames()
    end


    local function OnMessage(sender, message)
        if not message or message == "" then return end

        local myName = ns.FormatNameRealm(UnitName("player"))
        local senderNameRealm = ns.FormatNameRealm(sender)
        local isSelf = (senderNameRealm == myName)

        local function Starts(token)
            return message:sub(1, #token) == token
        end

        if ns.WargameFlow and ns.WargameFlow.IsWargamePaused()
        and not (ns.WargameFlow.IsInRoster and ns.WargameFlow.IsInRoster(senderNameRealm))
        and not Starts("Q_LEAVE,") then
            return
        end

        if Starts("Q_NOTE,") then
            print("|cff00ff00[PvP20R Queue]|r " .. message:sub(8))
        elseif Starts("Q_LEAVE,") then
            OnQueueLeave(sender, message)
        elseif Starts("Q_STAT,") then
            if not isSelf then
                OnQueueStatus(sender, message)
            end
        elseif Starts("G_LEAVE,") then
            OnQueueGroupLeave(sender, message)
        elseif Starts("G_RC_RESP,") then
            OnRoleResponse(sender, message)
        elseif Starts("G_RC,") then
            local q = GetQueue(message:sub(6))
            if q then OnRoleCheck(sender, q.title) end
        elseif Starts("H_LIST_RESP,") then
            if not isSelf then
                OnFindOk(sender, message)
            end
        elseif Starts("H_LIST,") then
            if not isSelf then
                OnHostList(sender, message)
            end
        elseif ns.WargameFlow and ns.WargameFlow.HandleMessage then
            ns.WargameFlow.HandleMessage(sender, message)
        end
    end

    -- ============================================================================
    -- UI HOOKS
    -- ============================================================================
    local function SetupMenuHook()
        if not Menu or not Menu.ModifyMenu then return false end
        if queueMenuHooked then return true end
        queueMenuHooked = true

        Menu.ModifyMenu("MENU_QUEUE_STATUS_FRAME", function(owner, rootDescription)
            if owner ~= QueueStatusButton then return end
            if currentState == QueueState.IDLE or not AnyQueueActive() then return end

            for _, q in ipairs(customQueues) do
                if q.startTime then
                    local name = q.title
                    if currentState == QueueState.MATCHED then name = "|cff19ff19" .. name .. "|r" end
                    rootDescription:CreateTitle(name)
                    local btn = rootDescription:CreateButton(LEAVE_QUEUE, function() LeaveQueueByKey(q.key); ResetWargame() end)
                    if IsInGroup(1) and not UnitIsGroupLeader("player", 1) and q.key == "ARENA_5V5" then
                        btn:SetEnabled(false)
                    end
                end
            end
        end)
        return true
    end

    local function QueueStatusHook()
        if QueueStatusFrame and QueueStatusFrame.Update and not queueUpdateHooked then
            queueUpdateHooked = true

            hooksecurefunc(QueueStatusFrame, "Update", function(self)
                if currentState == QueueState.IDLE or not AnyQueueActive() then return end
                if not QueueStatusButton:IsShown() then QueueStatusButton:Show() end

                for _, q in ipairs(customQueues) do
                    if q.startTime then
                        local entry = self:GetEntry(q.orderIndex)

                        if IsQueueSuspended() then
                            QueueStatusEntry_SetMinimalDisplay(entry, q.title, QUEUED_STATUS_SUSPENDED)
                        else
                            local realCount = 0
                            local bucket = QueueRoster[q.key]
                            if type(bucket) == "table" then
                                for _ in pairs(bucket) do realCount = realCount + 1 end
                            end
                            if realCount == 0 and q.startTime then realCount = 1 end
                            -- Больше мест в ростере — хост ещё подбирает состав: 7/6 и 8/6 путают,
                            -- показываем «одного не хватает».
                            if realCount > q.maxPlayers then realCount = q.maxPlayers - 1 end

                            local subTitle = currentState == QueueState.QUEUED
                                and (BATTLEFIELD_QUEUE_STATUS .. ": %d/%d"):format(realCount, q.maxPlayers)

                            if QueueStatusEntry_SetFullDisplay then
                                QueueStatusEntry_SetFullDisplay(
                                    entry, q.title, q.startTime,
                                    nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                                    subTitle, nil, nil
                                )
                            else
                                if entry.Title then entry.Title:SetText(q.title) end
                                if entry.Status then entry.Status:Hide() end
                                if entry.SubTitle and subTitle then
                                    entry.SubTitle:SetText(subTitle)
                                    entry.SubTitle:Show()
                                end
                            end

                            local ti, sub, tq = entry.Title, entry.SubTitle, entry.TimeInQueue
                            local titleH = (ti and ti:GetHeight()) or 0
                            local height = 14 + titleH

                            if sub and sub:IsShown() then
                                sub:ClearAllPoints()
                                sub:SetPoint("TOPLEFT", entry, "TOPLEFT", 10, -(height + 5))
                                height = height + (sub:GetHeight() or 0)
                            end
                            if tq and tq:IsShown() then
                                tq:ClearAllPoints()
                                tq:SetPoint("TOPLEFT", entry, "TOPLEFT", 10, -(height + 5))
                                height = height + (tq:GetHeight() or 0)
                            end

                            entry:SetHeight(height + 14)
                        end
                        entry:Show()
                    end
                end

                if QueueStatusFrame_SortAndAnchorEntries then
                    for entry in self.statusEntriesPool:EnumerateActive() do
                        if entry.EntrySeparator then entry.EntrySeparator:Show() end
                    end
                    QueueStatusFrame_SortAndAnchorEntries(self)
                end

                local totalHeight = 4
                for entry in self.statusEntriesPool:EnumerateActive() do
                    totalHeight = totalHeight + entry:GetHeight()
                end
                self:SetHeight(totalHeight)

                if not IsQueueSuspended() then
                    QueueStatusButton.Eye:SetStaticMode(false)
                end
            end)
        end

        if not eyeFlickerFixed then
            eyeFlickerFixed = true
            local origStartInitial = QueueStatusButton.Eye.StartInitialAnimation
            QueueStatusButton.Eye.StartInitialAnimation = function(self)
                if AnyQueueActive() then self:StartSearchingAnimation()
                else origStartInitial(self) end
            end
            QueueStatusButton:HookScript("OnHide", function(self)
                if AnyQueueActive() then
                    self:Show()
                    self.Eye:SetStaticMode(false)
                end
            end)
        end

        SetupMenuHook()
    end

    -- ============================================================================
    -- EVENT FRAME
    -- ============================================================================
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_LOGOUT")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("CLUB_ADDED")
    f:RegisterEvent("CLUB_REMOVED")
    f:RegisterEvent("CLUB_MEMBER_ADDED")
    f:RegisterEvent("CLUB_MEMBER_REMOVED")
    f:RegisterEvent("CLUB_MEMBER_UPDATED")
    f:RegisterEvent("CLUB_MEMBER_PRESENCE_UPDATED") -- зашёл/вышел: список онлайн для шёпота

    f:SetScript("OnEvent", function(self, event, ...)
        if event == "ADDON_LOADED" then
            local arg1 = ...
            if arg1 == addonName then
                QueueStatusHook()
                SetupMenuHook()
                RestoreState()
            end
        elseif event == "PLAYER_LOGIN" then
            ScheduleCommunityScan()
        elseif event == "PLAYER_ENTERING_WORLD" then
            local init, reload = ...
            if init and not reload then
                ClearState()
            elseif reload then
                OnReload()
            end
        elseif event == "PLAYER_LOGOUT" then
            SaveState()
            StopHeartbeat()
        elseif event == "GROUP_ROSTER_UPDATE" then
            OnGroupRosterUpdate()
        elseif event == "CLUB_ADDED" or event == "CLUB_REMOVED"
            or event == "CLUB_MEMBER_ADDED" or event == "CLUB_MEMBER_REMOVED"
            or event == "CLUB_MEMBER_UPDATED" or event == "CLUB_MEMBER_PRESENCE_UPDATED" then
            ScheduleCommunityScan()
        elseif event == "CHAT_MSG_ADDON" then
            local prefix, text, _, sender = ...
            if prefix == ns.PREFIX and text and text ~= "" then
                text = ns.UnpackQueueKeys(text)
                MarkHeard(sender)
                if text:sub(1, 6) == "Q_STAT"
                or text:sub(1, 6) == "Q_NOTE"
                or text:sub(1, 7) == "Q_LEAVE"
                or text:sub(1, 7) == "G_LEAVE"
                or text:sub(1, 4) == "G_RC"
                or text:sub(1, 9) == "G_RC_RESP"
                or text:sub(1, 6) == "H_LIST"
                or text:sub(1, 11) == "H_LIST_RESP" then
                    OnMessage(sender, text)
                elseif ns.WargameFlow and ns.WargameFlow.HandleMessage then
                    ns.WargameFlow.HandleMessage(sender, text)
                end
            end
        end
    end)

    -- ============================================================================
    -- EXPORT
    -- ============================================================================

    function ns.JoinSoloShuffle()
        return JoinQueueByKey("SOLO_SHUFFLE")
    end

    function ns.JoinArena5v5()
        return JoinQueueByKey("ARENA_5V5")
    end

    ns.StateMachine = {
        JoinSoloShuffle = function() return
            JoinQueueByKey("SOLO_SHUFFLE")
        end,
        JoinArena5v5 = function() return JoinQueueByKey("ARENA_5V5") end,
        LeaveQueueByKey = LeaveQueueByKey,
        HandleQueueMessage = OnMessage,
        IsAnyQueueActive = AnyQueueActive,
        GetQueueState = function() return currentState end,
        GetQueueRoster = function() return QueueRoster end,
        SendQueueMessage = SendQueueMessage,
        -- роли команды от хоста: { [имя] = "HEALER"/"DAMAGER"/"TANK" } или nil, если не собрать
        AssignTeamRoles = AssignTeamRoles,
        QueueFriendSender = function(queueKey, a, b)
            local known = hostFindResults[queueKey]
            if not known or not a or not b then return nil end
            local ra, rb = known[a], known[b]
            if ra and ra.friends and ra.friends[b] then return a end
            if rb and rb.friends and rb.friends[a] then return b end
            return nil
        end,
        GetConstraints = GetConstraints,
        IsQueueSuspended = IsQueueSuspended,
        SetQueueMatched = function()
            if not AnyQueueActive() then return end
            currentState = QueueState.MATCHED
            for _, q in ipairs(customQueues) do
                if q.startTime then q.found = q.maxPlayers end
            end
            RefreshFrames()
        end,
        UpdateQueueFound = function(key, found)
            local q = GetQueue(key)
            if q and q.startTime then
                q.found = math.min(found, q.maxPlayers)
                RefreshFrames()
            end
        end,
    }