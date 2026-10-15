local addonName, ns = ...

-- ============================================================================
-- LOCAL CONSTANTS (Throttling & Timers)
-- ============================================================================
local INSPECT_READY_THROTTLE   = 1.5
local INSPECT_TICK_INTERVAL    = 2
local MOUSEOVER_RETRY_INTERVAL = 2
local INSPECT_RETRY_INTERVAL   = 10
local INSPECT_REQUEUE_DELAY    = 5
local GROUP_QUEUE_DELAY        = 20
local POST_ARENA_MAX_RETRIES   = 2

-- ============================================================================
-- STATE
-- ============================================================================
local inspectQuery, inspectOrder = {}, {}
local lastCheckNext, lastCheckNextGuid, cooldownGuid = {}, {}, {}
local trackedGuids, unitToGuid = {}, {}
local scheludedQueue, inspectTicker = nil, nil
local inspected, inspectCompleted, inspectUnitByGuid = {}, {}, {}
local priorityInspectUnit = nil
local lastAttempt, mouseoverPending = {}, {}
local lastMouseoverGUID = nil
local lastInspectReady = {}
local inspectDataOwnerGuid = nil
local postArena = nil

-- ============================================================================
-- UTILITIES
-- ============================================================================
local function GuidOnCooldown(guid)
	local last = lastCheckNextGuid[guid]
	return last ~= nil and (GetTime() - last) <= INSPECT_RETRY_INTERVAL
end

local function TrackUnit(unit, guid)
	trackedGuids[guid] = unit
	unitToGuid[unit] = guid
end

local function ReleaseUnit(unit)
	local guid = unitToGuid[unit] or ns.SafeGuid(UnitGUID(unit))
	if guid and trackedGuids[guid] == unit then trackedGuids[guid] = nil end
	unitToGuid[unit] = nil
end

local function RemoveFromQueue(unit)
	inspectQuery[unit] = nil
	for i = #inspectOrder, 1, -1 do
		if inspectOrder[i] == unit then table.remove(inspectOrder, i) end
	end
end

local function UnitIsInspected(unit)
	local guid = ns.SafeGuid(UnitGUID(unit))
	return guid ~= nil and inspected[guid] == true
end

