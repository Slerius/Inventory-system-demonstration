-- This script is a server sided inventory handler with many functions such as gadgets, pick up, drop, handling other items like chests, furnaces, crafting, etc.

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MS = game:GetService("MarketplaceService")
local GlobalData = require(game:GetService("ReplicatedStorage").Modules.GlobalData) -- this is the data that is shared between the entire server, setting cycles and world infection tier

local items = require(RS.Modules.Items) -- this is a table of each item in the game
local Assets = require(RS.Modules.Assets) -- this is a table of each damagable asset/creature
local Recipes = require(RS.Modules.Recipes) -- this is a table of all crafting recipes
local builds = require(RS.Modules.Builds) -- this is a table of all builds you can create with
local mainfunctions = require(script.Parent.MainFunctions) -- mainfunctions handle most of the important stuff like damaging players, assets, drops on player death etc. 


local LooseFolder = workspace.Loose -- folder for collectible assets

local inventory = {}

local DETECTION_RADIUS = 25 -- radius for detecting collectible items
local INVENTORY_SIZE = 40 -- inventory size
local GADGETS_SIZE = 7 -- gadget slots
local HOTBAR_SIZE = 7 -- hotbar slots

function inventory.fillHotbarSlots(hotbar) -- fills the indexed slots into a "empty" string so there isnt any iteration jump glitch when using pairs/ipairs
	local filled = {}
	for i = 1, HOTBAR_SIZE do
		if hotbar[i] then
			filled[i] = hotbar[i]
		else
			filled[i] = "Empty"
		end
	end
	return filled
end


function inventory.fillInventorySlots(inv) -- same as the hotbar ver
	local filled = {}
	for i = 1, INVENTORY_SIZE do
		filled[i] = inv[i] or "Empty"
	end
	return filled
end

function inventory.fillGadgetSlots(gadgets) -- same as the hotbar ver
	local filled = {}
	for i = 1, GADGETS_SIZE do
		filled[i] = gadgets[i] or "Empty"
	end
	return filled
end

function inventory.AddItem(player, itemName, amountOrUses, equip) -- adds an item cleanly to the player invenotry
	local id = player.UserId
	local itemData = items[itemName]
	if not itemData then return false end

	local hotbar = inventory.fillHotbarSlots(_G.SessionData.hotbar[id])
	local inv = inventory.fillInventorySlots(_G.SessionData.inventory[id])
	local gadgets = inventory.fillGadgetSlots(_G.SessionData.gadgets[id])

	local found = false

	if equip and itemData.Gadget then -- equip is used to know if auto equip a gadget when crafting or getting it on your inventory, this part iterates through the gadgets and if theres an empty space it adds the gadget
		for i, slot in pairs(gadgets) do
			if slot == "Empty" then
				gadgets[i] = { Name = itemName, Ammount = amountOrUses or 1}
				_G.SessionData.gadgets[id] = gadgets
				return true
			end
		end
	end

	if itemData.Tool then -- checks if the item is a tool and then adds it to the hotbar, increasing the ammount or adding a new slot if there is none
		for _, entry in pairs(hotbar) do
			if typeof(entry) == "table" and entry.Name == itemName and entry.Ammount then
				entry.Ammount += amountOrUses or 1
				_G.SessionData.hotbar[id] = hotbar
				return true
			end
		end

		for i, slot in pairs(hotbar) do
			if slot == "Empty" then
				hotbar[i] = { Name = itemName, Ammount = amountOrUses or 1, Uses = itemData.Uses }
				_G.SessionData.hotbar[id] = hotbar
				return true
			end
		end
	end


	for _, entry in pairs(inv) do -- if none of the other ones work this does the same but for the inventory
		if typeof(entry) == "table" and entry.Name == itemName and entry.Ammount then
			entry.Ammount += amountOrUses or 1
			_G.SessionData.inventory[id] = inv
			return true
		end
	end

	for i, slot in pairs(inv) do 
		if slot == "Empty" then
			inv[i] = { Name = itemName, Ammount = amountOrUses or 1 }
			_G.SessionData.inventory[id] = inv
			return true
		end
	end

	return false
end

-- setup for pickup items
local DetectionParts = {}
local pickupCooldown = {}

local function getDetectionPart(player) -- returns or generates a part that the player can use to detect items arround them
	local id = player.UserId

	if DetectionParts[id] then
		return DetectionParts[id]
	end

	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(DETECTION_RADIUS * 2, DETECTION_RADIUS * 2, DETECTION_RADIUS * 2)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.Transparency = 1
	part.Name = "PickupDetector_" .. id
	part.Parent = workspace

	DetectionParts[id] = part

	return part
end

