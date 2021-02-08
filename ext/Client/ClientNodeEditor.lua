class "ClientNodeEditor"

require('__shared/Config');
require('__shared/NodeCollection')

function ClientNodeEditor:__init()
	-- caching values for drawing performance
	self.player = nil
	self.waypoints = {}
	self.playerPos = nil
	self.textColor = Vec4(1,1,1,1)
	self.sphereColors = {
		Vec4(1,0,0,0.25),
		Vec4(0,1,0,0.25),
		Vec4(0,0,1,0.25),
		Vec4(1,1,0,0.25),
		Vec4(1,0,1,0.25),
		Vec4(0,1,1,0.25),
		Vec4(1,0.5,0,0.25),
		Vec4(1,0,0.5,0.25),
		Vec4(0,0.5,1,0.25),
		Vec4(1,0.5,0.5,0.25),
	}
	self.lineColors = {
		Vec4(1,0,0,1),
		Vec4(0,1,0,1),
		Vec4(0,0,1,1),
		Vec4(1,1,0,1),
		Vec4(1,0,1,1),
		Vec4(0,1,1,1),
		Vec4(1,0.5,0,1),
		Vec4(1,0,0.5,1),
		Vec4(0,0.5,1,1),
		Vec4(1,0.5,0.5,1),
	}

	self.CommoRose = {
		Pressed = false,
		Active = false,
		LastAction = ''
	}

	self.lastTraceSearchAreaPos = nil
	self.lastTraceSearchAreaSize = nil
	self.lastTraceStart = nil
	self.lastTraceEnd = nil

	self:RegisterEvents()
end

function ClientNodeEditor:RegisterEvents()
	NetEvents:Subscribe('NodeEditor:SetLastTraceSearchArea', self, self._onSetLastTraceSearchArea)
	NetEvents:Subscribe('NodeEditor:ClientInit', self, self._onClientInit)

	Events:Subscribe('UpdateManager:Update', self, self._onUpdateManagerUpdate)
	Events:Subscribe('UI:DrawHud', self, self._onUIDrawHud)
	Events:Subscribe('Player:Respawn', self, self._onPlayerRespawn)
	Events:Subscribe('Player:Deleted', self, self._onPlayerDeleted)
	Events:Subscribe('Level:Destroy', self, self._onLevelDestroy)

	Hooks:Install('UI:PushScreen', 100, self, self._onUIPushScreen)
	Hooks:Install('UI:InputConceptEvent', 100, self, self._onUIInputConceptEvent)

	Console:Register('GetNodes', 'Remove selected waypoints', self, self._onGetNodes)
	Console:Register('Remove', 'Remove selected waypoints', self, self._onRemove)
	Console:Register('Merge', 'Merge selected waypoints', self, self._onMerge)
	Console:Register('Split', 'Split selected waypoints', self, self._onSplit)
	Console:Register('ClearSelection', 'Clear selected waypoints', self, self._onClearSelection)

end


function ClientNodeEditor:_onGetNodes(args)
	NetEvents:Send('NodeEditor:GetNodes')
	return true
end

function ClientNodeEditor:_onRemove(args)
	g_NodeCollection:Remove()
	self.waypoints = g_NodeCollection:Get()
	print(Language:I18N('Success'))
	return true
end

function ClientNodeEditor:_onMerge(args)
	local result, message = g_NodeCollection:MergeSelection()
	self.waypoints = g_NodeCollection:Get()
	print(Language:I18N(message))
	return result
end

function ClientNodeEditor:_onSplit(args)
	local result, message = g_NodeCollection:SplitSelection()
	self.waypoints = g_NodeCollection:Get()
	print(Language:I18N(message))
	return result
end

function ClientNodeEditor:_onClearSelection(args)
	g_NodeCollection:ClearSelection()
	print(Language:I18N('Success'))
	return true
end

function ClientNodeEditor:_onSetLastTraceSearchArea(data)
	self.lastTraceSearchAreaPos = data[1]
	self.lastTraceSearchAreaSize = data[2]
end

