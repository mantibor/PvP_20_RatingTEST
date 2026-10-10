-- SpecPlan(роль от хоста) из WargameFlow.lua и AssignTeamRoles из StateMachine.lua на заглушках WoW.
-- Запуск: luajit tests/specplan_check.lua (из папки аддона) или с путём к ней первым аргументом.
local A = arg[1] or (arg[0]:match("^(.*)[/\\]tests[/\\][^/\\]+$") or ".")
local frame = setmetatable({}, { __index = function() return function() end end })
CreateFrame = function() return frame end
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end, NewTicker = function() return { Cancel = function() end } end }
GetTime = function() return 0 end
hooksecurefunc = function() end

local CLASSES = {
  [8] = { { 62, "DAMAGER" }, { 63, "DAMAGER" }, { 64, "DAMAGER" } },    -- маг: Тайная, Огонь, Лёд
  [3] = { { 253, "DAMAGER" }, { 254, "DAMAGER" }, { 255, "DAMAGER" } }, -- охотник: ПЗ, Стрельба, Выживание
  [5] = { { 256, "HEALER" }, { 257, "HEALER" }, { 258, "DAMAGER" } },   -- жрец: Послушание, Свет, Тьма
}
local classID, current = 8, 2
UnitClass = function() return "x", "X", classID end
C_SpecializationInfo = {
  GetSpecialization = function() return current end,
  GetSpecializationInfo = function(i) local s = CLASSES[classID][i]; return s[1], "spec" .. s[1], nil, nil, s[2] end,
  SetSpecialization = function() return true end,
  GetNumSpecializationsForClassID = function(c) return #CLASSES[c] end,
}
local ns = {}
assert(loadfile(A .. "/Modules/CustomQueue/WargameFlow.lua"))("PvP_20_RatingTEST", ns)
local SpecPlan = ns.WargameFlow.SpecPlan

local function case(cls, cur, role, check, label)
  classID, current = cls, cur
  local seen = {}
  for _ = 1, 200 do seen[tostring(SpecPlan(role))] = true end
  local got = {}; for k in pairs(seen) do got[#got + 1] = k end
  assert(check(seen), label .. ": " .. table.concat(got, ","))
  print("ok  " .. label)
end
case(8, 2, "DAMAGER", function(s) return s["1"] and s["3"] and not s["2"] and not s["nil"] end, "маг Огонь → Тайная/Лёд случайно")
case(8, 1, "DAMAGER", function(s) return s["nil"] end, "маг Тайная — подходит")
case(3, 2, "DAMAGER", function(s) return s["1"] and not s["3"] end, "охотник Стрельба → Повелитель зверей")
case(5, 3, "HEALER", function(s) return s["1"] and s["2"] and not s["3"] end, "жрец Тьма, хост дал хила → Послушание/Свет")
case(5, 2, "DAMAGER", function(s) return s["3"] and not s["1"] end, "жрец Свет, хост дал бойца → Тьма")
case(5, 3, "DAMAGER", function(s) return s["nil"] end, "жрец Тьма, хост дал бойца — подходит")
case(5, 3, nil, function(s) return s["nil"] end, "роли от хоста нет — не трогаем")

-- AssignTeamRoles: гибкий «хил+боец» идёт хилом, только если хилов не хватает
local sm = {}
NUM_LE_LFG_CATEGORYS, MAX_WORLD_PVP_QUEUES = 0, 0
assert(loadfile(A .. "/Modules/CustomQueue/StateMachine.lua"))("PvP_20_RatingTEST", sm)
local roster = sm.StateMachine.GetQueueRoster()
roster.SOLO_SHUFFLE = {
  A = { roles = "H", subscribed = true }, B = { roles = "H;D", subscribed = true }, C = { roles = "D", subscribed = true },
  E = { roles = "H;D", subscribed = true }, F = { roles = "T;D", subscribed = true },
}
local c = { teamSize = 3, healersPerTeam = 1, minSubscribersPerTeam = 1 }
local r = sm.StateMachine.AssignTeamRoles("SOLO_SHUFFLE", { "A", "B", "C" }, c)
assert(r and r.A == "HEALER" and r.B == "DAMAGER" and r.C == "DAMAGER", "хил + гибкий: гибкий — боец")
r = sm.StateMachine.AssignTeamRoles("SOLO_SHUFFLE", { "B", "E", "C" }, c)
assert(r and (r.B == "HEALER") ~= (r.E == "HEALER"), "двое гибких: ровно один хил")
r = sm.StateMachine.AssignTeamRoles("SOLO_SHUFFLE", { "C", "F", "C" }, c)
assert(r == nil, "без хила — команда не собирается")
r = sm.StateMachine.AssignTeamRoles("SOLO_SHUFFLE", { "A", "F", "C" }, c)
assert(r and r.F == "DAMAGER", "танк+боец — боец")
print("ok  AssignTeamRoles: гибкие роли")
print("все случаи ok")
