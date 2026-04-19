--[[
    Désactivations « défaut » (table asc_staff_ox_disabled_defaults) sans dépendre d’asc_staff au démarrage.
    Convar : setr inventory:asc_staff_disabled_table "asc_staff_ox_disabled_defaults"
]]

if not lib then return end

local function sanitizeTableName(name)
	if type(name) ~= 'string' or not name:match('^[%w_]+$') then
		return 'asc_staff_ox_disabled_defaults'
	end
	return name
end

local function disabledTableName()
	return sanitizeTableName(GetConvar('inventory:asc_staff_disabled_table', 'asc_staff_ox_disabled_defaults'))
end

--- Lit la SQL, réapplique serveur + notifie les clients (payload partiel, sans toucher aux shops SQL asc_staff)
function AscStaffBlacklistApplyFromDb()
	local tbl = disabledTableName()
	local ok, rows = pcall(function()
		return MySQL.query.await(('SELECT `kind`, `internal_key` FROM `%s`'):format(tbl)) or {}
	end)
	if not ok or type(rows) ~= 'table' then return end
	local dshops, dcraft = {}, {}
	for i = 1, #rows do
		if rows[i].kind == 'shop' then
			dshops[#dshops + 1] = rows[i].internal_key
		elseif rows[i].kind == 'craft' then
			dcraft[#dcraft + 1] = rows[i].internal_key
		end
	end
	pcall(function()
		exports.ox_inventory:SyncBuiltinShopsAfterBlacklist(dshops)
	end)
	pcall(function()
		exports.ox_inventory:SyncBuiltinCraftingAfterBlacklist(dcraft)
	end)
	TriggerClientEvent('asc_staff:client:oxInventoryPointsApply', -1, {
		disabledBuiltinShops = dshops,
		disabledBuiltinCrafting = dcraft,
	})
end

MySQL.ready(function()
	CreateThread(function()
		Wait(800)
		AscStaffBlacklistApplyFromDb()
	end)
end)

--- Joueur qui se connecte après le boot (ou race) : réapplique côté client uniquement
RegisterNetEvent('ox_inventory:server:requestBuiltinBlacklist', function()
	local src = source
	if not src or src < 1 then return end
	local tbl = disabledTableName()
	local ok, rows = pcall(function()
		return MySQL.query.await(('SELECT `kind`, `internal_key` FROM `%s`'):format(tbl)) or {}
	end)
	local dshops, dcraft = {}, {}
	if ok and type(rows) == 'table' then
		for i = 1, #rows do
			if rows[i].kind == 'shop' then
				dshops[#dshops + 1] = rows[i].internal_key
			elseif rows[i].kind == 'craft' then
				dcraft[#dcraft + 1] = rows[i].internal_key
			end
		end
	end
	TriggerClientEvent('asc_staff:client:oxInventoryPointsApply', src, {
		disabledBuiltinShops = dshops,
		disabledBuiltinCrafting = dcraft,
	})
end)

exports('ApplyStaffBuiltinBlacklistFromDb', AscStaffBlacklistApplyFromDb)