function inventory.PickUpItem(player) -- lets the player pick up items arround
	local id = player.UserId
	local character = player.Character
	if not character then return end

	if GlobalData.Pickup == false then -- returns if picking items is disabled
		RS.Events.Message:FireClient(player, "Pickup Is Disabled!", RS.Sounds.Error)
		return
	end

	if pickupCooldown[id] then return end -- prevents spam
	pickupCooldown[id] = true

	task.delay(0.3, function()
		pickupCooldown[id] = nil
	end)

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local detector = getDetectionPart(player) -- get or create the part for the player

	detector.Position = hrp.Position
	local parts = workspace:GetPartsInPart(detector)

	local closestItem = nil
	local shortestDistance = DETECTION_RADIUS
	local checked = {} -- prevents checking same model multiple times

	for _, part in pairs(parts) do -- checks for items arround (only inside sphere)

		if part.Name ~= "Handle" then continue end

		local model = part.Parent
		if not model or checked[model] or model.Parent ~= LooseFolder then continue end
		checked[model] = true

		local distance = (part.Position - hrp.Position).Magnitude

		if distance < shortestDistance then
			shortestDistance = distance
			closestItem = model
		end
	end

	if closestItem then -- the picking up logic
		local itemName = closestItem.Name

		if itemName == "BloodStone" then -- special case for bloodstone because its the game currency
			if MS:UserOwnsGamePassAsync(player.UserId, 1459647769) then
				_G.data.playerdata[player.UserId].BloodStone += 2
			else
				_G.data.playerdata[player.UserId].BloodStone += 1
			end
			closestItem:Destroy()
			return
		end

		local success = inventory.AddItem(player, itemName, 1) -- adds the item to the inventory if possible

		if success then
			if closestItem:FindFirstChild("Respawn") then -- respawn if necessary
				local clone = closestItem:Clone()

				task.delay(40, function()
					clone.Parent = LooseFolder
				end)
			end

			closestItem:Destroy()

			RS.Events.Inventory:FireClient(player, inventory.fillInventorySlots(_G.SessionData.inventory[id]))
			RS.Events.HotBar:FireClient(player, _G.SessionData.hotbar[id])
		else -- doesnt pick up the item if theres an error with picking up
			RS.Events.Message:FireClient(player, "Inventory is full!", RS.Sounds.Error)
		end
	end
end



function inventory.RemoveItem(player, itemName, amount) -- removes an item from the player inventory
	local id = player.UserId
	local inv = inventory.fillInventorySlots(_G.SessionData.inventory[id])
	local Hotbar = inventory.fillHotbarSlots(_G.SessionData.hotbar[id])
	local Gadgets = inventory.fillGadgetSlots(_G.SessionData.gadgets[id])
	local remaining = amount -- how many items need to be removed

	local function removeFromContainer(container) -- function to check containers
		for i, entry in pairs(container) do
			if typeof(entry) == "table" and entry.Name == itemName then
				if entry.Ammount and entry.Ammount >= remaining then
					entry.Ammount -= remaining
					if entry.Ammount <= 0 then container[i] = "Empty" end
					remaining = 0
					break
				elseif entry.Ammount then
					remaining -= entry.Ammount
					container[i] = "Empty"
				else
					container[i] = "Empty"
					remaining -= 1
				end
			end
		end
	end


	removeFromContainer(inv) -- first tries to remove from the inventory
	if remaining > 0 then removeFromContainer(Hotbar) end -- if there are still items left then it checks for the hotbar
	if remaining > 0 then removeFromContainer(Gadgets) end -- same for gadgets



	_G.SessionData.inventory[id] = inv
	_G.SessionData.hotbar[id] = Hotbar
	_G.SessionData.gadgets[id] = Gadgets


	if remaining <= 0 then
		return true -- only works if the user has the ammount of items to remove
	end
end



function inventory.SwapSlot(player, fromType, fromIndex, toType, toIndex, chestId) --swaps 2 items position on the inventory or any type of container
	local id = player.UserId

	local inv = inventory.fillInventorySlots(_G.SessionData.inventory[id])
	local Hotbar = _G.SessionData.hotbar[id]
	local Gadgets = _G.SessionData.gadgets[id]

	local chestStorage
	-- only allow chest access if it exists and player is registered inside it
	if chestId and _G.ActiveChests and _G.ActiveChests[chestId] and _G.ActiveChests[chestId].Storage and _G.ActiveChests[chestId].Players and _G.ActiveChests[chestId].Players[id] then
		chestStorage = _G.ActiveChests[chestId].Storage
	end

	local function getTable(typeStr) -- returns the container type with a string
		if typeStr == "Inventory" then
			return inv
		elseif typeStr == "Hotbar" then
			return Hotbar
		elseif typeStr == "Gadgets" then
			return Gadgets
		elseif typeStr == "Chest" and chestStorage then
			return chestStorage
		end
	end

	local fromTable = getTable(fromType)
	local toTable = getTable(toType)
	if not fromTable or not toTable then return end -- return if its an invalid container

	local item = fromTable[fromIndex]
	local targetItem = toTable[toIndex]
	if not item or not item.Name then return end

	local itemData = items[item.Name]
	local targetData = targetItem and targetItem.Name and items[targetItem.Name]

	-- prevents non-tools from going into hotbar
	if toType == "Hotbar" and (not itemData or not itemData.Tool) then return end
	if targetData and fromType == "Hotbar" and not targetData.Tool then return end

	-- prevents non-gadgets from going into gadget slots
	if toType == "Gadgets" and (not itemData or not itemData.Gadget) then return end
	if targetData and fromType == "Gadgets" and not targetData.Gadget then return end

	-- only allow one bag-type gadget at a time
	if toType == "Gadgets" and itemData and itemData.Gadget then
		if itemData.Bag then
			for _, slot in pairs(Gadgets) do
				if slot.Name and items[slot.Name] and items[slot.Name].Gadget and items[slot.Name].Bag then
					return
				end
			end
		end
	end

	-- actual swap
	fromTable[fromIndex] = targetItem
	toTable[toIndex] = item

	_G.SessionData.inventory[id] = inv
	_G.SessionData.hotbar[id] = Hotbar
	_G.SessionData.gadgets[id] = Gadgets

	if chestStorage then -- update chest if used
		_G.ActiveChests[chestId].Storage = chestStorage
	end

	-- small delay so client updates feel smoother / avoids race conditions
	task.delay(0.1, function()
		RS.Events.Inventory:FireClient(player, inventory.fillInventorySlots(inv))
		RS.Events.HotBar:FireClient(player, Hotbar)
		RS.Events.Gadget:FireClient(player, Gadgets)

		if chestStorage then
			RS.Events.UpdateChest:FireClient(player, chestId, chestStorage)
		end
	end)
