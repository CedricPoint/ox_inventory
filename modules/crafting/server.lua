if not lib then return end

local CraftingBenches = {}
local Items = require 'modules.items.server'
local Inventory = require 'modules.inventory.server'

---@param id number
---@param data table
local function createCraftingBench(id, data)
	CraftingBenches[id] = {}
	local recipes = data.items

	if recipes then
		for i = 1, #recipes do
			local recipe = recipes[i]
			local item = Items(recipe.name)

			if item then
				recipe.weight = item.weight
				recipe.slot = i
			else
				warn(('failed to setup crafting recipe (bench: %s, slot: %s) - item "%s" does not exist'):format(id, i, recipe.name))
			end

			for ingredient, needs in pairs(recipe.ingredients) do
				if needs < 1 then
					item = Items(ingredient)

					if item and not item.durability then
						item.durability = true
					end
				end
			end
		end

		if shared.target then
			data.points = nil
		else
			data.zones = nil
		end

		CraftingBenches[id] = data
	end
end

local craftingDataFile = lib.load('data.crafting') or {}
--- Modèles immuables (deepclone) pour pouvoir réactiver après désactivation
local craftingTemplates = {}
for id, data in pairs(craftingDataFile) do
	local benchId = data.name or id
	craftingTemplates[benchId] = table.deepclone(data)
end

exports('SyncBuiltinCraftingAfterBlacklist', function(disabledBenchKeys)
	local dis = {}
	if type(disabledBenchKeys) == 'table' then
		for i = 1, #disabledBenchKeys do
			local k = disabledBenchKeys[i]
			if k ~= nil then dis[tostring(k)] = true end
		end
	end
	for benchId, pristine in pairs(craftingTemplates) do
		if dis[tostring(benchId)] then
			CraftingBenches[benchId] = nil
		else
			createCraftingBench(benchId, table.deepclone(pristine))
		end
	end
end)

for benchId, pristine in pairs(craftingTemplates) do
	createCraftingBench(benchId, table.deepclone(pristine))
end