function ClientNodeEditor:_onClientInit()
	g_NodeCollection:RegisterEvents()
	self.player = PlayerManager:GetLocalPlayer()
	self.waypoints = g_NodeCollection:Get()
end

function ClientNodeEditor:_onPlayerRespawn(args)
	if (Config.debugTracePaths) then
		NetEvents:Send('NodeEditor:GetNodes')
	end
end

function ClientNodeEditor:_onPlayerDeleted(args)
	g_NodeCollection:Clear()
	self.player = nil
	self.waypoints = {}
end

function ClientNodeEditor:_onLevelDestroy()
	g_NodeCollection:Clear()
	self.player = nil
	self.waypoints = {}
end

function ClientNodeEditor:_onUpdateManagerUpdate(delta, pass)

	if (not Config.debugTracePaths) then
		return
	end

	-- Only do math on presimulation UpdatePass
	if pass ~= UpdatePass.UpdatePass_PreSim then
		return
	end

	-- doing this here and not in UI:DrawHud prevents a memory leak that crashes you in under a minute
	if (self.player ~= nil and self.player.alive and self.player.soldier ~= nil and self.player.soldier.alive and self.player.soldier.worldTransform ~= nil) then
		self.playerPos = self.player.soldier.worldTransform.trans
    	for i=1, #self.waypoints do
    		if (self.waypoints[i] ~= nil) then
    			-- precalc the distances for less overhead on the hud draw
    			self.waypoints[i].Distance = self.playerPos:Distance(self.waypoints[i].Position)
    		end
    	end
    end
end

function ClientNodeEditor:_onUIPushScreen(hook, screen, priority, parentGraph, stateNodeGuid)

	if (Config.debugTracePaths and screen ~= nil and UIScreenAsset(screen).name == 'UI/Flow/Screen/CommRoseScreen') then
    	self.CommoRose.Active = self.CommoRose.Pressed
    	self:_onCommoRoseAction('Show')
    	hook:Return() -- don't actually display the UI
    end
	hook:Pass(screen, priority, parentGraph, stateNodeGuid)
end

function ClientNodeEditor:_onUIInputConceptEvent(hook, eventType, action)

	if (not Config.debugTracePaths) then
		hook:Pass(eventType, action)
	end
	
	-- was pressed quickly, quick-select
    if (action == UIInputAction.UIInputAction_CommoRose 
    	and eventType == UIInputActionEventType.UIInputActionEventType_Released
    	and self.CommoRose.Pressed and not self.CommoRose.Active) then
		self.CommoRose.Pressed = (eventType == UIInputActionEventType.UIInputActionEventType_Pressed)
		self:_onCommoRoseAction('Select')
	end

	-- was pressed long enough to trigger, then released
    if (action == UIInputAction.UIInputAction_CommoRose 
    	and eventType == UIInputActionEventType.UIInputActionEventType_Released
    	and self.CommoRose.Pressed and self.CommoRose.Active) then
		self.CommoRose.Pressed = (eventType == UIInputActionEventType.UIInputActionEventType_Pressed)
		self:_onCommoRoseAction('Hide')
	end

    if (action == UIInputAction.UIInputAction_CommoRose) then
		self.CommoRose.Pressed = (eventType == UIInputActionEventType.UIInputActionEventType_Pressed)
	end
    hook:Pass(eventType, action)
end

function ClientNodeEditor:_onCommoRoseAction(action, hit)
	print('CommoRoseAction: '..tostring(action))

	if (action == 'Show') then
		NetEvents:Send('UI_Request_CommoRose_Show')
		return
	end

	if (action == 'Hide') then
		NetEvents:Send('UI_Request_CommoRose_Hide')
		return
	end

	if (action == 'Select') then

		local hit = self:Raycast()
		if (hit == nil) then
			return
		end
	    local hitPoint = g_NodeCollection:Find(hit.position)

		-- nothing found at hit location, try a raytracing check
		if (hitPoint == nil and self.player ~= nil and self.player ~= nil) then
			local playerCamPos = self.player.soldier.worldTransform.trans + self.player.input.authoritativeCameraPosition
			hitPoint = g_NodeCollection:FindAlongTrace(playerCamPos, hit.position)
			self.lastTraceStart = playerCamPos
			self.lastTraceEnd = hit.position
		end

		-- still no results, let's create one
		if (hitPoint == nil) then
			--local waypoint = g_NodeCollection:Create(hit.position)
			--NetEvents:Send('NodeEditor:Add', waypoint) -- send it to everyone
			--g_NodeCollection:Select(waypoint)
			return
		else -- we found one, let's toggle its selected state

			local isSelected = g_NodeCollection:IsSelected(hitPoint)

			if (isSelected) then 
				g_NodeCollection:Deselect(hitPoint)
				return
			else
				g_NodeCollection:Select(hitPoint)
				return
			end
		end
	end
