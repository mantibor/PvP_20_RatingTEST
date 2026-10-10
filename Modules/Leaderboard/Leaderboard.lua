local addonName, ns = ...
local L = ns.L
local LD = ns.LeaderboardData

-- ============================================================================
-- STATE
-- ============================================================================
local ROW_HEIGHT = 20
local LEADERBOARD_WIDTH = 788

local seasonFilter = "CURRENT_SEASON"
local bracketFilter = "RANDOM_BATTLEGROUNDS"
local classFilter
local ratingFilters = {}
local sortKey = "rating"
local sortAsc = false
local searchText
local settingsLoaded
local wasActiveOnHide
local scrollView
local blizzMoveRegistered

-- ============================================================================
-- CONSTANTS 
-- ============================================================================

LD.CLASS_ORDER = {
	"WARRIOR",
	"PALADIN",
	"HUNTER",
	"ROGUE",
	"PRIEST",
	"DEATHKNIGHT",
	"SHAMAN",
	"MAGE",
	"WARLOCK",
	"MONK",
	"DRUID",
	"DEMONHUNTER",
	"EVOKER",
}

LD.COLUMN_INFO = {
	{ title = "#",                             width = 36,  key = "rank"   },
	{ title = NAME,                            width = 186, key = "name"   },
	{ title = RATING,                          width = 65,  key = "rating" },
	{ title = PVP_BEST_RATING:gsub(": ", " "), width = 110, key = "best"   },
	{ title = STATISTICS,                      width = 100, key = "wr"     },
	{ title = L["Last Updated"],               width = 155, key = "time"   },
}

LD.RATING_FILTERS = {
	{ min = 0,    max = 999,  key = "Unranked",   color = "9D9D9D", text = PVP_RANK_0_NAME },
	{ min = 1000, max = 1399, key = "Combatant",  color = "FFFFFF", text = PVP_RANK_1_NAME:gsub("%s+I%s*$", "") },
	{ min = 1400, max = 1799, key = "Challenger", color = "1EFF00", text = PVP_RANK_2_NAME:gsub("%s+I%s*$", "") },
	{ min = 1800, max = 2099, key = "Rival",      color = "0070DD", text = PVP_RANK_3_NAME:gsub("%s+I%s*$", "") },
	{ min = 2100, max = 2299, key = "Duelist",    color = "A335EE", text = PVP_RANK_4_NAME:gsub("%s+I%s*$", "") },
	{ min = 2300, max = nil,  key = "Elite",      color = "FF8000", text = PVP_RANK_5_NAME },
}

LD.BRACKET_ARCHIVE_CONFIG = {
	RANDOM_BATTLEGROUNDS = { matchTypes = { "random_bg" },    useRounds = false },
	SOLO_SHUFFLE         = { matchTypes = { "solo_shuffle" }, useRounds = true  },
	WARGAMES             = { matchTypes = { "wg_arena" },     useRounds = false },
}