local function FindAlliesInGroup(allyGuids)
	local units = {}
	if not allyGuids or not next(allyGuids) then return units end
	local candidates = {}
	for i = 1, 4  do candidates[#candidates + 1] = "party" .. i end
	for i = 1, 40 do candidates[#candidates + 1] = "raid" .. i end
	for _, u in ipairs(candidates) do
		if UnitExists(u) and not UnitIsUnit(u, "player") then
			local g = ns.SafeGuid(UnitGUID(u))
			if g and allyGuids[g] then units[#units + 1] = u end
		end
	end
	return units
end

-- ============================================================================
-- INSPECTION QUEUE
-- ============================================================================
local function AddInspectToQueue(unit)
	if not unit or not CanInspect(unit, false) then return end
	local isSelf = UnitIsUnit(unit, "player")
	if not isSelf then
		if not UnitIsPlayer(unit) or not UnitExists(unit) or not UnitIsConnected(unit) then return end
		if UnitInOtherParty(unit) or not ns.IsLevel(UnitLevel(unit)) or UnitIsInspected(unit) then return end
	end
	local guid = ns.SafeGuid(UnitGUID(unit))
	if not guid or trackedGuids[guid] or GuidOnCooldown(guid) then return end
	
	local last = lastCheckNext[unit]
	if last and (GetTime() - last) <= INSPECT_RETRY_INTERVAL and cooldownGuid[unit] == guid then return end
	
	if not inspectQuery[unit] then
		inspectQuery[unit] = GetTime()
		inspectOrder[#inspectOrder + 1] = unit
		TrackUnit(unit, guid)
	end
end

-- ============================================================================
-- POST ARENA DATA
-- ============================================================================
local function CollectPostArenaData()
	local enemyNames, allyGuids, allyNames = {}, {}, {}
	local myGuid = UnitGUID("player")
	local total = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
	if total == 0 then return enemyNames, allyGuids, allyNames end
	
	local myFaction
	for i = 1, total do
		local ok, score = pcall(C_PvP.GetScoreInfo, i)
		if ok and score and score.guid == myGuid then
			myFaction = score.faction
			break
		end
	end
	
	for i = 1, total do
		local ok, score = pcall(C_PvP.GetScoreInfo, i)
		if ok and score and score.guid and score.guid ~= myGuid then
			local guid = ns.SafeGuid(score.guid) or score.guid
			local name = (score.name and score.name ~= "") and ns.FormatNameRealm(score.name) or nil
			if myFaction ~= nil and score.faction == myFaction then
				allyGuids[guid] = true
				if name then allyNames[guid] = name end
			else
				if name then enemyNames[#enemyNames + 1] = name end
			end
		end
	end
	return enemyNames, allyGuids, allyNames
end

local function FinishPostArena()
	if not postArena then return end
	local enemyNames, allyGuids, allyNames = postArena.enemyNames, postArena.allyGuids, postArena.allyNames
	postArena = nil
	if not enemyNames or #enemyNames == 0 then return end
	
	local db = ns.SkirmishDB
	if type(db) ~= "table" then return end
	
	local now = time()
	local myGuid = UnitGUID("player")
	
	local function FreshRecord(guid)
		local rec = db[guid]
		if type(rec) == "table" and (tonumber(rec.rating) or 0) > 0 and ns.IsNew(rec.lastUpdate) then
			return {
				n = rec.name, r = rec.rating, b = rec.bestRating or rec.rating,
				p = rec.played or 0, w = rec.won or 0, c = rec.class, u = rec.lastUpdate or now,
			}
		end
	end
	
	local myRecord = myGuid and FreshRecord(myGuid) or nil
	local enemyPayloadRecords = {}
	if myRecord then enemyPayloadRecords[myGuid] = myRecord end
	for guid in pairs(allyGuids or {}) do
		if guid ~= myGuid then 
			local rec = FreshRecord(guid)
			if rec then enemyPayloadRecords[guid] = rec end 
		end
	end
	
	if next(enemyPayloadRecords) then
		local enemyPayload = ns.EncodeSnapshot(enemyPayloadRecords)
		if enemyPayload then
			for _, name in ipairs(enemyNames) do
				ns.SendWhisper(enemyPayload, name)
			end
		end
	end
	
	if myRecord and allyGuids and allyNames then
		local allyPayload = ns.EncodeSnapshot({ [myGuid] = myRecord })
		if allyPayload then
			for guid in pairs(allyGuids) do
				if guid ~= myGuid then
					local allyName = allyNames[guid]
					if allyName then 
						ns.SendWhisper(allyPayload, allyName) 
					end
				end
			end
		end
	end
end

-- ============================================================================
-- POST ARENA KICK
-- ============================================================================
local function PostArenaKick()
	if not postArena or not postArena.active then return end
	if UnitIsDeadOrGhost("player") or C_PvP.IsMatchComplete() then return end
	if InspectFrame and InspectFrame:IsShown() then return end
	if InCombatLockdown() or UnitAffectingCombat("player") then return end
	
	local enqueueSelf
	enqueueSelf = function()
		if not postArena or not postArena.active or postArena.selfDone or postArena.awaitingSelf then return end
		AddInspectToQueue("player")
		if not inspectQuery["player"] then
			C_Timer.After(2, function()
				if postArena and postArena.active and not postArena.selfDone and not postArena.awaitingSelf then enqueueSelf() end
			end)
			return
		end
		postArena.awaitingSelf = true
		C_Timer.After(INSPECT_REQUEUE_DELAY, function()
			if postArena and postArena.active and postArena.awaitingSelf then
				postArena.awaitingSelf = false
				PostArenaKick()
			end
		end)
	end
	enqueueSelf()
	
	if postArena.pendingAllies then
		for _, u in ipairs(FindAlliesInGroup(postArena.allyGuids)) do
			local g = ns.SafeGuid(UnitGUID(u))
			if g and postArena.pendingAllies[g] then
				if u and not UnitIsUnit(u, "player") and UnitExists(u) and UnitIsConnected(u) and not UnitInOtherParty(u) then
					AddInspectToQueue(u)
				end
			end
		end
	end
end

local function ClearPendingAlly(guid)
	if postArena and postArena.active and postArena.pendingAllies and postArena.pendingAllies[guid] then
		postArena.pendingAllies[guid] = nil
		if postArena.allyRetries then postArena.allyRetries[guid] = nil end
		if not next(postArena.pendingAllies) then
			if postArena.selfDone then FinishPostArena() else PostArenaKick() end
		else 
			PostArenaKick() 
		end
	end
end

-- ============================================================================
-- INSPECTION QUEUE TICK
-- ============================================================================
local function InspectNext()
	if UnitIsDeadOrGhost("player") or C_PvP.IsMatchComplete() then return end
	if InspectFrame and InspectFrame:IsShown() then return end
	if InCombatLockdown() or UnitAffectingCombat("player") then return end
	
	local nowTime = GetTime()
	local candidates = {}
	if priorityInspectUnit and inspectQuery[priorityInspectUnit] then candidates[#candidates + 1] = priorityInspectUnit end
	for _, unit in ipairs(inspectOrder) do
		if unit ~= priorityInspectUnit and inspectQuery[unit] then candidates[#candidates + 1] = unit end
	end
	
	for _, unit in ipairs(candidates) do
		local retryInterval = mouseoverPending[unit] and MOUSEOVER_RETRY_INTERVAL or INSPECT_REQUEUE_DELAY
		if not UnitExists(unit) or not UnitIsConnected(unit) or (not UnitIsUnit(unit, "player") and UnitInOtherParty(unit)) or UnitIsInspected(unit) then
			ReleaseUnit(unit)
			RemoveFromQueue(unit)
			lastAttempt[unit] = nil
			mouseoverPending[unit] = nil
			if priorityInspectUnit == unit then priorityInspectUnit = nil end
		elseif CanInspect(unit, false) and (not lastAttempt[unit] or nowTime - lastAttempt[unit] > retryInterval) then
			local guid = ns.SafeGuid(unit and UnitGUID(unit))
			local isPriority = (unit == priorityInspectUnit)
			lastAttempt[unit] = nowTime
			RemoveFromQueue(unit)
			if isPriority then mouseoverPending[unit] = true; priorityInspectUnit = nil end
			if guid then
				inspectCompleted[guid] = nil
				inspectUnitByGuid[guid] = unit
				TrackUnit(unit, guid)
			end
			NotifyInspect(unit)
			
			C_Timer.After(isPriority and MOUSEOVER_RETRY_INTERVAL or INSPECT_REQUEUE_DELAY, function()
				local checkGuid = ns.SafeGuid(UnitGUID(unit))
				if not unit or not UnitExists(unit) or UnitIsInspected(unit) or not checkGuid then
					ReleaseUnit(unit)
					RemoveFromQueue(unit)
					return
				end
				local completed = inspectCompleted[checkGuid]
				inspectCompleted[checkGuid] = nil
				if completed then return end
				if inspectQuery[unit] then return end
				
				if postArena and postArena.active and postArena.pendingAllies and postArena.pendingAllies[checkGuid] then
					postArena.allyRetries = postArena.allyRetries or {}
					local retries = (postArena.allyRetries[checkGuid] or 0) + 1
					postArena.allyRetries[checkGuid] = retries
					if retries > POST_ARENA_MAX_RETRIES then ClearPendingAlly(checkGuid); return end
				end
				
				lastAttempt[unit] = nil
				inspectQuery[unit] = GetTime()
				inspectOrder[#inspectOrder + 1] = unit
				TrackUnit(unit, checkGuid)
			end)
			return
		end
	end
end

-- ============================================================================
-- TOOLTIP INSPECT
-- ============================================================================
local function TryInspectTooltipUnit(unit)
	if not unit or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end
	if not UnitExists(unit) or not UnitIsConnected(unit) or UnitIsInspected(unit) or not CanInspect(unit, false) then return end
	local guid = ns.SafeGuid(UnitGUID(unit))
	if not guid or not ns.IsLevel(UnitLevel(unit)) then return end
	
	local name = ns.FormatNameRealm(UnitName(unit))
	if ns.IsBlacklisted(name) or GuidOnCooldown(guid) then return end
	
	local last = lastCheckNext[unit]
	if last and (GetTime() - last) <= INSPECT_RETRY_INTERVAL and cooldownGuid[unit] == guid then return end
	
	local tracked = trackedGuids[guid]
	if tracked then
		if tracked ~= unit or not inspectQuery[unit] then return end
		priorityInspectUnit = unit
		InspectNext()
		return
	end
	
	priorityInspectUnit = unit
	AddInspectToQueue(unit)
	InspectNext()
end

-- ============================================================================
-- START POST ARENA
-- ============================================================================
local function StartPostArena(enemyNames, allyGuids, allyNames)
	if not enemyNames or #enemyNames == 0 then return end
	postArena = {
		enemyNames = enemyNames,
		allyGuids = allyGuids,
		allyNames = allyNames,
		active = false,
		startedAt = GetTime()
	}
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================
local function HandleInspectReady(guid)
	guid = ns.SafeGuid(guid)
	if not guid then return end
	
	local now = GetTime()
	local last = lastInspectReady[guid]
	if last and (now - last) < INSPECT_READY_THROTTLE then return end
	lastInspectReady[guid] = now
	inspectDataOwnerGuid = guid
	
	if guid == UnitGUID("player") then
		inspectCompleted[guid] = true
		if GetInspectArenaData and inspectDataOwnerGuid == UnitGUID("player") then
			local rating, played, won = GetInspectArenaData(5)
			if type(rating) == "number" then ns.SetMySkirmishData(rating, played or 0, won or 0) end
		end
		if postArena and postArena.active and ns.MainUI and ns.MainUI.RecordWeeklyArenaRating then
			if GetInspectArenaData then
				local rating, _, _, wp, ww = GetInspectArenaData(5)
				if type(rating) == "number" then ns.MainUI.RecordWeeklyArenaRating(rating, wp, ww) end
			end
		end
		if postArena and postArena.active and postArena.awaitingSelf then
			postArena.awaitingSelf = false
			postArena.selfDone = true
			if postArena.pendingAllies and next(postArena.pendingAllies) then PostArenaKick() else FinishPostArena() end
		end
		return
	end
	
	local unit = inspectUnitByGuid[guid]
	if not (unit and UnitExists(unit) and ns.SafeGuid(UnitGUID(unit)) == guid) then
		unit = nil
		if guid then
			local candidates = { "target", "focus", "mouseover" }
			for i = 1, 5  do candidates[#candidates + 1] = "party" .. i end
			for i = 1, 40 do candidates[#candidates + 1] = "raid" .. i end
			for i = 1, 40 do candidates[#candidates + 1] = "nameplate" .. i end
			if InspectFrame and InspectFrame.unit then candidates[#candidates + 1] = InspectFrame.unit end
			for _, u in ipairs(candidates) do
				if UnitExists(u) and ns.SafeGuid(UnitGUID(u)) == guid then unit = u; break end
			end
		end
	end
	inspectUnitByGuid[guid] = nil
	
	if not unit or UnitIsUnit(unit, "player") then return end
	
	local level = UnitLevel(unit)
	if not ns.IsLevel(level) or not GetInspectArenaData then return end
	
	local rating, played, won = GetInspectArenaData(5)
	if type(rating) ~= "number" then return end
	
	if (tonumber(rating) or 0) == 0 then
		local hasData = false
		if not hasData and GetInventoryItemID then
			for slot = 1, 17 do
				local id = GetInventoryItemID(unit, slot)
				if type(id) == "number" and id > 0 then
					hasData = true
					break
				end
			end
		end
		if not hasData then
			lastAttempt[unit] = nil
			if not inspectQuery[unit] then
				inspectQuery[unit] = GetTime()
				inspectOrder[#inspectOrder + 1] = unit
				TrackUnit(unit, guid)
			end
			return
		end
	end
	
	local name = ns.FormatNameRealm(UnitName(unit))
	
	local function ConcludeAndMark(cooldown)
		if guid then inspected[guid] = true end
		if unit then
			RemoveFromQueue(unit)
			if priorityInspectUnit == unit then priorityInspectUnit = nil end
			ReleaseUnit(unit)
			if cooldown then
				lastCheckNext[unit] = GetTime()
				lastCheckNextGuid[guid] = GetTime()
				cooldownGuid[unit] = guid
			end
			lastAttempt[unit] = nil
			mouseoverPending[unit] = nil
			ClearPendingAlly(guid)
		end
	end
	
	if ns.IsBlacklisted(name) then
		ConcludeAndMark(true)
		return
	end
	
	ns.SaveSharedData(guid, name, rating, played or 0, won or 0, select(2, UnitClass(unit)), nil, nil)
	inspectCompleted[guid] = true
	ConcludeAndMark(true)
end

local function HandleMouseoverUnit()
	if not UnitExists("mouseover") then
		lastMouseoverGUID = nil
		return
	end
	local guid = ns.SafeGuid(UnitGUID("mouseover"))
	if not guid or guid == lastMouseoverGUID then return end
	lastMouseoverGUID = guid
	TryInspectTooltipUnit("mouseover")
end

local function HandleRosterUpdate()
	if not scheludedQueue then
		scheludedQueue = C_Timer.NewTimer(GROUP_QUEUE_DELAY, function()
			scheludedQueue = nil
			if InCombatLockdown() or UnitAffectingCombat("player") then return end
			if IsInRaid() then
				local n = GetNumGroupMembers() or 0
				for i = 1, math.min(n, 40) do AddInspectToQueue("raid" .. i) end
			elseif IsInGroup() then
				for i = 1, 4 do AddInspectToQueue("party" .. i) end
			end
		end)
	end
	
	if postArena and postArena.active and postArena.pendingAllies and not postArena.awaitingSelf then
		local present = {}
		if (GetTime() - (postArena.startedAt or 0)) >= 10 then
			for _, u in ipairs(FindAlliesInGroup(postArena.allyGuids)) do
				local g = ns.SafeGuid(UnitGUID(u))
				if g then present[g] = true end
			end
			for g in pairs(postArena.pendingAllies) do
				if not present[g] then ClearPendingAlly(g) end
			end
		end
	end
	PostArenaKick()
end

local function HandleEnteringWorld()
    wipe(inspected)
    wipe(inspectOrder)
    wipe(trackedGuids)
    wipe(unitToGuid)
    wipe(inspectCompleted)
    wipe(inspectUnitByGuid)
    wipe(lastAttempt)
    wipe(mouseoverPending)
    wipe(lastCheckNext)
    wipe(lastCheckNextGuid)
    wipe(cooldownGuid)
    inspectQuery = {}
	if postArena and postArena.active then
		postArena = nil
	end
	
	C_Timer.After(5, function()
		if not postArena or postArena.active or not postArena.enemyNames or #postArena.enemyNames == 0 then return end
		postArena.active = true
		postArena.pendingAllies = {}
		for _, u in ipairs(FindAlliesInGroup(postArena.allyGuids)) do
			local g = ns.SafeGuid(UnitGUID(u))
			if g then postArena.pendingAllies[g] = true end
		end
		PostArenaKick()
	end)
end

-- ============================================================================
-- EVENT FRAME REGISTRATION
-- ============================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("INSPECT_READY")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "INSPECT_READY" then
		HandleInspectReady(arg1)
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		HandleMouseoverUnit()
	elseif event == "GROUP_ROSTER_UPDATE" then
		HandleRosterUpdate()
	elseif event == "PLAYER_ENTERING_WORLD" then
		HandleEnteringWorld()
	end
end)

if GameTooltip and GameTooltip.SetUnit then
	hooksecurefunc(GameTooltip, "SetUnit", function(self, unit)
		if unit then TryInspectTooltipUnit(unit) end
	end)
end

if not inspectTicker then
	inspectTicker = C_Timer.NewTicker(INSPECT_TICK_INTERVAL, InspectNext)
end

-- ============================================================================
-- EXPORT
-- ============================================================================
ns.InspectQueue = {
	StartPostArena = StartPostArena,
	CollectPostArenaData = CollectPostArenaData,
}