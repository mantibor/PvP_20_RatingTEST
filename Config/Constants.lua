local addonName, ns = ...

-- Network & Protocol
ns.PREFIX = "PVP20R" -- Префикс для аддон-сообщений оставляем как был
ns.PROTOCOL_VERSION = "3" -- 3: короткий вид и время разницей (15.10); со старыми клиентами пакеты кэша не смешиваются
-- Метка сборки очереди, видна в /dev у каждого игрока. Менять при каждой раздаче.
ns.QUEUE_BUILD = "15.10-01"

-- Time & Epochs
ns.EPOCH_MIN = 1782864000
ns.MAX_CACHE_AGE = 30 * 24 * 60 * 60

-- Классы: в базе и пересылках — номер (ClassID игры, warcraft.wiki.gg/wiki/ClassID),
-- а не строка.
ns.CLASS_IDS = {
	WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7,
	MAGE = 8, WARLOCK = 9, MONK = 10, DRUID = 11, DEMONHUNTER = 12, EVOKER = 13,
}
ns.CLASS_BY_ID = {}
for token, id in pairs(ns.CLASS_IDS) do ns.CLASS_BY_ID[id] = token end

-- Regions & Seasons
ns.REGION_KEYS = {
	[1] = "NA",
	[2] = "KR",
	[3] = "EU",
	[4] = "TW",
	[5] = "CN",
}
ns.SEASON_START_UTC = {
	[1] = 1787065200,
	[2] = 1787209200,
	[3] = 1787119200,
	[4] = 1787209200,
	[5] = 1787209200,
}
