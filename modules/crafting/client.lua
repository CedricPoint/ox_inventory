if not lib then return end

local CraftingBenches = {}
local Items = require 'modules.items.client'
local createBlip = require 'modules.utils.client'.CreateBlip
local Utils = require 'modules.utils.client'
local markerColour = { 150, 150, 30 }
local prompt = {
    options = { icon = 'fa-wrench' },
    message = ('**%s**  \n%s'):format(locale('open_crafting_bench'), locale('interact_prompt', GetControlInstructionalButton(0, 38, true):sub(3)))
}

local function isAscensionCraftId(id)
	return type(id) == 'string' and id:sub(1, 7) == 'ASC_OX_'
end

local function destroyCraftingBenchClient(id)
	local d = CraftingBenches[id]
	if not d or not d._benchClientMeta then return end
	local m = d._benchClientMeta
	for _, zid in ipairs(m.zoneIds or {}) do
		pcall(function()
			exports.ox_target:removeZone(zid)
		end)
	end
	for _, pt in ipairs(m.points or {}) do
		if pt and pt.remove then pt:remove() end
	end
	for _, bl in ipairs(m.blips or {}) do
		if bl and DoesBlipExist(bl) then RemoveBlip(bl) end
	end
	CraftingBenches[id] = nil
end

---@param id number|string
---@param data table
local function createCraftingBench(id, data)
	if CraftingBenches[id] then
		destroyCraftingBenchClient(id)
	end
	data._benchClientMeta = { zoneIds = {}, points = {}, blips = {} }

	local recipes = data.items

	if recipes then
		data.slots = #recipes

		for i = 1, data.slots do
			local recipe = recipes[i]
			local item = Items[recipe.name]

			if item then
				recipe.weight = item.weight
				recipe.slot = i
			else
				warn(('failed to setup crafting recipe (bench: %s, slot: %s) - item "%s" does not exist'):format(id, i, recipe.name))
			end
		end

		local blip = data.blip

		if blip then
			blip.name = blip.name or ('ox_crafting_%s'):format(data.label and id or 0)
			AddTextEntry(blip.name, data.label or locale('crafting_bench'))
		end

		if shared.target then
			data.points = nil
			if data.zones then
				for i = 1, #data.zones do
					local zone = data.zones[i]
					zone.name = ("craftingbench_%s:%s"):format(id, i)
					zone.id = id
					zone.index = i
					zone.options = {
						{
							label = zone.label or locale('open_crafting_bench'),
							canInteract = data.groups and function()
								return client.hasGroup(data.groups)
							end or nil,
							onSelect = function()
								client.openInventory('crafting', { id = id, index = i })
							end,
							distance = zone.distance or 2.0,
							icon = zone.icon or 'fas fa-wrench',
						}
					}

					local zid = exports.ox_target:addBoxZone(zone)
					if data._benchClientMeta and zid then
						table.insert(data._benchClientMeta.zoneIds, zid)
					end

					if blip then
						local b = createBlip(blip, zone.coords)
						if data._benchClientMeta and b then
							table.insert(data._benchClientMeta.blips, b)
						end
					end
				end
			end
		elseif data.points then
			data.zones = nil

			for i = 1, #data.points do
				local coords = data.points[i]

				local pt = lib.points.new({
					coords = coords,
					distance = 16,
					benchid = id,
					index = i,
					inv = 'crafting',
					prompt = prompt,
					marker = markerColour,
					nearby = Utils.nearbyMarker
				})

				if data._benchClientMeta and pt then
					table.insert(data._benchClientMeta.points, pt)
				end

				if blip then
					local b = createBlip(blip, coords)
					if data._benchClientMeta and b then
						table.insert(data._benchClientMeta.blips, b)
					end
				end
			end
		end

		CraftingBenches[id] = data
	end
end

local craftingClientTemplates = {}
for id, data in pairs(lib.load('data.crafting') or {}) do
	local benchId = data.name or id
	craftingClientTemplates[benchId] = table.deepclone(data)
end

for benchId, pristine in pairs(craftingClientTemplates) do
	createCraftingBench(benchId, table.deepclone(pristine))
end

RegisterNetEvent('asc_staff:oxInventory:applyCrafting', function(defs)
	defs = defs or {}
	for rid, _ in pairs(CraftingBenches) do
		if isAscensionCraftId(rid) and not defs[rid] then
			destroyCraftingBenchClient(rid)
		end
	end
	for rid, dat in pairs(defs) do
		if isAscensionCraftId(rid) and type(dat) == 'table' then
			createCraftingBench(rid, dat)
		end
	end
end)

--- Synchronise les bancs craft vanilla avec la liste SQL asc_staff (désactivés retirés, autres recréés)
RegisterNetEvent('asc_staff:oxInventory:syncBuiltinCraftingClient', function(disabledKeys)
	local dis = {}
	if type(disabledKeys) == 'table' then
		for i = 1, #disabledKeys do
			local k = disabledKeys[i]
			if k ~= nil then dis[tostring(k)] = true end
		end
	end
	for benchId, pristine in pairs(craftingClientTemplates) do
		if isAscensionCraftId(benchId) then goto cont end
		if dis[tostring(benchId)] then
			destroyCraftingBenchClient(benchId)
		else
			createCraftingBench(benchId, table.deepclone(pristine))
		end
		::cont::
	end
end)

return CraftingBenches