end

function ClientNodeEditor:_onUIDrawHud()

	if (not Config.debugTracePaths) then
		return
	end

	DebugRenderer:DrawText2D(20, 20,
		'CommoRose.Pressed: '..tostring(self.CommoRose.Pressed).."\nCommoRose.Active: "..tostring(self.CommoRose.Active).."\nCommoRose.LastAction: "..tostring(self.CommoRose.LastAction),
		self.textColor, 1)

	if (Config.debugSelectionRaytraces) then
		if (self.lastTraceStart ~= nil and self.lastTraceEnd ~= nil) then
			DebugRenderer:DrawLine(self.lastTraceStart, self.lastTraceEnd, self.textColor, self.textColor)
		end
		if (self.lastTraceSearchAreaPos ~= nil and self.lastTraceSearchAreaSize ~= nil) then
			DebugRenderer:DrawSphere(self.lastTraceSearchAreaPos, self.lastTraceSearchAreaSize, self.sphereColors[9], false, false)
		end
	end

	for i=1, #self.waypoints do
		local waypoint = self.waypoints[i]
		if (waypoint ~= nil) then

			local isSelected = g_NodeCollection:IsSelected(waypoint)

			if (waypoint.Distance ~= nil and waypoint.Distance < Config.waypointRange) then
				DebugRenderer:DrawSphere(waypoint.Position, 0.05, self.sphereColors[waypoint.PathIndex], false, false)
			end

			if (waypoint.Distance ~= nil and waypoint.Distance < Config.waypointRange and isSelected) then
				DebugRenderer:DrawSphere(waypoint.Position, 0.07, self.sphereColors[waypoint.PathIndex], false, false)
				DebugRenderer:DrawLine(waypoint.Position, waypoint.Position + (Vec3.up * 0.7), self.lineColors[waypoint.PathIndex], self.lineColors[waypoint.PathIndex])
			end

			if (waypoint.Distance ~= nil and waypoint.Distance < Config.lineRange and Config.drawWaypointLines) then
				-- try to find a previous node and draw a line to it
				if (waypoint.Previous ~= nil) then
					DebugRenderer:DrawLine(waypoint.Previous.Position, waypoint.Position, self.lineColors[waypoint.PathIndex], self.lineColors[waypoint.PathIndex])
				end
			end

			if (waypoint.Distance ~= nil and waypoint.Distance < Config.textRange and Config.drawWaypointIDs) then
				if (isSelected) then
					-- don't try to precalc this value like with the distance, another memory leak crash awaits you
					local screenPos = ClientUtils:WorldToScreen(waypoint.Position + (Vec3.up * 0.7))
					if (screenPos ~= nil) then

						local previousNode = "None\n"
						local nextNode = "None\n"
						if (waypoint.Previous ~= nil) then
							previousNode = waypoint.Previous.ID
						end
						if (waypoint.Next ~= nil) then
							nextNode = waypoint.Next.ID
						end

						local text = 'Custom ID: '..tostring(waypoint.ID).."\n"
						text = text..'Custom Index: '..tostring(waypoint.Index).."\n"
						text = text..'Database ID: '..tostring(waypoint.OriginalID).."\n"
						text = text..'PathIndex: '..tostring(waypoint.PathIndex).."\n"
						text = text..'PointIndex: '..tostring(waypoint.PointIndex).."\n"
						text = text..'Previous Node: '..tostring(waypoint.Previous)..' -> '..previousNode.."\n"
						text = text..'Next Node: '..tostring(waypoint.Next)..' -> '..nextNode.."\n"
						text = text..'PointIndex: '..tostring(waypoint.PointIndex).."\n"
						text = text..'InputVar: '..tostring(g_Utilities:getEnumName(EntryInputActionEnum, waypoint.InputVar))..' ('..tostring(waypoint.InputVar)..')'
						DebugRenderer:DrawText2D(screenPos.x, screenPos.y, text, self.textColor, 1.2)
					end
					screenPos = nil
				else
					-- don't try to precalc this value like with the distance, another memory leak crash awaits you
					local screenPos = ClientUtils:WorldToScreen(waypoint.Position + (Vec3.up * 0.05))
					if (screenPos ~= nil) then
						DebugRenderer:DrawText2D(screenPos.x, screenPos.y, tostring(waypoint.ID).."\n"..tostring(g_Utilities:getEnumName(EntryInputActionEnum, waypoint.InputVar)), self.textColor, 1)
						screenPos = nil
					end
				end
			end
		end
	end