end


local ActiveGadgetModules = {}

function inventory.Gadget(player) -- handles player equipping and unequipping gadgets (gadgets give different buffs and abilities)
	local userId = player.UserId

	local currentGadgets = _G.SessionData.gadgets[userId]
	local newGadgets = {} -- used to track which gadgets should remain active

	ActiveGadgetModules[userId] = ActiveGadgetModules[userId] or {}

	for _, gadget in pairs(currentGadgets) do
		if gadget ~= "Empty" and gadget.Name then

			newGadgets[gadget.Name] = true

			-- only start the gadget if its not running already
			if not ActiveGadgetModules[userId][gadget.Name] then

				local moduleScript = RS.Modules.Gadgets:FindFirstChild(gadget.Name)

				if moduleScript then
					local success, module = pcall(require, moduleScript)

					-- ensures the module works
					if success and typeof(module.Start) == "function" then

						local clone = RS.Accessories[gadget.Name]:Clone()
						clone.Parent = player.Character -- attach visual

						task.spawn(function() -- run async so it doesnt block
							module.Start(player)
						end)

						ActiveGadgetModules[userId][gadget.Name] = module
					else
						warn(gadget.Name .. " module is missing a Start function or failed to load.")
					end
				else
					-- still give accessory even if there isnt any module, this is used for gadgets that affect mainfunctions
					local clone = RS.Accessories[gadget.Name]:Clone()
					clone.Parent = player.Character

					warn(gadget.Name .. " is not a valid gadget module!")
				end
			end
		end
	end

	-- remove gadgets that were removed
	for gadgetName, module in pairs(ActiveGadgetModules[userId]) do
		if not newGadgets[gadgetName] then

			if typeof(module.Stop) == "function" then
				module.Stop(player) -- properly stop behavior
			end

			-- remove the accessory
			if player.Character:FindFirstChild(gadgetName) then
				player.Character[gadgetName]:Destroy()
			end

			ActiveGadgetModules[userId][gadgetName] = nil
		end
	end

	mainfunctions.CalculateHumanoidStats(player) -- recalculate stats after gadget changes, i use this for the speed and jump power
end

local playerscharging = {}

