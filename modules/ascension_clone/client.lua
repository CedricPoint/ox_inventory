--- Ped clone **local** (CreatePed isNetwork=false) : repositionné chaque sync sur le rayon
--- GetWorldCoordFromScreenCoord(viewport) pour rester calé sur le « trou » NUI quand le joueur se déplace.

local clonePed
local lastSync = 0
local headingExtra = 0.0

local screenNx = 0.5
local screenNy = 0.42

local function deleteClone()
	if clonePed and DoesEntityExist(clonePed) then
		DeletePed(clonePed)
	end
	clonePed = nil
end

local function rotationToDirection(rot)
	local z = math.rad(rot.z)
	local x = math.rad(rot.x)
	local cosx = math.abs(math.cos(x))
	return vector3(-math.sin(z) * cosx, math.cos(z) * cosx, math.sin(x))
end

local function cloneDistance()
	local v = tonumber(GetConvar('inventory:ascension_clone_dist', '3.35'))
	if not v or v < 0.4 or v > 25.0 then return 3.35 end
	return v
end

local function cloneVerticalBias()
	return tonumber(GetConvar('inventory:ascension_clone_zbias', '0.0')) or 0.0
end

local function getCloneTargetPosition()
	local cam = GetGameplayCamCoord()
	local dist = cloneDistance()
	local pos

	local ok, w, dir = pcall(function()
		return GetWorldCoordFromScreenCoord(screenNx, screenNy)
	end)
	if ok and w and dir and type(w) == 'vector3' and type(dir) == 'vector3' then
		pos = w + dir * dist
	end

	if not pos then
		local dir2 = rotationToDirection(GetGameplayCamRot(2))
		pos = cam + dir2 * dist
	end

	pos = vector3(pos.x, pos.y, pos.z + cloneVerticalBias())

	if GetConvarInt('inventory:ascension_clone_ground', 0) == 1 then
		local found, gz = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 2.0, false)
		if found and math.abs(gz - pos.z) < 1.25 then
			pos = vector3(pos.x, pos.y, gz + cloneVerticalBias())
		end
	end

	return pos, cam
end

local function headingFaceCamera(pos, cam)
	local dx, dy = cam.x - pos.x, cam.y - pos.y
	if math.abs(dx) < 0.02 and math.abs(dy) < 0.02 then
		return (GetGameplayCamRot(2).z + 180.0) % 360.0
	end
	local hok, h = pcall(GetHeadingFromVector_2d, dx, dy)
	if hok and type(h) == 'number' then
		return h
	end
	return (math.deg(math.atan2(-dx, dy)) + 360.0) % 360.0
end

local function applyCloneTransform(pos, cam)
	if not clonePed or not DoesEntityExist(clonePed) then return end
	SetEntityCoordsNoOffset(clonePed, pos.x, pos.y, pos.z, false, false, false)
	SetEntityHeading(clonePed, headingFaceCamera(pos, cam) + headingExtra)
end

local function copyAppearanceToClone(playerPed, targetPed)
	if GetResourceState('illenium-appearance') == 'started' then
		local ok, appearance = pcall(function()
			return exports['illenium-appearance']:getPedAppearance(playerPed)
		end)
		if ok and appearance then
			pcall(function()
				exports['illenium-appearance']:setPedAppearance(targetPed, appearance)
			end)
			return
		end
	end

	for comp = 0, 11 do
		SetPedComponentVariation(
			targetPed,
			comp,
			GetPedDrawableVariation(playerPed, comp),
			GetPedTextureVariation(playerPed, comp),
			0
		)
	end
	for pr = 0, 7 do
		local d = GetPedPropIndex(playerPed, pr)
		if d ~= -1 then
			SetPedPropIndex(targetPed, pr, d, GetPedPropTextureIndex(playerPed, pr), false)
		else
			ClearPedProp(targetPed, pr)
		end
	end
end

local function configureCloneEntity(ped)
	--- isNetwork=false : ped **uniquement sur ce client** (les autres joueurs ne le reçoivent pas).
	SetEntityAsMissionEntity(ped, true, true)
	SetEntityInvincible(ped, true)
	FreezeEntityPosition(ped, true)
	SetBlockingOfNonTemporaryEvents(ped, true)
	SetPedCanRagdoll(ped, false)
	SetPedCanBeTargetted(ped, false)
	SetEntityCollision(ped, false, false)
	SetEntityProofs(ped, true, true, true, true, true, true, true, true)
	TaskStandStill(ped, -1)
	pcall(function()
		NetworkSetEntityInvisibleToNetwork(ped, true)
	end)
end

local M = {}

function M.setScreenTarget(nx, ny)
	if type(nx) == 'number' and type(ny) == 'number' then
		screenNx = math.min(0.995, math.max(0.005, nx))
		screenNy = math.min(0.995, math.max(0.005, ny))
	end
	lastSync = 0
	if clonePed and DoesEntityExist(clonePed) then
		local pos, cam = getCloneTargetPosition()
		applyCloneTransform(pos, cam)
	end
end

function M.start()
	deleteClone()
	headingExtra = 0.0
	if GetConvarInt('inventory:ascension_clone', 1) ~= 1 then return end

	local playerPed = cache.ped
	if not playerPed or playerPed == 0 or not DoesEntityExist(playerPed) then return end

	local model = GetEntityModel(playerPed)
	if not IsModelInCdimage(model) then return end

	lib.requestModel(model)

	local pos, cam = getCloneTargetPosition()
	local h = headingFaceCamera(pos, cam) + headingExtra

	--- Dernier booléan false = **pas** d’entité réseau → invisible / inexistant pour les autres clients.
	clonePed = CreatePed(26, model, pos.x, pos.y, pos.z, h, false, false)
	SetModelAsNoLongerNeeded(model)

	if not clonePed or clonePed == 0 or not DoesEntityExist(clonePed) then
		clonePed = nil
		return
	end

	configureCloneEntity(clonePed)

	copyAppearanceToClone(playerPed, clonePed)
	applyCloneTransform(pos, cam)
end

function M.stop()
	deleteClone()
	lastSync = 0
	headingExtra = 0.0
	screenNx = 0.5
	screenNy = 0.42
end

function M.sync()
	if not clonePed or not DoesEntityExist(clonePed) then return end
	local now = GetGameTimer()
	local interval = GetConvarInt('inventory:ascension_clone_sync_ms', 80)
	if interval < 40 then interval = 40 elseif interval > 250 then interval = 250 end
	if now - lastSync < interval then return end
	lastSync = now
	local playerPed = cache.ped
	if not playerPed or not DoesEntityExist(playerPed) then return end

	copyAppearanceToClone(playerPed, clonePed)

	local pos, cam = getCloneTargetPosition()
	applyCloneTransform(pos, cam)
end

function M.rotateWithPlayer(delta)
	local d = tonumber(delta) or 0
	if d == 0 then return end
	headingExtra = headingExtra - d * 0.045
	if clonePed and DoesEntityExist(clonePed) then
		local pos, cam = getCloneTargetPosition()
		applyCloneTransform(pos, cam)
	end
end

function M.getPed()
	return clonePed
end

AddEventHandler('onResourceStop', function(resourceName)
	if resourceName == GetCurrentResourceName() then
		deleteClone()
	end
end)

return M