end

-- ##################################################
-- ##################################################
-- ###################################### DEBUG STUFF


function ClientNodeEditor:_onLevelLoaded(player)

	local TheBigList = {}

	EntityManager:TraverseAllEntities(function(entity)
		if (entity.typeInfo ~= nil) then
			if (TheBigList[entity.typeInfo.name] == nil) then
				TheBigList[entity.typeInfo.name] = 1
			else
				TheBigList[entity.typeInfo.name] = TheBigList[entity.typeInfo.name] + 1
			end
		end
	end)

	for k,v in pairs(TheBigList) do
		print(k..': '..tostring(v))
	end

	print('ClientUIGraphEntity Callbacks Registered: '..self:_registerCallbacks('ClientUIGraphEntity'))
	print('ClientSoldierEntity Callbacks Registered: '..self:_registerCallbacks('ClientSoldierEntity'))
end

-- stolen't https://github.com/EmulatorNexus/VEXT-Samples/blob/80cddf7864a2cdcaccb9efa810e65fae1baeac78/no-headglitch-raycast/ext/Client/__init__.lua
function ClientNodeEditor:Raycast()
	if self.player == nil then
		return
	end

	-- We get the camera transform, from which we will start the raycast. We get the direction from the forward vector. Camera transform
	-- is inverted, so we have to invert this vector.
	local transform = ClientUtils:GetCameraTransform()
	local direction = Vec3(-transform.forward.x, -transform.forward.y, -transform.forward.z)

	if transform.trans == Vec3(0,0,0) then
		return
	end

	local castStart = transform.trans

	-- We get the raycast end transform with the calculated direction and the max distance.
	local castEnd = Vec3(
		transform.trans.x + (direction.x * 100),
		transform.trans.y + (direction.y * 100),
		transform.trans.z + (direction.z * 100))

	-- Perform raycast, returns a RayCastHit object.
	local raycastHit = RaycastManager:Raycast(castStart, castEnd, RayCastFlags.DontCheckWater | RayCastFlags.DontCheckCharacter | RayCastFlags.DontCheckRagdoll | RayCastFlags.CheckDetailMesh)

	return raycastHit	
end

function ClientNodeEditor:_registerCallbacks(entityType)
	local messageIterator = EntityManager:GetIterator(entityType)
	local messageEntity = messageIterator:Next()
	local total = 0
	
	while messageEntity do
		messageEntity = Entity(messageEntity)
		messageEntity:RegisterEventCallback(function(ent, entityEvent)
			if (ent.data ~= nil) then
				print(tostring(entityType)..': '..tostring(ent.data.instanceGuid)..' -> '..tostring(ent.data.name))
			end
        end)
        total = total+1
		
		messageEntity = messageIterator:Next()
	end
	return total
end

if (g_ClientNodeEditor == nil) then
	g_ClientNodeEditor = ClientNodeEditor()
end

return g_ClientNodeEditor