local addonName, ns = ...

function ns.SafeGuid(guid)
	if type(guid) ~= "string" then return nil end
	if issecretvalue and issecretvalue(guid) then return nil end
	return guid
end

--- Форматирует имя в формат "Name-Realm".
--- Если имя уже содержит дефис — возвращает как есть.
--- Если realm не передан — использует текущий нормализованный реалм.
function ns.FormatNameRealm(name, realm)
	if not name or name == "" then return nil end
	if name:find("-", 1, true) then return name end
	realm = (realm and realm ~= "") and realm:gsub("%s+", "") or GetNormalizedRealmName()
	if realm and realm ~= "" then return name .. "-" .. realm end
	return name
end

--- Проверяет, является ли уровень допустимым для PvP 20 (20 или 21).
function ns.IsLevel(level)
	return level == 20 or level == 21
end

-- ============================================================================
-- BattleNet Friend Lookup
-- ============================================================================

--- Ищет BNet-друга по BattleTag. Возвращает accountInfo или nil.
function ns.FindBNetFriendByBattleTag(battleTag)
	if not battleTag then return nil end
	for i = 1, BNGetNumFriends() do
		local info = C_BattleNet.GetFriendAccountInfo(i)
		if info and info.battleTag == battleTag then return info end
	end
	return nil
end

--- Ищет BNet-друга по "Name-Realm" среди онлайн-аккаунтов WoW.
--- Сначала проверяет основной gameAccount, затем все дополнительные.
--- Возвращает accountInfo или nil.
function ns.FindBNetFriendByNameRealm(nameRealm)
	if not nameRealm or nameRealm == "" then return nil end
	local wantName, wantRealm = nameRealm:match("^(.+)%-(.+)$")
	if not wantName then wantName = nameRealm end
	wantName = wantName:lower()
	wantRealm = wantRealm and wantRealm:lower():gsub("%s+", "")

	for i = 1, BNGetNumFriends() do
		local acc = C_BattleNet.GetFriendAccountInfo(i)
		if acc then
			-- Основной gameAccount
			if acc.gameAccountInfo and acc.gameAccountInfo.isOnline then
				local cName = acc.gameAccountInfo.characterName
				local realm = (acc.gameAccountInfo.realmName or ""):lower():gsub("%s+", "")
				if cName and cName:lower() == wantName
					and (not wantRealm or realm == wantRealm) then
					return acc
				end
			end
			-- Дополнительные gameAccounts
			if C_BattleNet.GetFriendNumGameAccounts then
				for j = 1, (C_BattleNet.GetFriendNumGameAccounts(i) or 0) do
					local game = C_BattleNet.GetFriendGameAccountInfo(i, j)
					if game and game.isOnline and game.clientProgram == BNET_CLIENT_WOW then
						local cName = game.characterName
						local realm = (game.realmName or ""):lower():gsub("%s+", "")
						if cName and cName:lower() == wantName
							and (not wantRealm or realm == wantRealm) then
							return acc
						end
					end
				end
			end
		end
	end
	return nil
end

-- ============================================================================
-- Class Color Utilities
-- ============================================================================

--- Возвращает английский ключ класса (например, "WARRIOR") из локализованного имени.
function ns.GetClassKey(className)
	if not className then return nil end
	if LOCALIZED_CLASS_NAMES_MALE then
		for k, v in pairs(LOCALIZED_CLASS_NAMES_MALE) do
			if className == v then return k end
		end
	end
	if LOCALIZED_CLASS_NAMES_FEMALE then
		for k, v in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
			if className == v then return k end
		end
	end
	return className
end

--- Оборачивает текст в цветовой код класса. Всегда закрывает "|r".
function ns.GetClassColorText(className, text)
	if not className then return FRIENDS_WOW_NAME_COLOR_CODE .. text .. "|r" end
	local classKey = ns.GetClassKey(className) or className
	local colorCode = FRIENDS_WOW_NAME_COLOR_CODE
	if RAID_CLASS_COLORS[classKey] and RAID_CLASS_COLORS[classKey].colorStr then
		colorCode = "|c" .. RAID_CLASS_COLORS[classKey].colorStr
	end
	return colorCode .. text .. "|r"
end