function inventory.Use(player, mousepos, released, position, rotation, buildname)-- this handles if the player used a tool and how it was used
	local id = player.UserId
	local equippedTool = _G.SessionData.equipped[id]
	local toolData = items[equippedTool]
	if not toolData then return end

	
	if toolData.Use == "Swing" then -- handles melee type tools

		
		local currentTime = tick() -- cooldown to attack
		if currentTime - (_G.SessionData.lastAttackTime[id] or 0) < toolData.Cooldown then return end
		_G.SessionData.lastAttackTime[id] = currentTime

		local char = player.Character
		if not char then return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local hum = char:FindFirstChild("Humanoid")
		if not hrp or not hum then return end

		RS.Events.Animate:FireAllClients(RS.Anims.Dagger,char,1,nil,false) -- play swing anim

		
		local hitbox = Instance.new("Part") -- creates a hitbox in front of the character
		hitbox.Size = Vector3.new(toolData.Reach, 15, toolData.Reach)
		hitbox.Position = hrp.Position + hrp.CFrame.LookVector * (toolData.Reach / 2)
		hitbox.Transparency = 1
		hitbox.CanCollide = false
		hitbox.Anchored = true
		hitbox.Parent = workspace
		hitbox.CFrame = CFrame.new(hitbox.Position, hrp.Position + hrp.CFrame.LookVector)

		local parts = workspace:GetPartsInPart(hitbox) -- checks for the collided parts
		local alreadyHit = {}

		for _, part in pairs(parts) do -- checks all the collided parts found

			
			if GlobalData.Pvp == true then -- PVP only damaging
				if part.Name == ("HumanoidRootPart") then
					local model = part:FindFirstAncestorWhichIsA("Model")

					if model and model.Parent == workspace.Players and model ~= player.Character and not alreadyHit[model] then
						local Humanoid = model:FindFirstChild("Humanoid")

						if Humanoid and Humanoid.Health > 0 then
							alreadyHit[model] = true

							local damage = toolData.Damage

							
							if mainfunctions.HasGadget(player,"Leather Gloves") then -- damage buff by gadgets
								damage *= 1.25
							end

							if mainfunctions.HasGadget(player,"Thorned Band") then
								damage *= 1.5
							end

							mainfunctions.Damage(model, player.Character, damage)
						end
					end
				end
			end

			
			local model = part:FindFirstAncestorWhichIsA("Model") -- damages assets

			if model and model ~= workspace and model:FindFirstChild("Health") then

				if part.Name == "Colission" then continue end

				if not alreadyHit[model] then
					mainfunctions.DamageAsset(model, player, toolData)
					alreadyHit[model] = true
				end
			end
		end

		
		task.delay(0.2, function() -- clear the hitbox
			hitbox:Destroy()
		end)


	elseif toolData.Use == "Heal" then

		
		local currentTime = tick() -- cooldown
		if currentTime - (_G.SessionData.lastAttackTime[id] or 0) < toolData.Cooldown then return end
		_G.SessionData.lastAttackTime[id] = currentTime

		
		inventory.RemoveItem(player, equippedTool, 1) -- remove the item

		
		if player.Character:FindFirstChild(equippedTool) then -- remove the tool model from the character's hand
			player.Character:FindFirstChild(equippedTool):Destroy()
		end

		
		player.Character.Humanoid.Health += toolData.Heal -- applies heal

		_G.SessionData.equipped[id] = nil -- removes the tool from the hand

		
		RS.Events.HotBar:FireClient(player, _G.SessionData.hotbar[id]) -- update UI


	elseif toolData.Use == "Food" then

		
		inventory.RemoveItem(player, equippedTool, 1) -- consumes the item

		if player.Character:FindFirstChild(equippedTool) then -- removes model from the hand
			player.Character:FindFirstChild(equippedTool):Destroy()
		end

		
		_G.SessionData.hunger[id] += items[equippedTool].Food -- adds to the hunger bar

		
		if items[equippedTool].Damage then -- for raw food (no use right now)
			player.Character.Humanoid.Health -= toolData.Damage
		end

		_G.SessionData.hunger[id] = math.clamp(_G.SessionData.hunger[id], 0, 100)

		
		_G.SessionData.equipped[id] = nil -- reset equipped tool
		RS.Events.HotBar:FireClient(player, _G.SessionData.hotbar[id])	 -- resets both UIs
		RS.Events.Hunger:FireClient(player, _G.SessionData.hunger[id])


	elseif toolData.Use == "Build" then

		
		if GlobalData.Build == false then  -- check if building is disabled globally
			RS.Events.Message:FireClient(player, "Building Is Disabled!", RS.Sounds.Error) 
			return 
		end

		
		local function isRotationValid(rot) -- assures 45° rotation
			return rot % 45 == 0
		end

		if not position or not rotation then return end
		if not isRotationValid(rotation) then return end -- returns if the rotation is not valid to prevent exploits or possible async
		if not builds[buildname] then return end

		local cost = builds[buildname].Items

		local inv = inventory.fillInventorySlots(_G.SessionData.inventory[id])
		local Hotbar = inventory.fillHotbarSlots(_G.SessionData.hotbar[id])

		
		if GlobalData.FreeBuild == false then -- checks for the materials

			for name, amount in pairs(cost) do
				local total = 0

				-- inventory count
				for _, entry in pairs(inv) do
					if typeof(entry) == "table" and entry.Name == name then
						total += entry.Ammount or 1
					end
				end

				-- hotbar count
				for _, entry in pairs(Hotbar) do
					if typeof(entry) == "table" and entry.Name == name then
						total += 1
					end
				end

				if total < amount then
					RS.Events.Message:FireClient(player, "Not enough materials to build", RS.Sounds.Error)
					return
				end
			end

			-- remove materials
			for name, amount in pairs(cost) do
				inventory.RemoveItem(player, name, amount)
			end
		end

		
		local part = RS.Assets.Builds[buildname]:Clone() -- creates the build
		part.Handle.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(rotation), 0)
		part.Handle.Anchored = true
		part.Name = buildname
		part.Parent = workspace.Builds

		
		if builds[buildname].Health then -- adds health to it
			local health = Instance.new("IntValue")
			health.Name = "Health"
			health.Value = builds[buildname].Health
			health.Parent = part

			
			health.Changed:Connect(function(value) -- handles if the build was destroyed
				if value <= 0 then
					part:Destroy()
				end
			end)
		end

		
		if builds[buildname].Interactable then -- checks if its interactable (useful for doors/chests, etc.)
			local module = require(script.Builds:FindFirstChild(buildname)) 

			task.spawn(function()
				module.Start(part) -- calls the module start
			end)
		end

		
		RS.Events.Inventory:FireClient(player, inventory.fillInventorySlots(_G.SessionData.inventory[id])) -- update UI
		RS.Events.HotBar:FireClient(player, _G.SessionData.hotbar[id])


	elseif toolData.Use == "Shovel" then -- shovels give you items when you click

		
		local currentTime = tick() -- cooldown
		if currentTime - (_G.SessionData.lastAttackTime[id] or 0) < toolData.Cooldown then return end
		_G.SessionData.lastAttackTime[id] = currentTime

		local char = player.Character
		if not char then return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local hum = char:FindFirstChild("Humanoid")
		if not hrp or not hum then return end

		
		if hum.FloorMaterial ~= (Enum.Material.Grass or Enum.Material.Mud) then -- only works on grass or mud (wouldnt make sense to have a shovel break rocks)
			RS.Events.Message:FireClient(player, "You need to be on grass or mud to dig!", RS.Sounds.Error) 
			return 
		end

		
		RS.Events.Animate:FireAllClients(RS.Anims.Shovel,char,1,nil,false) -- plays the anim

		for item, info in pairs(toolData.Drops) do -- gives the drops according to the chance
			if math.random(1, info.Chance) == 1 then
				inventory.AddItem(player, item, info.Ammount)
			end
		end

		
		RS.Events.Inventory:FireClient(player, inventory.fillInventorySlots(_G.SessionData.inventory[id])) -- update UI


	elseif toolData.Use == "Shoot" then

		
		if released then
			RS.Events.Animate:FireAllClients(nil, player.Character, nil, nil, false, "BowDragContinue") -- removing the drag anim
		end

		
		local currentTime = tick() -- cooldown
		if currentTime - (_G.SessionData.lastAttackTime[id] or 0) < toolData.Cooldown then return end
		_G.SessionData.lastAttackTime[id] = currentTime

		
		if not released then -- start charging
			playerscharging[id] = {StartTime = tick()} -- saves the time they started charging
			RS.Events.Animate:FireAllClients(RS.Anims.BowDragContinue, player.Character, nil, nil, false)
			return
		end

		
		RS.Events.Animate:FireAllClients(nil, player.Character, nil, nil, false, "BowDragContinue") -- stops the animation if shooting

		
		local success = inventory.RemoveItem(player, toolData.Ammo, 1) -- consumes ammo
		if success ~= true then return RS.Events.Message:FireClient(player, "No ammo!", RS.Sounds.Error) end -- returns if there isnt ammo

		
		local chargeInfo = playerscharging[id] -- calculates the charge to multiply damage
		local chargeTime = 0
		if chargeInfo then
			chargeTime = tick() - chargeInfo.StartTime
			playerscharging[id] = nil
		end

		local damageMultiplier = math.clamp(1 + chargeTime, 1, 3)
		local finalDamage = toolData.Damage * damageMultiplier

		local char = player.Character
		if not char then return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local arrow

		
		if toolData.AmmoPart then -- creates the projectile
			local arrowmodel = RS.Assets:FindFirstChild(toolData.AmmoPart, true):Clone()
			arrow = arrowmodel.Handle
			arrow.Anchored = true
			arrow.CanCollide = false
			arrow.CFrame = hrp.CFrame * CFrame.new(0, 1.5, -2)
			arrowmodel.Parent = workspace.Projectiles
		else
			arrow = Instance.new("Part")
			arrow.Size = Vector3.new(0.2, 0.2, 2)
			arrow.CFrame = hrp.CFrame * CFrame.new(0, 1.5, -2)
			arrow.Color = Color3.fromRGB(80, 80, 80)
			arrow.Material = Enum.Material.Wood
			arrow.CanCollide = false
			arrow.Anchored = true
			arrow.Parent = workspace.Projectiles
		end

		
		local hitbox = Instance.new("Part") -- creates the hitbox
		hitbox.Size = Vector3.new(toolData.HitboxSize, toolData.HitboxSize, toolData.HitboxSize)
		hitbox.Transparency = toolData.HitboxTransparency
		hitbox.Material = Enum.Material.ForceField
		hitbox.Shape = Enum.PartType.Ball
		if toolData.HitboxColor then
			hitbox.Color = toolData.HitboxColor
		end

		hitbox.CanCollide = false
		hitbox.Anchored = true
		hitbox.Parent = workspace.Projectiles

		
		local startPos = arrow.Position -- trajectory calculing
		local endPos = mousepos
		local distance = (endPos - startPos).Magnitude

		local baseArc = toolData.ArcHeight or 30 -- how much to arc the trajectory to look realistic
		local arcHeight

		if toolData.Arc then
			arcHeight = math.clamp(distance * 0.25, baseArc * 0.3, baseArc * 2)
		else
			arcHeight = 0
		end

		local midPos = (startPos + endPos) / 2 + Vector3.new(0, arcHeight, 0)

		local function quadBezier(t, p0, p1, p2) -- calculates the projectile path
			return (1 - t)^2 * p0 + 2*(1-t)*t*p1 + t^2*p2
		end

		local speed = toolData.Speed or 130
		local travelTime = distance / speed

		local progress = Instance.new("NumberValue")
		progress.Value = 0

		local tween = game:GetService("TweenService"):Create(progress, TweenInfo.new(travelTime, Enum.EasingStyle.Linear), {Value = 1})

		local lastPos = startPos
		local alreadyHit = {}

		local conn
		conn = progress:GetPropertyChangedSignal("Value"):Connect(function() -- everytime the arrow progresses, it updates the position

			local t = progress.Value
			local newPos = quadBezier(t, startPos, midPos, endPos)
			local direction = newPos - lastPos

			arrow.CFrame = CFrame.new(newPos, newPos + direction.Unit)
			hitbox.CFrame = arrow.CFrame

			local parts = workspace:GetPartsInPart(hitbox) -- checks the assets inside the hitbox

			for _, part in ipairs(parts) do
				local model = part:FindFirstAncestorWhichIsA("Model")

				if model and model ~= char and not alreadyHit[model] then
					alreadyHit[model] = true -- makes sure it hasnt hit already

					if GlobalData.Pvp == true then -- checks for the global pvp state
						if model.Parent == workspace.Players then
							local hum = model:FindFirstChild("Humanoid")
							if hum and hum.Health > 0 then
								mainfunctions.Damage(model, player.Character, finalDamage) -- deals the damage
							end
						end
					end

					mainfunctions.DamageAsset(model, player, toolData, finalDamage) -- deals damage to the assets
					break
				end
			end

			lastPos = newPos
		end)

		tween.Completed:Connect(function() -- removes the arrow and hitbox after the tween is done
			RS.Events.Inventory:FireClient(player, _G.SessionData.inventory[id])

			if arrow.Parent then arrow:Destroy() end
			if hitbox.Parent then hitbox:Destroy() end

			progress:Destroy()
			conn:Disconnect()
		end)

		tween:Play()


	elseif toolData.Use == "Javelin" then -- javelins can be held down to charge and shoot or click to hit

		if released then
			RS.Events.Animate:FireAllClients(nil, player.Character, nil, nil, false, "Javelin")
		end

		if not released then

			local chargeId = tick()

			playerscharging[id] = { -- creates the info of the charging state
				StartTime = tick(),
				Charging = true,
				ChargeId = chargeId
			}

			task.delay(0.4, function() -- checks if it was clicked or charged
				local info = playerscharging[id]

				if info and info.Charging and info.ChargeId == chargeId then
					RS.Events.Animate:FireAllClients(RS.Anims.Javelin, player.Character, nil, nil, false)
				end
			end)

			return
		end

		
		local chargeInfo = playerscharging[id] -- calculates the charge
		local chargeTime = 0

		if chargeInfo then
			chargeTime = tick() - chargeInfo.StartTime
			chargeInfo.Charging = false
			playerscharging[id] = nil
		end

		
		local currentTime = tick() -- cooldown
		if currentTime - (_G.SessionData.lastAttackTime[id] or 0) < toolData.Cooldown then return end
		_G.SessionData.lastAttackTime[id] = currentTime

		local char = player.Character
		if not char then return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		
		if chargeTime <= 0.4 then -- checks if it was a quick click to deal melee damage (same logic as swing)

			RS.Events.Animate:FireAllClients(RS.Anims.Dagger, char, 1, nil, false)

			local hitbox = Instance.new("Part")
			hitbox.Size = Vector3.new(toolData.Reach, 10, toolData.Reach)
			hitbox.Position = hrp.Position + hrp.CFrame.LookVector * (toolData.Reach/2)
			hitbox.Transparency = 1
			hitbox.CanCollide = false
			hitbox.Anchored = true
			hitbox.Parent = workspace

			local alreadyHit = {}

			for _, part in pairs(workspace:GetPartsInPart(hitbox)) do

				-- pvp
				if GlobalData.Pvp == true then
					if part.Name == "HumanoidRootPart" then

						local model = part:FindFirstAncestorWhichIsA("Model")

						if model and model.Parent == workspace.Players and model ~= player.Character and not alreadyHit[model] then
							local Humanoid = model:FindFirstChild("Humanoid")

							if Humanoid and Humanoid.Health > 0 then
								alreadyHit[model] = true
								mainfunctions.Damage(model, player.Character, toolData.Damage)
							end
						end
					end
				end

				-- asset damage
				local model = part:FindFirstAncestorWhichIsA("Model")

				if model and model ~= workspace and model:FindFirstChild("Health") then

					if part.Name == "Colission" then continue end

					if not alreadyHit[model] then
						mainfunctions.DamageAsset(model, player, toolData)
						alreadyHit[model] = true
					end
				end
			end

			task.delay(0.2,function()
				hitbox:Destroy()
			end)

			return
		end

		
		local spear = RS.Replicate:FindFirstChild(toolData.Ammo):Clone() -- creates the clone in case the player charged the spear (same logic as the bow)
		local part = spear.Handle

		part.Anchored = true
		part.CanCollide = false
		part.CFrame = hrp.CFrame * CFrame.new(0,1.5,-2)

		spear.Parent = workspace.Projectiles

		
		local hitbox = Instance.new("Part")
		hitbox.Size = Vector3.new(toolData.HitboxSize, toolData.HitboxSize, toolData.HitboxSize)
		hitbox.Transparency = 1
		hitbox.Shape = Enum.PartType.Ball
		hitbox.CanCollide = false
		hitbox.Anchored = true
		hitbox.Parent = workspace.Projectiles

		local startPos = part.Position
		local endPos = mousepos

		local direction = (endPos - startPos).Unit
		local distance = (endPos - startPos).Magnitude

		local speed = toolData.Speed or 150
		local travelTime = distance / speed

		local progress = Instance.new("NumberValue")
		progress.Value = 0

		local tween = game:GetService("TweenService"):Create(
			progress,
			TweenInfo.new(travelTime, Enum.EasingStyle.Linear),
			{Value = 1}
		)

		local alreadyHit = {}

		local conn
		conn = progress:GetPropertyChangedSignal("Value"):Connect(function()

			local pos = startPos:Lerp(endPos, progress.Value)

			part.CFrame = CFrame.new(pos, pos + direction)
			hitbox.CFrame = part.CFrame

			local parts = workspace:GetPartsInPart(hitbox)

			for _, p in ipairs(parts) do
				local model = p:FindFirstAncestorWhichIsA("Model")

				if model and model ~= char and not alreadyHit[model] then
					alreadyHit[model] = true

					if model:FindFirstChild("Humanoid") and model:FindFirstChild("Humanoid").Health > 0 and model.Parent == workspace.Players and GlobalData.Pvp == true then
						mainfunctions.Damage(model, char, toolData.Damage)
					elseif model:FindFirstChild("Health") and model.Parent ~= workspace.Players then
						mainfunctions.DamageAsset(model, player, toolData, toolData.Damage)
					end
				end
			end
		end)

		tween.Completed:Connect(function()

			if spear then spear:Destroy() end
			if hitbox then hitbox:Destroy() end

			progress:Destroy()
			conn:Disconnect()
		end)

		tween:Play()
	end
