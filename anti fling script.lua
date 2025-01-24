local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

-- Configuration
local ANTI_FLING_THRESHOLD = 100
local ANTI_FLING_ENABLED = true
local BAN_THRESHOLD = 3 -- Number of times a player triggers anti-fling before ban
local CHECK_INTERVAL = 0.1 -- How often to check for flinging
local DEBUG_MODE = true -- Enable debug logging

-- Constants
local PHYSICAL_PROPERTIES = PhysicalProperties.new(0, 0, 0, 0, 0)
local ANTI_FLING_CONNECTIONS = {}
local FLING_COUNTS = {}
local LAST_VELOCITIES = {}
local LAST_POSITIONS = {}
local PLAYER_DATA = {}

-- Spatial Partitioning (Simple Grid)
local GRID_SIZE = 10
local SPATIAL_GRID = {}

-- Helper Functions
local function debugLog(message)
if DEBUG_MODE then
print("[Anti-Fling Debug]: " .. message)
end
end

local function getGridCell(position)
return Vector3.new(math.floor(position.X / GRID_SIZE), math.floor(position.Y / GRID_SIZE), math.floor(position.Z / GRID_SIZE))
end

local function updateSpatialGrid(part, oldCell)
if not part or not part:IsA("BasePart") then return end

local newCell = getGridCell(part.Position)

if oldCell then
	local cellParts = SPATIAL_GRID[oldCell]
	if cellParts then
		for i, v in ipairs(cellParts) do
			if v == part then
				table.remove(cellParts, i)
				break
			end
		end
		if #cellParts == 0 then
			SPATIAL_GRID[oldCell] = nil
		end
	end
end

if not SPATIAL_GRID[newCell] then
	SPATIAL_GRID[newCell] = {}
end
table.insert(SPATIAL_GRID[newCell], part)
end

local function getNearbyParts(position, radius)
local nearbyParts = {}
local centerCell = getGridCell(position)

for x = -1, 1 do
	for y = -1, 1 do
		for z = -1, 1 do
			local cell = centerCell + Vector3.new(x, y, z)
			local cellParts = SPATIAL_GRID[cell]
			if cellParts then
				for _, part in ipairs(cellParts) do
					if (part.Position - position).Magnitude <= radius then
						table.insert(nearbyParts, part)
					end
				end
			end
		end
	end
end
return nearbyParts
end

local function resetHumanoidRootPartPhysics(rootPart)
if not rootPart or not rootPart:IsA("BasePart") then return end

rootPart.Massless = true
rootPart.Friction = 0
rootPart.AssemblyLinearVelocity = Vector3.zero
rootPart.AssemblyAngularVelocity = Vector3.zero
rootPart.CanCollide = false
debugLog("Physics reset for " .. rootPart:GetFullName())
end

local function applyAntiFlingProperties(part)
if not part or not part:IsA("BasePart") or part.Anchored then
return
end

if part.Name == "HumanoidRootPart" then
	part.CustomPhysicalProperties = PHYSICAL_PROPERTIES
	part.Velocity = Vector3.zero
	part.RotVelocity = Vector3.zero
	part.CanCollide = false
	debugLog("Anti-fling properties applied to " .. part:GetFullName())
end
end

local function checkAndApplyAntiFling(part)
if not part or not part:IsA("BasePart") then return end
applyAntiFlingProperties(part)
end

local function banPlayer(player, reason)
if not player then return end
debugLog("Banning player " .. player.Name .. " for: " .. reason)
player:Kick("Banned for exploiting: " .. reason)
end

local function checkPlayer(player)
local character = player.Character
if not character then return end

local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
if humanoidRootPart then
	resetHumanoidRootPartPhysics(humanoidRootPart)
	if ANTI_FLING_ENABLED then
		applyAntiFlingProperties(humanoidRootPart)
	end
	PLAYER_DATA[player] = {
		lastPosition = humanoidRootPart.Position,
		lastVelocity = humanoidRootPart.AssemblyLinearVelocity,
		flingCount = 0,
		lastCheckTime = os.time()
	}
	updateSpatialGrid(humanoidRootPart)
