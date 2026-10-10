local addonName, ns = ...

-- Network & Protocol
ns.PREFIX = "PVP20R" -- Префикс для аддон-сообщений оставляем как был
ns.PROTOCOL_VERSION = "2"

-- Time & Epochs
ns.EPOCH_MIN = 1782864000
ns.MAX_CACHE_AGE = 30 * 24 * 60 * 60

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