end

function inventory.Craft(player, recipeName) -- handles crafting items
	local id = player.UserId

	local recipe = Recipes[recipeName]
	if not recipe then return end

	if GlobalData.Craft == false then --detexts if crafting is disabled
		RS.Events.Message:FireClient(player, "Crafting Is Disabled!", RS.Sounds.Error) 
		return 
	end

	-- ensures that the player has unlocked their previous tier first
	if _G.SessionData.Tier[id] < (recipe.Tier - 1) then 
		RS.Events.Message:FireClient(player, "Unlock Tier " .. (recipe.Tier - 1) .. " First!", RS.Sounds.Error) 
		return 
	end

	local inv = inventory.fillInventorySlots(_G.SessionData.inventory[id])
	local Hotbar = inventory.fillHotbarSlots(_G.SessionData.hotbar[id])

	-- checks if the player actually has all required ingredients
	for name, amount in pairs(recipe.Recipe) do
		local total = 0

		for _, entry in pairs(inv) do
			if typeof(entry) == "table" and entry.Name == name then
				total += entry.Ammount or 1
			end
		end

		for _, entry in pairs(Hotbar) do
			if typeof(entry) == "table" and entry.Name == name then
				total += 1
			end
		end

		if total < amount then
			RS.Events.Message:FireClient(player, "Missing ingredients", RS.Sounds.Error)
			return
		end
	end

	-- attempts to give the player the crafted item
	local success = inventory.AddItem(player, recipeName, recipe.Ammount)

	if success then -- if it works, it removes the ingredients

		-- handles the tier progression from crafting higher tier items
		if recipe.Tier and recipe.Tier > _G.SessionData.Tier[id] then

			if not _G.SessionData.PlayerTieredItems[id][recipe.Tier] then
				_G.SessionData.PlayerTieredItems[id][recipe.Tier] = 0
			end

			_G.SessionData.PlayerTieredItems[id][recipe.Tier] += 1

			-- requires crafting 3 items of that same tier to unlock it
			if _G.SessionData.PlayerTieredItems[id][recipe.Tier] >= 3 then

				_G.SessionData.Tier[id] = recipe.Tier

				-- updates the global infection tier if player surpasses it
				if _G.SessionData.Tier[id] > GlobalData.Tier then

					GlobalData.Tier = recipe.Tier

					RS.Events.Message:FireAllClients("World Tier Has Increased!", RS.Sounds.Upgradeworld, Color3.new(0.376471, 0, 0.74902))
					RS.Events.Tier:FireAllClients(GlobalData.Tier, true)
					RS.Events.Tier:FireClient(player,_G.SessionData.Tier[id], false)
				else
					-- if the player is lower tier than the world, it updates the player only
					RS.Events.Message:FireClient(player,"Player Tier Has Increased!", RS.Sounds.PlayerUpgrade, Color3.new(0, 0.572549, 0.74902))
					RS.Events.Tier:FireClient(player, _G.SessionData.Tier[id], false)
				end
			else
				-- tells the player how many crafts of the same tier are left to reach next tier
				RS.Events.Message:FireClient(player,"Craft " .. (3 - _G.SessionData.PlayerTieredItems[id][recipe.Tier]) .. " more items to reach this tier!", RS.Sounds.Ding, Color3.new(0, 0.74902, 0.34902))
			end
		end

		-- removes the ingredients AFTER a successful craft
		for name, amount in pairs(recipe.Recipe) do
			if not items[name].Tool then -- prevents consuming tools for more realism like cutting boards
				inventory.RemoveItem(player, name, amount)
			end
		end

		RS.Events.Inventory:FireClient(player, inventory.fillInventorySlots(_G.SessionData.inventory[id]))
		RS.Events.HotBar:FireClient(player, _G.SessionData.hotbar[id])
	else
		RS.Events.Message:FireClient(player, "Inventory is full!", RS.Sounds.Error)
	end