end
end

local function onCharacterDied(player)
local data = PLAYER_DATA[player]
if data then
local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
if rootPart then
updateSpatialGrid(rootPart, getGridCell(rootPart.Position))
end
PLAYER_DATA[player] = nil
end
for _, connection in ipairs(ANTI_FLING_CONNECTIONS) do
if connection and connection.Disconnect then
connection:Disconnect()
end
end
table.clear(ANTI_FLING_CONNECTIONS)
end

local function antiFling()
if not ANTI_FLING_ENABLED then return end

local client = Players.LocalPlayer
local character = client and client.Character

onCharacterDied(client)

for _, descendant in ipairs(workspace:GetDescendants()) do
	checkAndApplyAntiFling(descendant)
end

local heartbeatConnection = RunService.Heartbeat:Connect(function()
	for _, descendant in ipairs(workspace:GetDescendants()) do
		checkAndApplyAntiFling(descendant)
	end
end)

table.insert(ANTI_FLING_CONNECTIONS, heartbeatConnection)

if character and character:FindFirstChild("Humanoid") then
	local diedConnection = character.Humanoid.Died:Connect(function() onCharacterDied(client) end)
	table.insert(ANTI_FLING_CONNECTIONS, diedConnection)
end

debugLog("Anti-Fling Activated!")
end

-- Initial setup for existing players
for _, player in ipairs(Players:GetPlayers()) do
checkPlayer(player)
end

-- Handle new players
Players.PlayerAdded:Connect(function(player)
checkPlayer(player)
player.CharacterAdded:Connect(function(character)
task.wait(2)
antiFling()
end)
end)

-- Apply anti-fling to new parts
workspace.DescendantAdded:Connect(function(part)
if part:IsA("BasePart") then
checkAndApplyAntiFling(part)
if part.Name == "HumanoidRootPart" then
task.wait(2)
antiFling()
end
end
end)

-- Main loop for velocity and position checks
RunService.Heartbeat:Connect(function()
for player, data in pairs(PLAYER_DATA) do
local character = player.Character
if not character then
PLAYER_DATA[player] = nil
continue
end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		PLAYER_DATA[player] = nil
		continue
	end
	
	local currentTime = os.time()
	if currentTime - data.lastCheckTime < CHECK_INTERVAL then
		continue
	end
	data.lastCheckTime = currentTime

	-- Velocity check
	local currentVelocity = humanoidRootPart.AssemblyLinearVelocity
	local velocityChange = (currentVelocity - data.lastVelocity).Magnitude

	-- Position check
	local currentPosition = humanoidRootPart.Position
	local positionChange = (currentPosition - data.lastPosition).Magnitude

	if velocityChange > ANTI_FLING_THRESHOLD or positionChange > ANTI_FLING_THRESHOLD then
		data.flingCount = data.flingCount + 1
		resetHumanoidRootPartPhysics(humanoidRootPart)
		debugLog("Fling detected for " .. player.Name .. ", count: " .. data.flingCount)
		if data.flingCount >= BAN_THRESHOLD then
			banPlayer(player, "Excessive flinging")
			PLAYER_DATA[player] = nil
			return
		end
	end

	data.lastVelocity = currentVelocity
	data.lastPosition = currentPosition
	
	updateSpatialGrid(humanoidRootPart, getGridCell(data.lastPosition))

	-- Network ownership removal (only if necessary)
	if humanoidRootPart:GetNetworkOwner() ~= nil then
		humanoidRootPart:SetNetworkOwner(nil)
	end
end
end)

-- Initial anti-fling activation
task.wait(4)
if not game:IsLoaded() then
repeat task.wait() until game:IsLoaded()
end

local client = Players.LocalPlayer
if client then
antiFling()
client.CharacterAdded:Connect(function(character)
task.wait(2)
antiFling()
end)
end
