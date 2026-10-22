local addonName, ns = ...
local L = ns.L

ns.MAPS = {
	-- Battlegrounds
	{ id = nil,  name = L["Random Battleground"],    pvpType = 3, isRandom = true },
	{ id = 1014, name = L["Warsong Gulch"],          pvpType = 3, minPlayers = 5,  maxPlayers = 10 },
	{ id = 120,  name = L["The Battle for Gilneas"], pvpType = 3, minPlayers = 5,  maxPlayers = 10 },
	{ id = 1018, name = L["Arathi Basin"],           pvpType = 3, minPlayers = 8,  maxPlayers = 15 },
	{ id = 7,    name = L["Eye of the Storm"],       pvpType = 3, minPlayers = 8,  maxPlayers = 15 },
	{ id = 1,    name = L["Alterac Valley"],         pvpType = 3, minPlayers = 10, maxPlayers = 40 },
	{ id = 30,   name = L["Isle of Conquest"],       pvpType = 3, minPlayers = 10, maxPlayers = 40 },
	{ id = 1017, name = L["Battle for Wintergrasp"], pvpType = 3, minPlayers = 10, maxPlayers = 40 },
	{ id = 1020, name = L["Ashran"],                 pvpType = 3, minPlayers = 10, maxPlayers = 40 },
	-- Arenas
	{ id = nil,  name = L["Random Arena"],           pvpType = 4, isRandom = true },
	{ id = 809,  name = L["Nagrand Arena"],          pvpType = 4 },
	{ id = 844,  name = L["Blade's Edge Arena"],	 pvpType = 4 },
	{ id = 8,    name = L["Ruins of Lordaeron"],     pvpType = 4 },
	{ id = 10,   name = L["Dalaran Sewers"],     	 pvpType = 4 },
	{ id = 719,  name = L["Tol'Viron Arena"],        pvpType = 4 }, 
	{ id = 757,  name = L["The Tiger's Peak"],   	 pvpType = 4 },
	{ id = 808,  name = L["Black Rook Hold Arena"],  pvpType = 4 }, 
	{ id = 816,  name = L["Ashamane's Fall"],        pvpType = 4 },
	{ id = 897,  name = L["Hook Point"],             pvpType = 4 },
	{ id = 903,  name = L["Mugambala"],          	 pvpType = 4 },
	{ id = 1025, name = L["The Robodrome"],          pvpType = 4 },
	{ id = 1066, name = L["Maldraxxus Coliseum"],	 pvpType = 4 },
}

ns.RANDOM_BG_POOLS = {
	{ ids = { [1014] = true, [120] = true },                           		maxPlayers = 10 },
	{ ids = { [1018] = true, [7] = true },                              	maxPlayers = 15 },
	{ ids = { [1] = true, 	 [30] = true, [1017] = true, [1020] = true },  	maxPlayers = 40 },
}

ns.BRACKETS = {
	{ name = BATTLEGROUNDS,          size = 0 },
	{ name = PVP_RATED_SOLO_SHUFFLE, size = 3 },
	{ name = ARENA_2V2,              size = 2 },
	{ name = ARENA_3V3,              size = 3 },
	{ name = ARENA_5V5,              size = 5 },
}