end

function inventory.HotBar(player, itemName) -- checks and updates the current item in hand
	local id = player.UserId

	local found = false

	-- cancels the bow charging animation if youre switching items
	RS.Events.Animate:FireAllClients(nil, player.Character, nil, nil, false, "BowDragContinue")

	-- checks if the item actually exists in hotbar
	if itemName ~= nil then
		for _, tool in pairs(_G.SessionData.hotbar[id]) do
			if typeof(tool) == "table" and tool.Name == itemName then
				found = true
				break
			end
		end
	else
		found = true
	end

	if _G.SessionData.equipped[id] == itemName or not found then return end

	-- removes previous equipped tool
	if _G.SessionData.equipped[id] then
		local old = player.Character:FindFirstChild(_G.SessionData.equipped[id])
		if old then old:Destroy() end
	end

	-- enables build mode if the item is a build tool (buildinghammer)
	if itemName and items[itemName].Use == "Build" then
		RS.Events.Build:FireClient(player, items[itemName])
	else
		RS.Events.Build:FireClient(player, nil)
	end

	_G.SessionData.equipped[id] = itemName
	if not itemName then return end

	-- attaches the tool model to the player character
	local clone = RS.Accessories:FindFirstChild(itemName)
	if clone then
		clone:Clone().Parent = player.Character
	end