LD.ACCENT_MAP = {
	["á"] = "a", ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["ã"] = "a", ["å"] = "a", 	["ā"] = "a",
	["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["ē"] = "e", ["ė"] = "e",	["ę"] = "e",
	["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i", ["ī"] = "i", ["į"] = "i",
	["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["ö"] = "o", ["õ"] = "o", ["ø"] = "o", 	["ō"] = "o",
	["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["ū"] = "u", ["ů"] = "u",
	["ý"] = "y", ["ÿ"] = "y", ["ñ"] = "n", ["ç"] = "c", ["ß"] = "b", ["æ"] = "ae", 	["ð"] = "d",
}

LD.CYRILLIC_TO_LATIN = {
	["А"] = "A", 	["а"] = "a", 	["Б"] = "B", 	["б"] = "b", 	["В"] = "V", 	["в"] = "v",
	["Г"] = "G", 	["г"] = "g", 	["Д"] = "D", 	["д"] = "d", 	["Е"] = "E",	["е"] = "e",
	["Ё"] = "E", 	["ё"] = "e", 	["Ж"] = "Zh", 	["ж"] = "zh", 	["З"] = "Z", 	["з"] = "z",
	["И"] = "I", 	["и"] = "i", 	["Й"] = "I", 	["й"] = "i", 	["К"] = "K", 	["к"] = "k",
	["Л"] = "L", 	["л"] = "l", 	["М"] = "M", 	["м"] = "m", 	["Н"] = "N",	["н"] = "n",
	["О"] = "O", 	["о"] = "o", 	["П"] = "P", 	["п"] = "p", 	["Р"] = "R",	["р"] = "r",
	["С"] = "S", 	["с"] = "s", 	["Т"] = "T", 	["т"] = "t", 	["У"] = "U",	["у"] = "u",
	["Ф"] = "F", 	["ф"] = "f", 	["Х"] = "Kh", 	["х"] = "kh", 	["Ц"] = "Ts", 	["ц"] = "ts",
	["Ч"] = "Ch", 	["ч"] = "ch", 	["Ш"] = "Sh", 	["ш"] = "sh",	["Щ"] = "Shch", ["щ"] = "shch",
	["Ъ"] = "Ie", 	["ъ"] = "ie", 	["Ы"] = "Y", 	["ы"] = "y", 	["Ь"] = "", 	["ь"] = "",
	["Э"] = "E", 	["э"] = "e", 	["Ю"] = "Iu", 	["ю"] = "iu", 	["Я"] = "Ia", 	["я"] = "ia",
}

LD.REALM_TRANSLATIONS = {
	["Азурегос"] = 		"Azuregos", 		["Борейскаятундра"] = 	"BoreanTundra",
	["ВечнаяПесня"] = 	"Eversong", 		["Галакронд"] = 		"Galakrond",
	["Голдринн"] = 		"Goldrinn", 		["Гордунни"] = 			"Gordunni",
	["Гром"] = 			"Grom", 			["Дракономор"] = 		"Fordragon",
	["Корольлич"] = 	"LichKing", 		["ПиратскаяБухта"] = 	"BootyBay",
	["Подземье"] = 		"Deepholm", 		["Разувий"] = 			"Razuvious",
	["Ревущийфьорд"] = 	"HowlingFjord", 	["СвежевательДуш"] = 	"Soulflayer",
	["Седогрив"] = 		"Greymane", 		["СтражСмерти"] = 		"Deathguard",
	["Термоштепсель"] = "Thermaplugg", 		["ТкачСмерти"] = 		"Deathweaver",
	["ЧерныйШрам"] = 	"Blackscar", 		["Ясеневыйлес"] = 		"Ashenvale",
}

-- ============================================================================
-- LOCAL UTILITIES (Используются ТОЛЬКО внутри Leaderboard.lua)
-- ============================================================================
-- Примечание: Таблицы маппинга (ns.ACCENT_MAP, ns.CYRILLIC_TO_LATIN, ns.REALM_TRANSLATIONS) 
-- остаются в Config/Strings.lua как ns.*, так как это статичные конфиги.

function LD.NormalizeString(text)
	if not text then return "" end
	text = text:lower()
	for accented, plain in pairs(LD.ACCENT_MAP) do
		text = text:gsub(accented, plain)
	end
	return text
end

function LD.TransliterateName(name)
	if not name then return name end
	return name:gsub("[\208\209][\128-\191]", LD.CYRILLIC_TO_LATIN)
end

function LD.LocalizeRealm(realm)
	if not realm or realm == "" then return realm end
	local exact = LD.REALM_TRANSLATIONS[realm]
	if exact then return exact end
	local clean = realm:gsub("[%s%-]", ""):lower()
	for cyr, eng in pairs(LD.REALM_TRANSLATIONS) do
		if cyr:gsub("[%s%-]", ""):lower() == clean then return eng end
	end
	return LD.TransliterateName(realm)
end

function LD.DisplayName(fullName)
	if not fullName then return fullName end
	if GetLocale() == "ruRU" then return fullName end
	local name, realm = fullName:match("^(.-)%-(.+)$")
	if name and realm then
		return ns.FormatNameRealm(LD.TransliterateName(name), LD.LocalizeRealm(realm))
			or LD.TransliterateName(fullName)
	end
	return LD.TransliterateName(fullName)
end

-- ============================================================================
-- BLIZZMOVE & SETTINGS
-- ============================================================================
local function RegisterWithBlizzMove()
	if blizzMoveRegistered then return true end
	local API = _G.BlizzMoveAPI
	if not API or not LeaderboardFrame or not PVEFrame then return false end
	API:RegisterAddOnFrames({
		[addonName] = { ["PVEFrame"] = { SubFrames = { ["LeaderboardFrame"] = {} } } }
	})
	blizzMoveRegistered = true
	return true
end

local function SaveSettings()
	if not PvP20RLeaderboardSettings then PvP20RLeaderboardSettings = {} end
	PvP20RLeaderboardSettings.ratingFilters = {}
	for filter, enabled in pairs(ratingFilters) do
		if enabled then PvP20RLeaderboardSettings.ratingFilters[filter.key] = true end
	end
end

local function LoadSettings()
	local settings = PvP20RLeaderboardSettings
	local restored = 0
	if settings and settings.ratingFilters then
		for _, filter in ipairs(LD.RATING_FILTERS) do
			if settings.ratingFilters[filter.key] then
				ratingFilters[filter] = true
				restored = restored + 1
			end
		end
	end
	if restored == 0 then
		for _, filter in ipairs(LD.RATING_FILTERS) do
			ratingFilters[filter] = true
		end
		SaveSettings()
	end
end

-- ============================================================================
-- COPY DIALOG & ARMORY
-- ============================================================================
local function BuildArmoryURL(fullName)
	if not fullName or fullName == "" then return nil end
	local name, realm = fullName:match("^(.-)%-(.+)$")
	if not name then
		name = fullName
		realm = GetNormalizedRealmName()
	end
	local englishRealm = LD.LocalizeRealm(realm)
	local realmSlug = ""
	if englishRealm and englishRealm ~= "" then
		realmSlug = englishRealm:gsub("(%l)(%u)", "%1-%2"):gsub("[%s_]+", "-"):lower()
	end
	if realmSlug == "" then return nil end
	
	local key = ns.GetRegionKey()
	local regionSlug = key and key:lower()
	
	local loc = GetLocale()
	local armoryLocale
	if loc == "enUS" or loc == "enGB" then
		armoryLocale = GetCurrentRegion() == 3 and "en-gb" or "en-us"
	else
		local lang, country = loc:sub(1, 2):lower(), loc:sub(3, 4):lower()
		armoryLocale = country ~= "" and (lang .. "-" .. country) or lang
	end
	return ("https://worldofwarcraft.blizzard.com/%s/worldsoul/%s/armory/character/%s/%s"):format(armoryLocale, regionSlug, realmSlug, name)
end

local function ShowCopyDialog(text, titleColored)
	if not text or text == "" then return end
	StaticPopup_Show("PVP20R_ARMORY_LINK", titleColored, nil, text)
end

StaticPopupDialogs["PVP20R_ARMORY_LINK"] = {
	text = "%s",
	button1 = OKAY,
	hasEditBox = true,
	editBoxWidth = 350,
	OnShow = function(self, data)
		local eb = self.editBox or (self.GetEditBox and self:GetEditBox())
		if not eb then return end 
		local dialog = eb:GetParent()
		dialog:SetScript("OnMouseDown", function(_, btn)
			if btn == "RightButton" then
				dialog:Hide()
			end
		end)
		dialog:EnableKeyboard(true)
		dialog:SetPropagateKeyboardInput(true)
		dialog:SetScript("OnKeyDown", function(_, key)
			if IsControlKeyDown() or IsMetaKeyDown() then
				eb:SetFocus()
				eb:HighlightText()
			end
		end)
		eb.URL = data or ""
		eb.restoring = nil
		eb:SetMaxLetters(0)
		eb:SetText(eb.URL)
		eb:SetAutoFocus(false)
		eb:ClearFocus()
		eb:SetScript("OnKeyDown", function(self, key)
			if key == "C" and (IsControlKeyDown() or IsMetaKeyDown()) then
				self:HighlightText()
				C_Timer.After(0.1, function()
					if dialog and dialog.Hide then
						dialog:Hide()
					end
					ActionStatus:DisplayMessage(L["Copied to clipboard."], true)
				end)
			end
		end)
		eb:SetScript("OnTextChanged", function(self, userInput)
			if self.restoring or not self.URL then return end
			if userInput and self:GetText() ~= self.URL then
				self.restoring = true
				self:SetText(self.URL)
				self.restoring = nil
			end
		end)
		eb:SetScript("OnEscapePressed", function()
			if dialog and dialog.Hide then
				dialog:Hide()
			end
		end)
		eb:SetScript("OnEnterPressed", function()
			if dialog and dialog.Hide then
				dialog:Hide()
			end
		end)
		eb:SetScript("OnMouseDown", function(self)
			self:ClearFocus()
		end)
		eb:SetScript("OnMouseUp", function(self)
			self:HighlightText()
		end)
	end,
	OnHide = function(self)
		local eb = self.editBox or (self.GetEditBox and self:GetEditBox())
		if eb then
			for _, event in ipairs({"OnKeyDown", "OnTextChanged", "OnEscapePressed", "OnEnterPressed", "OnMouseDown", "OnMouseUp"}) do eb:SetScript(event, nil) end
			eb.URL, eb.restoring = nil, nil
			local dialog = eb:GetParent()
			if dialog then
				dialog:SetScript("OnMouseDown", nil)
				dialog:SetScript("OnKeyDown", nil)
				dialog:EnableKeyboard(false)
			end
		end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- ============================================================================
-- TABLE ROW DISPLAY
-- ============================================================================
local function ClassLabel(cls)
	if not cls then return ALL_CLASSES end
	local locName = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls] or cls
	return ns.GetClassColorText(cls, locName)
end

local function InitializeRow(row, elementData)
	if not row or not elementData then return end
	local e = elementData
	local widths = {}
	for _, col in ipairs(ns.COLUMN_INFO) do widths[col.key] = col.width end
	
	if row.Rank then row.Rank:SetWidth(math.max(widths.rank - 6, 1)) end
	if row.Name then row.Name:SetWidth(math.max(widths.name - 30, 1)) end
	if row.Rating then row.Rating:SetWidth(widths.rating) end
	if row.Best then row.Best:SetWidth(widths.best) end
	if row.Stats then row.Stats:SetWidth(widths.wr) end
	if row.Updated then row.Updated:SetWidth(widths.time) end
	
	row.Rank:SetText(e.rank or 0)
	local coords = e.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[e.class]
	if coords then
		row.ClassIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
		row.ClassIcon:SetTexCoord(unpack(coords))
		row.ClassIcon:Show()
	else
		row.ClassIcon:Hide()
	end
	
	local displayName = LD.DisplayName(e.name)
	if e.class then displayName = ns.GetClassColorText(e.class, displayName) end
	if e.isSelf then displayName = displayName .. " |cFF00FF00(" .. YOU .. ")|r" end
	row.Name:SetText(displayName)
	row.originalName = e.name
	row.class = e.class
	row.hasCyrillic = e.name and e.name:find("[\208\209][\128-\191]") ~= nil
	
	local rating = LD.safeNum(e.rating)
	local best = LD.safeNum(e.best)
	local played = LD.safeNum(e.played)
	local won = LD.safeNum(e.won)
	
	row.Rating:SetText(("|cFF%s%d|r"):format(LD.RatingColor(rating), rating))
	row.Best:SetText(("|cFF%s%d|r"):format(LD.RatingColor(best), best))
	
	local lost = math.max(played - won, 0)
	local wr = played > 0 and math.floor(100 * won / played) or 0
	row.Stats:SetText(("%d-%d (%d%%)"):format(won, lost, wr))
	
	local ts = LD.safeNum(e.lastUpdate)
	row.Updated:SetText((type(ts) == "number" and ts > 1000000000) and date("%d.%m.%y %H:%M", ts) or "-")
	local ageOk = ts > 1000000000
	if ageOk and ts >= ns.GetWeekStart() then
		row.Updated:SetTextColor(1, 1, 1)
	else
		row.Updated:SetTextColor(0.5, 0.5, 0.5)
	end
	
	local dataIndex = row:GetElementDataIndex()
	if dataIndex and dataIndex % 2 == 0 then row:GetNormalTexture():SetVertexColor(0.95, 0.95, 0.95, 1)
	else row:GetNormalTexture():SetVertexColor(1, 1, 1, 1) end
	
	row:SetScript("OnEnter", function(self)
		if GetLocale() ~= "ruRU" and self.hasCyrillic and self.originalName then
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 2)
			GameTooltip:AddLine(ns.GetClassColorText(self.class, self.originalName))
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			local fullName = self.originalName
			if fullName and MenuUtil and MenuUtil.CreateContextMenu then
				local shownName = LD.DisplayName(fullName)
				local titleColored = ns.GetClassColorText(self.class, shownName)
				MenuUtil.CreateContextMenu(self, function(owner, root)
					root:CreateTitle(titleColored)
					root:CreateButton(COPY_CHARACTER_NAME, function()
						ShowCopyDialog(fullName, titleColored)
					end)
					local url = BuildArmoryURL(fullName)
					root:CreateButton(L["Copy Armory Link"], function()
						ShowCopyDialog(url, titleColored)
					end)
				end)
			end
		end
	end)
end

-- ============================================================================
-- LEADERBOARD TABLE MANAGEMENT
-- ============================================================================
local function RefreshList()
	local frame = LeaderboardFrame
	if not frame or not scrollView then return end
	
	local entries = LD.CollectEntries(bracketFilter, classFilter, ratingFilters, searchText, sortKey, sortAsc)
	local rankByGuid = {}
	local archiveCfg = LD.BRACKET_ARCHIVE_CONFIG[bracketFilter]
	
	if archiveCfg then
		local allAggregates = LD.BuildArchiveAggregates(archiveCfg.matchTypes, archiveCfg.useRounds)
		LD.InjectArchiveRatings(allAggregates, bracketFilter)          -- ← добавить
		local all = {}
		for _, agg in pairs(allAggregates) do
			if (tonumber(agg.rating) or 0) > 0 then                    -- ← фильтр как в GetLeaderboardRank
				all[#all + 1] = agg
			end
		end
		table.sort(all, LD.IsBetter)
		for i, e in ipairs(all) do rankByGuid[e.guid] = i end
	else
		local all = {}
		local db = ns.SkirmishDB
		if type(db) == "table" then
			for guid, data in pairs(db) do
				if type(guid) == "string" and type(data) == "table" and (tonumber(data.rating) or 0) > 0 then
					all[#all + 1] = {
						guid = guid,
						name = data.name,
						rating = tonumber(data.rating) or 0,
						bestRating = tonumber(data.bestRating or data.rating) or 0,
						played = tonumber(data.played) or 0,
						won = tonumber(data.won) or 0,
						lastUpdate = tonumber(data.lastUpdate) or 0,
					}
				end
			end
		end
		table.sort(all, LD.IsBetter)
		for i, e in ipairs(all) do rankByGuid[e.guid] = i end
	end
	
	for _, e in ipairs(entries) do e.rank = rankByGuid[e.guid] or 0 end
	
	local provider = CreateDataProvider(entries)
	frame.ScrollBox:SetDataProvider(provider, ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
end

function _G.Leaderboard_OnSearchTextChanged(editBox)
	local text = editBox:GetText()
	searchText = (text and text ~= "") and text:lower() or nil
	RefreshList()
end

local function HideLeaderboard()
	if LeaderboardFrame then LeaderboardFrame:Hide() end
end

local function UpdateLeaderboardTabVisibility()
	local tab = ns._leaderboardTab
	if not tab then return end
	local lvl = UnitLevel("player")
	if lvl == 20 or lvl == 21 then
		tab:Show()
	else
		if PVEFrame and PVEFrame.activeTabIndex == tab:GetID() then HideLeaderboard() end
		tab:Hide()
	end
end

local function ShowLeaderboard()
	if not scrollView then
		local frame = LeaderboardFrame
		if frame then
			if not settingsLoaded then LoadSettings(); settingsLoaded = true end
			scrollView = CreateScrollBoxListLinearView()
			scrollView:SetElementInitializer("PvP20RLeaderboardRowTemplate", InitializeRow)
			scrollView:SetElementExtent(ROW_HEIGHT)
			ScrollUtil.InitScrollBoxListWithScrollBar(frame.ScrollBox, frame.ScrollBar, scrollView)
			
			local cd = frame.ColumnDisplay
			if cd and not cd.__Init then
				cd.__Init = true
				cd.sortingFunction = function(_, columnIndex)
					local col = LD.COLUMN_INFO[columnIndex]
					if col and col.key then
						local key = col.key
						if key == "rank" then key = "rating" end
						if sortKey == key then sortAsc = not sortAsc
						else sortKey = key; sortAsc = (key == "name") end
						RefreshList()
					end
				end
				if cd.LayoutColumns then
					cd:LayoutColumns(LD.COLUMN_INFO)
				end
				RefreshList()
			end
			
			if frame.SeasonDropdown then
				local seasonText = PLAYER_V_PLAYER_SEASON:match("%((.*)%)"):format(PVPUtil.GetCurrentSeasonNumber())
				frame.SeasonDropdown:SetupMenu(function(dropdown, root)
					for _, s in ipairs({{key="CURRENT_SEASON", text=seasonText, enabled=true}}) do
						local radio = root:CreateRadio(s.text,
							function() return seasonFilter == s.key end,
							function()
								if not s.enabled then return MenuResponse and MenuResponse.Open end
								seasonFilter = s.key; frame.SeasonDropdown:SetText(s.text); RefreshList()
								return MenuResponse and MenuResponse.CloseAll
							end)
						if not s.enabled and radio and radio.SetEnabled then radio:SetEnabled(false) end
					end
				end)
				frame.SeasonDropdown:SetText(seasonText)
			end
			
			if frame.BracketDropdown then
				local brackets = {
					{ key = "RANDOM_BATTLEGROUNDS", text = RANDOM_BATTLEGROUNDS, enabled = true },
					{ key = "SKIRMISH",             text = SKIRMISH, enabled = true },
					{ key = "SOLO_SHUFFLE",         text = PVP_RATED_SOLO_SHUFFLE, enabled = true },
					{ key = "WARGAMES",             text = ARENA_BATTLES_5V5, enabled = true },
				}
				frame.BracketDropdown:SetupMenu(function(dropdown, root)
					for _, b in ipairs(brackets) do
						local radio = root:CreateRadio(b.text,
							function() return bracketFilter == b.key end,
							function()
								if not b.enabled then return MenuResponse and MenuResponse.Open end
								bracketFilter = b.key; frame.BracketDropdown:SetText(b.text)
								RefreshList()
								return MenuResponse and MenuResponse.CloseAll
							end)
						if not b.enabled and radio and radio.SetEnabled then
							radio:SetEnabled(false)
						end
					end
				end)
				frame.BracketDropdown:SetText(SKIRMISH)
			end
			
			if frame.ClassDropdown then
				frame.ClassDropdown:SetupMenu(function(dropdown, root)
					root:CreateRadio(ALL_CLASSES,
						function()
							return classFilter == nil
						end,
						function()
							classFilter = nil
							frame.ClassDropdown:SetText(ClassLabel(nil))
							RefreshList()
							return MenuResponse and MenuResponse.CloseAll
						end)
					for _, cls in ipairs(LD.CLASS_ORDER) do
						root:CreateRadio(ClassLabel(cls),
							function()
								return classFilter == cls
							end,
							function()
								classFilter = cls
								frame.ClassDropdown:SetText(ClassLabel(cls))
								RefreshList()
								return MenuResponse and MenuResponse.CloseAll
							end)
					end
				end)
				frame.ClassDropdown:SetText(ClassLabel(classFilter))
			end
			
			if frame.RatingFilterDropdown then
				frame.RatingFilterDropdown:SetupMenu(function(dropdown, root)
					for _, filter in ipairs(LD.RATING_FILTERS) do
						local label = filter.color and ("|cFF%s%s|r"):format(filter.color, filter.text or filter.key) or (filter.text or filter.key)
						root:CreateCheckbox(label,
							function()
								return ratingFilters[filter] == true
							end,
							function()
								ratingFilters[filter] = not ratingFilters[filter] or nil
								SaveSettings()
								RefreshList()
								return MenuResponse and MenuResponse.Refresh
							end)
					end
				end)
				frame.RatingFilterDropdown:SetText(FILTERS)
				local RATING_DROPDOWN_WIDTH = 100
				frame.RatingFilterDropdown:SetWidth(RATING_DROPDOWN_WIDTH)
				hooksecurefunc(frame.RatingFilterDropdown, "SetWidth", function(self, w)
					if w ~= RATING_DROPDOWN_WIDTH then
						self:SetWidth(RATING_DROPDOWN_WIDTH)
					end
				end)
			end
			
			frame:HookScript("OnShow", RefreshList)
			RegisterWithBlizzMove()
		end
	end
	
	for _, f in ipairs({GroupFinderFrame, PVPUIFrame, ChallengesFrame}) do if f then f:Hide() end end
	if PVEFrame_HideLeftInset then PVEFrame_HideLeftInset() end
	
	local asset = UnitFactionGroup("player") == "Horde" and "Interface\\Icons\\INV_BannerPVP_01" or "Interface\\Icons\\INV_BannerPVP_02"
	PVEFrame:SetPortraitToAsset(asset)
	PVEFrame:SetTitleFormatted(PLAYER_V_PLAYER_SEASON, PVPUtil.GetCurrentSeasonNumber())
	PVEFrame:SetWidth(LEADERBOARD_WIDTH)
	
	if LeaderboardFrame then
		LeaderboardFrame:SetWidth(LEADERBOARD_WIDTH)
		LeaderboardFrame:Show()
		RefreshList()
	end
	UpdateUIPanelPositions(PVEFrame)
end

-- ============================================================================
-- TOOLTIP INTEGRATION
-- ============================================================================
local function AddUnitRatingLine(tooltip, guid)
	if not guid or (issecretvalue and issecretvalue(guid)) or type(guid) ~= "string" then return end
	local hasLine = false
	local stats = ns.GetArchiveStatsForGuid and ns.GetArchiveStatsForGuid(guid)
	
	if stats and stats.randomBG then
		local rbPlayed = LD.safeNum(stats.randomBG.played)
		local rbWon = LD.safeNum(stats.randomBG.wins)
		if rbPlayed > 0 then
			local rbLost = math.max(rbPlayed - rbWon, 0)
			local rbWR = math.floor(100 * rbWon / rbPlayed)
			local rbRating = stats.randomBG.rating
			local rbRatingText = ("|cFF%s%d|r"):format(LD.RatingColor(rbRating), rbRating)
			tooltip:AddDoubleLine("PvP 20 Rating:", ("%s: %s %d-%d (%d%%)"):format(RANDOM_BATTLEGROUNDS, rbRatingText, rbWon, rbLost, rbWR), 1, 0.82, 0, 1, 1, 1)
			hasLine = true
		end
	end
	
	if ns.SkirmishDB then
		local rec = ns.SkirmishDB[guid]
		if type(rec) == "table" and rec.rating and LD.safeNum(rec.played) > 0 then
			local played = LD.safeNum(rec.played)
			local won = LD.safeNum(rec.won)
			local lost = math.max(played - won, 0)
			local winrate = played > 0 and math.floor(100 * won / played) or 0
			local ratingText = ("|cFF%s%d|r"):format(LD.RatingColor(rec.rating), LD.safeNum(rec.rating))
			tooltip:AddDoubleLine(hasLine and " " or "PvP 20 Rating:", ("%s: %s %d-%d (%d%%)"):format(SKIRMISH, ratingText, won, lost, winrate), 1, 0.82, 0, 1, 1, 1)
			hasLine = true
		end
	end
	
	if stats and stats.soloShuffle then
		local ssPlayed = LD.safeNum(stats.soloShuffle.played)
		local ssWon = LD.safeNum(stats.soloShuffle.wins)
		if ssPlayed > 0 then
			local ssLost = math.max(ssPlayed - ssWon, 0)
			local ssWR = math.floor(100 * ssWon / ssPlayed)
			local ssRating = stats.soloShuffle.rating
			local ssRatingText = ("|cFF%s%d|r"):format(LD.RatingColor(ssRating), ssRating)
			tooltip:AddDoubleLine(hasLine and " " or "PvP 20 Rating:", ("%s: %s %d-%d (%d%%)"):format(PVP_RATED_SOLO_SHUFFLE, ssRatingText, ssWon, ssLost, ssWR), 1, 0.82, 0, 1, 1, 1)
			hasLine = true
		end
	end
	
	if stats and stats.wargame then
		local wgPlayed = LD.safeNum(stats.wargame.played)
		local wgWon = LD.safeNum(stats.wargame.wins)
		if wgPlayed > 0 then
			local wgLost = math.max(wgPlayed - wgWon, 0)
			local wgWR = math.floor(100 * wgWon / wgPlayed)
			local wgRating = stats.wargame.rating
			local wgRatingText = ("|cFF%s%d|r"):format(LD.RatingColor(wgRating), wgRating)
			tooltip:AddDoubleLine(hasLine and " " or "PvP 20 Rating:", ("%s: %s %d-%d (%d%%)"):format(WARGAMES, wgRatingText, wgWon, wgLost, wgWR), 1, 0.82, 0, 1, 1, 1)
			hasLine = true
		end
	end
	
	if hasLine then tooltip:Show() end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
		if tooltip == GameTooltip and data and data.guid then AddUnitRatingLine(tooltip, data.guid) end
	end)
else
	GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip)
		local _, unit = tooltip:GetUnit()
		if unit and UnitExists(unit) then AddUnitRatingLine(tooltip, UnitGUID(unit)) end
	end)
end

-- ============================================================================
-- TAB MANAGEMENT
-- ============================================================================
local function GetTabAnchor()
	local challengesTab = ChallengesFrame and PVEFrameTab3
	if challengesTab and challengesTab:IsShown() then return PVEFrameTab3, "RIGHT", 3, 0 end
	return PVEFrameTab2, "RIGHT", 3, 0
end

local function AddLeaderboardTab()
	if not PVEFrame or ns._tabAdded then return end
	ns._tabAdded = true
	local myTabID = (PVEFrame.numTabs or 3) + 1
	local tab = CreateFrame("Button", "PVEFrameTab" .. myTabID, PVEFrame, "PanelTabButtonTemplate")
	tab:SetID(myTabID)
	tab:SetText(L["Leaderboard"])
	PanelTemplates_TabResize(tab, 0)
	
	local anchorFrame, anchorPoint, offsetX, offsetY = GetTabAnchor()
	tab:SetPoint("LEFT", anchorFrame, anchorPoint, offsetX, offsetY)
	tab:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
		wasActiveOnHide = true
		PanelTemplates_SetTab(PVEFrame, myTabID)
		ShowLeaderboard()
	end)
	
	hooksecurefunc("PanelTemplates_SetTab", function(frame, tabID)
		if frame == PVEFrame and tabID ~= myTabID then
			wasActiveOnHide = false
			HideLeaderboard()
			if PVEFrame_ShowLeftInset then PVEFrame_ShowLeftInset() end
		end
	end)
	
	PVEFrame.numTabs = myTabID
	ns._leaderboardTab = tab
	UpdateLeaderboardTabVisibility()
	
	local function repositionTab()
		local newAnchor, newPoint, newX, newY = GetTabAnchor()
		tab:ClearAllPoints()
		tab:SetPoint("LEFT", newAnchor, newPoint, newX, newY)
	end
	if PVEFrameTab2 then PVEFrameTab2:HookScript("OnShow", repositionTab) end
	if PVEFrameTab3 then
		PVEFrameTab3:HookScript("OnShow", repositionTab)
		PVEFrameTab3:HookScript("OnHide", repositionTab)
	end
end

-- ============================================================================
-- EVENT FRAME
-- ============================================================================
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == addonName then
			LoadSettings()
			settingsLoaded = true
		elseif arg1 == "BlizzMove" then
			if scrollView and LeaderboardFrame then RegisterWithBlizzMove() end
		end
	elseif event == "PLAYER_LOGIN" then
		if not ns._tabAdded and PVEFrame then AddLeaderboardTab() end
	elseif event == "PLAYER_ENTERING_WORLD" then
		UpdateLeaderboardTabVisibility()
	end
end)

-- ============================================================================
-- EXPORTS
-- ============================================================================
ns.Leaderboard_Update = RefreshList