--- Bancs craft issus de data/crafting.lua (id = data.name ou index)
exports('GetBuiltinCraftingBenches', function()
	local list = {}
	for benchId, pristine in pairs(craftingTemplates) do
		list[#list + 1] = { key = benchId, name = pristine.name or tostring(benchId) }
	end
	table.sort(list, function(a, b)
		return tostring(a.key) < tostring(b.key)
	end)
	return list
end)

---falls back to player coords if zones and points are both nil
---@param source number
---@param bench table
---@param index number
---@return vector3
local function getCraftingCoords(source, bench, index)
	if not bench.zones and not bench.points then
		return GetEntityCoords(GetPlayerPed(source))
	else
		return shared.target and bench.zones[index].coords or bench.points[index]
	end
end

lib.callback.register('ox_inventory:openCraftingBench', function(source, id, index)
	local left, bench = Inventory(source), CraftingBenches[id]

	if not left then return end

	if bench then
		local groups = bench.groups
		local coords = getCraftingCoords(source, bench, index)

		if not coords then return end

		if groups and not server.hasGroup(left, groups) then return end
		if #(GetEntityCoords(GetPlayerPed(source)) - coords) > 10 then return end

		if left.open and left.open ~= source then
			local inv = Inventory(left.open) --[[@as OxInventory]]

			-- Why would the player inventory open with an invalid target? Can't repro but whatever.
			if inv?.player then
				inv:closeInventory()
			end
		end

		left:openInventory(left)
	end

	return { label = left.label, type = left.type, slots = left.slots, weight = left.weight, maxWeight = left.maxWeight }
end)

local TriggerEventHooks = require 'modules.hooks.server'

lib.callback.register('ox_inventory:craftItem', function(source, id, index, recipeId, toSlot)
	local left, bench = Inventory(source), CraftingBenches[id]

	if not left then return end

	if bench then
		local groups = bench.groups
		local coords = getCraftingCoords(source, bench, index)

		if groups and not server.hasGroup(left, groups) then return end
		if #(GetEntityCoords(GetPlayerPed(source)) - coords) > 10 then return end

		local recipe = bench.items[recipeId]

		if recipe then
			local tbl, num = {}, 0

			for name in pairs(recipe.ingredients) do
				num += 1
				tbl[num] = name
			end

			local craftedItem = Items(recipe.name)
			local craftCount = (type(recipe.count) == 'number' and recipe.count) or (table.type(recipe.count) == 'array' and math.random(recipe.count[1], recipe.count[2])) or 1

			-- Modified weight calculation
			local newWeight = left.weight
			local items = Inventory.Search(left, 'slots', tbl) or {}
			---@todo new iterator or something to accept a map
			-- First subtract weight of ingredients that will be removed
			for name, needs in pairs(recipe.ingredients) do
				if needs > 0 then
					local item = Items(name)
					if item then
						newWeight -= (item.weight * needs)
					end
				end
			end

			-- Add weight of crafted item
			newWeight += (craftedItem.weight + (recipe.metadata?.weight or 0)) * craftCount

			if newWeight > left.maxWeight then return false, 'cannot_carry' end

			local items = Inventory.Search(left, 'slots', tbl) or {}
			table.wipe(tbl)

			for name, needs in pairs(recipe.ingredients) do
				if needs == 0 then break end

				local slots = items[name] or items

                if #slots == 0 then return end

				for i = 1, #slots do
					local slot = slots[i]

					if needs == 0 then
						if not slot.metadata.durability or slot.metadata.durability > 0 then
							break
						end
					elseif needs < 1 then
						local item = Items(name)
						local durability = slot.metadata.durability

						if durability and durability >= needs * 100 then
							if durability > 100 then
								local degrade = (slot.metadata.degrade or item.degrade) * 60
								local percentage = ((durability - os.time()) * 100) / degrade

								if percentage >= needs * 100 then
									tbl[slot.slot] = needs
									break
								end
							else
								tbl[slot.slot] = needs
								break
							end
						end
					elseif needs <= slot.count then
						tbl[slot.slot] = needs
						break
					else
						tbl[slot.slot] = slot.count
						needs -= slot.count
					end

					if needs == 0 then break end
					-- Player does not have enough items (ui should prevent crafting if lacking items, so this shouldn't trigger)
					if needs > 0 and i == #slots then return end
				end
			end

			if not TriggerEventHooks('craftItem', {
				source = source,
				benchId = id,
				benchIndex = index,
				recipe = recipe,
				toInventory = left.id,
				toSlot = toSlot,
			}) then return false end

			local success = lib.callback.await('ox_inventory:startCrafting', source, id, recipeId)

			if success then
				for name, needs in pairs(recipe.ingredients) do
					if Inventory.GetItemCount(left, name) < needs then return end
				end

				for slot, count in pairs(tbl) do
					local invSlot = left.items[slot]

					if not invSlot then return end

					if count < 1 then
						local item = Items(invSlot.name)
						local durability = invSlot.metadata.durability or 100

						if durability > 100 then
							local degrade = (invSlot.metadata.degrade or item.degrade) * 60
							durability -= degrade * count
						else
							durability -= count * 100
						end

						if invSlot.count > 1 then
							local emptySlot = Inventory.GetEmptySlot(left)

							if emptySlot then
								local newItem = Inventory.SetSlot(left, item, 1, table.deepclone(invSlot.metadata), emptySlot)

								if newItem then
                                    Items.UpdateDurability(left, newItem, item, durability < 0 and 0 or durability)
								end
							end

							invSlot.count -= 1
                            invSlot.weight = Inventory.SlotWeight(item, invSlot)

							left:syncSlotsWithClients({
								{
									item = invSlot,
									inventory = left.id
								}
							}, true)
						else
                            Items.UpdateDurability(left, invSlot, item, durability < 0 and 0 or durability)
						end
					else
						local removed = invSlot and Inventory.RemoveItem(left, invSlot.name, count, nil, slot)
						-- Failed to remove item (inventory state unexpectedly changed?)
						if not removed then return end
					end
				end

				Inventory.AddItem(left, craftedItem, craftCount, recipe.metadata or {}, craftedItem.stack and toSlot or nil)
			end

			return success
		end
	end
end)

--- Bancs craft dynamiques (asc_staff) — même logique que data/crafting
exports('UpsertCraftingBench', function(id, data)
	if not id or type(data) ~= 'table' then return end
	createCraftingBench(id, data)
end)

exports('RemoveCraftingBench', function(id)
	CraftingBenches[id] = nil
end)

--- Retire les bancs craft dynamiques asc_staff (clés ASC_OX_*) avant réapplication SQL
exports('ClearAscensionDynamicCrafting', function()
	for id in pairs(CraftingBenches) do
		if type(id) == 'string' and id:sub(1, 7) == 'ASC_OX_' then
			CraftingBenches[id] = nil
		end
	end
end)