end

function inventory.Drop(player, index, typestr) -- handles dropping items
	local id = player.UserId

	local inv = inventory.fillInventorySlots(_G.SessionData.inventory[id])
	local Hotbar = inventory.fillInventorySlots(_G.SessionData.hotbar[id])
	local Gadgets = inventory.fillInventorySlots(_G.SessionData.gadgets[id])

	local function getTable(typeStr) -- fixes the container to drop from
		if typeStr == "Inventory" then
			return inv
		elseif typeStr == "Hotbar" then
			return Hotbar
		elseif typeStr == "Gadgets" then
			return Gadgets
		end
	end

	local tabletouse = getTable(typestr)

	index = tonumber(index)

	local entry = tabletouse and tabletouse[index] or inv[index]


	if not entry or not entry.Name or items[entry.Name].NoDrop then  -- prevents dropping invalid or restricted items
		RS.Events.Message:FireClient(player, "Cant drop item!", RS.Sounds.Error) 
		return 
	end

	if GlobalData.Drop == false then -- prevents dropping if the drops are disabled
		RS.Events.Message:FireClient(player, "Dropping Is Disabled!", RS.Sounds.Error) 
		return 
	end

	-- spawns the physical drop in front of the player
	local clone = RS.Assets:FindFirstChild(entry.Name, true):Clone()
	clone.Parent = LooseFolder
	clone.Handle.CFrame = CFrame.new(player.Character.HumanoidRootPart.Position + player.Character.HumanoidRootPart.CFrame.LookVector * 3)

	inventory.RemoveItem(player, entry.Name, 1)

	-- destroy it after some time to make sure there arent many assets arround
	task.delay(60, function()
		if clone and clone.Parent then
			clone:Destroy()
		end
	end)

	-- sync UI
	RS.Events.Inventory:FireClient(player, inventory.fillInventorySlots(_G.SessionData.inventory[id]))
	RS.Events.HotBar:FireClient(player, inventory.fillHotbarSlots(_G.SessionData.hotbar[id]))
	RS.Events.Gadget:FireClient(player, inventory.fillGadgetSlots(_G.SessionData.gadgets[id]))
end

return inventory
