--!native
--!strict
--// ported to lua by nebulimity

local MapGenerator = {}

MapGenerator.LoadingPercent = 0
MapGenerator.RandomSeed = os.time()

local AssetCache = require(script.Parent.AssetCache)
local MapSize = Vector2.new(18, 18)
local MapWidth = MapSize.X
local MapHeight = MapSize.Y

local RoomSpacing = 45.056

local EachRooms = {}

local RoomType = {
	ROOM1 = 0,
	ROOM2 = 1,
	ROOM2C = 2,
	ROOM3 = 3,
	ROOM4 = 4
}

local function GetZone(y: number)
	return math.min(math.floor((MapHeight - y) / MapHeight * 3), 3 - 1)
end

local function IsInBounds(arr, d1)
	return d1 >= 0 and d1 < #arr[0] + 1
end

local function WrapAngle360(angle: number)
	return (angle % 360 + 360) % 360
end

local function SizedArray(size: number, defaultValue)
	local arr = {}
	for i = 0, size - 1 do
		arr[i] = defaultValue
	end
	return arr
end

local function Sized2DArray(size1: number, size2: number, defaultValue)
	local arr = {}
	for i = 0, size1 - 1 do
		arr[i] = {}
		for j = 0, size2 - 1 do
			arr[i][j] = defaultValue
		end
	end

	return arr
end

local function drawLine(startPos: Vector3, endPos: Vector3, color, lifetime)
	local line = Instance.new("Part")
	line.Anchored = true
	line.CanCollide = false
	line.Size = Vector3.new(0.2, 0.2, (startPos - endPos).Magnitude)
	line.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -line.Size.Z / 2)
	line.Color = color or Color3.new(1, 1, 1)
	line.Parent = workspace

	game:GetService("Debris"):AddItem(line, lifetime)

	return line
end

local function SetRoom(MapRoom, room_name, room_type, pos: number, min_pos: number, max_pos: number) -- place a room without overwriting others
	if max_pos < min_pos then
		warn("Can't place " .. room_name)
		return false
	end

	local looped = false
	local can_place = true

	while MapRoom[room_type][pos] ~= "" do
		pos += 1
		if pos > max_pos then
			if not looped then
				pos = min_pos + 1
				looped = true
			else
				can_place = false
				break
			end
		end
	end

	if can_place then
		MapRoom[room_type][pos] = room_name
		return true
	else
		warn("couldn't place " .. room_name)
		return false
	end
end

local function Instantiate(room)
	local go = room:Clone()
	go.Parent = workspace.Map

	local Rooms = script.Rooms:Clone()
	Rooms.Parent = go

	local RoomTemplates = script.RoomTemplates:Clone()
	RoomTemplates.Parent = go

	table.insert(EachRooms, go)
	return go
end

local function CreateRoom(zone, room_type: number, x: number, y: number, z: number, room_name, rng)
	local room: Model, DisableOverlapCheck = AssetCache.LoadRoom(room_name, room_type, zone, rng)

	local go: any = Instantiate(room)
	go:PivotTo(CFrame.new(x * RoomSpacing, y * RoomSpacing, z * RoomSpacing))

	go.RoomTemplates.DisableOverlapCheck.Value = DisableOverlapCheck
	go.RoomTemplates.Shape.Value = room_type
	go.RoomTemplates.RoomName.Value = room_name

	go.Rooms.Zone.Value = zone
	go.Rooms.X.Value = x * RoomSpacing
	go.Rooms.Y.Value = y * RoomSpacing
	go.Rooms.Z.Value = z * RoomSpacing
	go.Rooms.OriginalX.Value = x
	go.Rooms.OriginalY.Value = y
	go.Rooms.OriginalZ.Value = z

	return go
end

local function CreateDoor(zone, x: number, y: number, z: number, angle, big)	
	local door: Model = AssetCache.LoadDoor(zone, big)
	local go = door:Clone()
	go.Parent = workspace.Interactables

	go:PivotTo(CFrame.new(x, y, z))

	local modelCFrame = go:GetPivot()
	go:PivotTo(CFrame.new(modelCFrame.X, modelCFrame.Y, modelCFrame.Z) * CFrame.Angles(0, math.rad(angle), 0))

	return go
end

local function CalculateRoomExtents(r)
	if r.RoomTemplates.DisableOverlapCheck.Value then
		return
	end

	-- shrink the extents slightly - we don't care if the overlap is smaller than the thickness of the walls
	local shrinkAmount = 0.05

	-- convert from the rooms local space to world space
	local minVector = Vector3.new(r.RoomTemplates.MinX.Value, r.RoomTemplates.MinY.Value, r.RoomTemplates.MinZ.Value)
	local minWorld: Vector3 = r.CFrame:PointToWorldSpace(minVector)

	r.RoomTemplates.MinX.Value = minWorld.X + shrinkAmount + r.Rooms.X.Value
	r.RoomTemplates.MinY.Value = minWorld.Y + shrinkAmount
	r.RoomTemplates.MinZ.Value = minWorld.Z + shrinkAmount + r.Rooms.Z.Value

	-- convert from the rooms local space to world space
	local maxVector = Vector3.new(r.RoomTemplates.MaxX.Value, r.RoomTemplates.MaxY.Value, r.RoomTemplates.MaxZ.Value)
	local maxWorld = r.CFrame:PointToWorldSpace(maxVector)

	r.RoomTemplates.MaxX.Value = maxWorld.X - shrinkAmount + r.Rooms.X.Value
	r.RoomTemplates.MaxY.Value = maxWorld.Y - shrinkAmount
	r.RoomTemplates.MaxZ.Value = maxWorld.Z - shrinkAmount + r.Rooms.Z.Value

	if r.RoomTemplates.MinX.Value > r.RoomTemplates.MaxX.Value then
		r.RoomTemplates.MinX.Value, r.RoomTemplates.MaxX.Value = r.RoomTemplates.MaxX.Value, r.RoomTemplates.MinX.Value
	end
	if r.RoomTemplates.MinZ.Value > r.RoomTemplates.MaxZ.Value then
		r.RoomTemplates.MinZ.Value, r.RoomTemplates.MaxZ.Value = r.RoomTemplates.MaxZ.Value, r.RoomTemplates.MinZ.Value
	end
end

local function CheckRoomOverlap(r1: any, r2: any)
	if r1.RoomTemplates.MaxX.Value <= r2.RoomTemplates.MinX.Value or r1.RoomTemplates.MaxY.Value <= r2.RoomTemplates.MinY.Value or r1.RoomTemplates.MaxZ.Value <= r2.RoomTemplates.MinZ.Value then
		return false
	end
	if r1.RoomTemplates.MinX.Value >= r2.RoomTemplates.MaxX.Value or r1.RoomTemplates.MinY.Value >= r2.RoomTemplates.MaxY.Value or r1.RoomTemplates.MinZ.Value >= r2.RoomTemplates.MaxZ.Value then
		return false
	end

	return true
end

local function PreventRoomOverlap(r: any) --this doesnt actually work yet
	if r.RoomTemplates.DisableOverlapCheck.Value then
		return
	end

	local r2 = nil
	local r3 = nil
	local IsIntersecting = false

	-- Just skip it when it would try to check for the checkpoints
	if r.RoomTemplates.RoomName.Value == "checkpoint1" or r.RoomTemplates.RoomName.Value == "checkpoint2" or r.RoomTemplates.RoomName.Value == "start" then
		return true
	end

	-- First, check if the room is actually intersecting at all
	for i, r2: any in EachRooms do
		if r2 ~= r and not r2.RoomTemplates.DisableOverlapCheck.Value then
			if CheckRoomOverlap(r, r2) then
				IsIntersecting = true
				break
			end
		end
	end

	-- If not, then simple return it as true
	if not IsIntersecting then
		return true
	end

	-- Room is intersecting: first, check if the given room is a ROOM2, so we could potentially just turn it by 180 degrees
	IsIntersecting = false

	local x = r.Rooms.OriginalX.Value
	local y = r.Rooms.OriginalZ.Value

	if r.RoomTemplates.Shape.Value == RoomType.ROOM2 then
		-- Room is a ROOM2, let's check if turning it 180 degrees fixes the overlapping issue
		r.Rooms.Angle.Value += 180

		local modelCFrame = r:GetPivot()
		r:PivotTo(CFrame.new(modelCFrame.X, modelCFrame.Y, modelCFrame.Z) * CFrame.Angles(0, math.rad(r.Rooms.Angle.Value), 0))
		CalculateRoomExtents(r)

		for i, r2: any in EachRooms do
			if r2 ~= r and not r2.RoomTemplates.DisableOverlapCheck.Value then
				if CheckRoomOverlap(r, r2) then
					-- didn't work -> rotate the room back and move to the next step
					IsIntersecting = true
					r.Rooms.Angle.Value -= 180
					local modelCFrame = r:GetPivot()
					r:PivotTo(CFrame.new(modelCFrame.X, modelCFrame.Y, modelCFrame.Z) * CFrame.Angles(0, math.rad(r.Rooms.Angle.Value), 0))
					CalculateRoomExtents(r)
					break
				end
			end
		end
	else
		IsIntersecting = true
	end

	-- room is ROOM2 and was able to be turned by 180 degrees
	if not IsIntersecting then
		print("ROOM2 turning successful! " .. r.RoomTemplates.RoomName.Value)
		return true
	end

	-- Room is either not a ROOM2 or the ROOM2 is still intersecting, now trying to swap the room with another of the same type
	IsIntersecting = true
	local temp2 = 0
	local x2 = 0
	local y2 = 0
	local rot = 0
	local rot2 = 0

	for i, r2: any in EachRooms do
		if r2 ~= r and not r2.RoomTemplates.DisableOverlapCheck.Value then
			if r.RoomTemplates.Shape.Value == r2.RoomTemplates.Shape.Value and r.RoomTemplates.Zone.Value == r2.RoomTemplates.Zone.Value and r2.RoomTemplates.RoomName.Value ~= "checkpoint1" and r2.RoomTemplates.RoomName.Value ~= "checkpoint2" and r2.RoomTemplates.RoomName.Value ~= "start" then
				x = r.Rooms.OriginalX.Value
				y = r.Rooms.OriginalZ.Value
				rot = r.Rooms.Angle.Value

				x2 = r2.Rooms.OriginalX.Value
				y2 = r2.Rooms.OriginalZ.Value
				rot2 = r2.Rooms.Angle.Value

				IsIntersecting = false

				r.Rooms.X.Value = x2 * RoomSpacing
				r.Rooms.Z.Value = y2 * RoomSpacing
				r.Rooms.Angle.Value = rot2

				local modelCFrame = r:GetPivot()
				r:PivotTo(CFrame.new(r.Rooms.X.Value, r.Rooms.Y.Value, r.Rooms.Z.Value))
				r:PivotTo(CFrame.new(modelCFrame.X, modelCFrame.Y, modelCFrame.Z) * CFrame.Angles(0, math.rad(r.Rooms.Angle.Value), 0))
				CalculateRoomExtents(r)

				r2.Rooms.X.Value = x * RoomSpacing
				r2.Rooms.Z.Value = y * RoomSpacing
				r2.Rooms.Angle.Value = rot

				local modelCFrame = r2:GetPivot()
				r:PivotTo(CFrame.new(r2.Rooms.X.Value, r2.Rooms.Y.Value, r2.Rooms.Z.Value))
				r:PivotTo(CFrame.new(modelCFrame.X, modelCFrame.Y, modelCFrame.Z) * CFrame.Angles(0, math.rad(r2.Rooms.Angle.Value), 0))
				CalculateRoomExtents(r2)

				-- make sure neither room overlaps with anything after the swap
				for i, r3: any in EachRooms do
					if not r3.RoomTemplates.DisableOverlapCheck.Value then
						if r3 ~= r then
							if CheckRoomOverlap(r, r3) then
								IsIntersecting = true
								break
							end
						end
						if r3 ~= r2 then
							if CheckRoomOverlap(r2, r3) then
								IsIntersecting = true
								break
							end
						end
					end
				end

				-- Either the original room or the "reposition" room is intersecting, reset the position of each room to their original one
				if IsIntersecting then
					r.Rooms.X.Value = x * RoomSpacing
					r.Rooms.Z.Value = y * RoomSpacing
					r.Rooms.Angle.Value = rot

					local modelCFrame = r:GetPivot()
					r:PivotTo(CFrame.new(r.Rooms.X.Value, r.Rooms.Y.Value, r.Rooms.Z.Value))
					r:PivotTo(CFrame.new(modelCFrame.X, modelCFrame.Y, modelCFrame.Z) * CFrame.Angles(0, math.rad(r.Rooms.Angle.Value), 0))
					CalculateRoomExtents(r)

					r2.Rooms.X.Value = x2 * RoomSpacing
					r2.Rooms.Z.Value = y2 * RoomSpacing
					r2.Rooms.Angle.Value = rot2

					local modelCFrame = r2:GetPivot()
					r:PivotTo(CFrame.new(r2.Rooms.X.Value, r2.Rooms.Y.Value, r2.Rooms.Z.Value))
					r:PivotTo(CFrame.new(modelCFrame.X, modelCFrame.Y, modelCFrame.Z) * CFrame.Angles(0, math.rad(r2.Rooms.Angle.Value), 0))
					CalculateRoomExtents(r2)

					IsIntersecting = false
				end
			end
		end
	end

	-- room was able to the placed in a different spot
	if not IsIntersecting then
		print("Room re-placing successful! " .. r.RoomTemplates.RoomName.Value)
		return true
	end

	print("Couldn't fix room overlapping issue for room ".. r.RoomTemplates.RoomName.Value)
end

function MapGenerator.CreateMap(CustomSeed: number)
	if CustomSeed then
		MapGenerator.RandomSeed = CustomSeed
	end
	
	print("Generating a map using the seed " .. MapGenerator.RandomSeed)

	local Transition = {}
	Transition[0] = math.floor(MapHeight * (2 / 3)) + 1
	Transition[1] = math.floor(MapHeight * (1 / 3)) + 1

	local x, y, temp = 0, 0, 0
	local i, x2, y2 = 0, 0, 0

	local zone = 0

	local rng = Random.new(MapGenerator.RandomSeed)

	local MapName = Sized2DArray(MapWidth, MapHeight, "")
	local MapTemp = Sized2DArray(MapWidth + 1, MapHeight + 1, 0)
	local MapRoomID = SizedArray(RoomType.ROOM4 + 1, 0)

	local x = math.floor(MapWidth / 2)
	local y = MapHeight - 2 -- rng:NextInteger(3, 5)

	for i = y, MapHeight - 1 do
		MapTemp[x][i] = 1
	end

	repeat
		local width = rng:NextInteger(math.floor(MapWidth * 0.6), math.floor(MapWidth * 0.85))

		if x > MapWidth * 0.6 then
			width = -width
		elseif x > MapWidth * 0.4 then
			x = math.floor(x - width / 2)
		end

		-- make sure the hallway doesn't go outside the array
		if x + width > MapWidth - 3 then
			--x = -width + MapWidth - 4

			width = MapWidth - 3 - x
		elseif x + width < 2 then
			--x  = 3 - width

			width = -x + 2
		end

		x = math.min(x, x + width)
		width = math.abs(width)

		for i = x, x + width do
			MapTemp[math.min(i, MapWidth)][y] = 1
		end

		local height = rng:NextInteger(3, 4)

		if y - height < 1 then
			height = y - 1
		end

		local yhallways = rng:NextInteger(4, 5)

		if GetZone(y - height) ~= GetZone(y - height + 1) then
			height = height - 1
		end

		for i = 1, yhallways do
			local x2 = math.max(math.min(rng:NextInteger(x, x + width - 1), MapWidth - 2), 2)
			local tempheight = 0

			while MapTemp[x2][y - 1] >= 1 or MapTemp[x2 - 1][y - 1] >= 1 or MapTemp[x2 + 1][y - 1] >= 1 do
				x2 = x2 + 1
			end

			if x2 < x + width then
				if i == 1 then
					tempheight = height
					if rng:NextInteger(0, 2) == 1 then
						x2 = x
					else
						x2 = x + width
					end
				else
					tempheight = rng:NextInteger(1, height)
				end

				for y2 = y - tempheight, y do
					if GetZone(y2) ~= GetZone(y2 + 1) then -- a room leading from zone to another
						MapTemp[x2][y2] = 255
					else
						MapTemp[x2][y2] = 1
					end
				end

				if tempheight == height then
					temp = x2
				end
			end
		end

		x = temp
		y = y - height
	until y < 2

	for k = 0, MapHeight - 1 do
		for j = 0, MapWidth - 1 do
			local pos = Vector3.new(j, 0, k)

			if MapTemp[j][k] >= 1 then
				drawLine(pos, pos + Vector3.new(0, 1, 0), Color3.fromRGB(255, 0, 0), math.huge)
			end
		end
	end

	local ZoneAmount = 3
	local Room1Amount = SizedArray(ZoneAmount, 0)
	local Room2Amount = SizedArray(ZoneAmount, 0)
	local Room2CAmount = SizedArray(ZoneAmount, 0)
	local Room3Amount = SizedArray(ZoneAmount, 0)
	local Room4Amount = SizedArray(ZoneAmount, 0)

	-- count the amount of rooms
	for y = 1, MapHeight - 1 do
		local zone = GetZone(y)

		for x = 1, MapWidth - 1 do
			if MapTemp[x][y] > 0 then
				temp = math.min(MapTemp[x + 1][y], 1) + math.min(MapTemp[x - 1][y], 1)
				temp = temp + math.min(MapTemp[x][y + 1], 1) + math.min(MapTemp[x][y - 1], 1)

				if MapTemp[x][y] < 255 then
					MapTemp[x][y] = temp
				end

				if MapTemp[x][y] == 1 then
					Room1Amount[zone] += 1
				elseif MapTemp[x][y] == 2 then
					if math.min(MapTemp[x + 1][y], 1) + math.min(MapTemp[x - 1][y], 1) == 2 then
						Room2Amount[zone] += 1
					elseif math.min(MapTemp[x][y + 1], 1) + math.min(MapTemp[x][y - 1], 1) == 2 then
						Room2Amount[zone] += 1
					else
						Room2CAmount[zone] += 1
					end
				elseif MapTemp[x][y] == 3 then
					Room3Amount[zone] += 1
				elseif MapTemp[x][y] == 4 then
					Room4Amount[zone] += 1
				end
			end
		end
	end

	local y_min, y_max, x_min, x_max

	-- force more room1s (if needed)
	for i = 0, 2 do
		-- need more rooms if there are less than 5 of them
		temp = -Room1Amount[i] + 5
		if temp > 0 then
			if i == 2 then y_min = 1 else y_min = Transition[i] end
			if i == 0 then y_max = MapHeight - 2 else y_max = Transition[i - 1] - 1 end
			x_min = 1
			x_max = MapWidth - 2

			for y = y_max, y_max do
				for x = x_min, x_max do
					if MapTemp[x][y] == 0 then
						if (math.min(MapTemp[x + 1][y], 1) + math.min(MapTemp[x - 1][y], 1) + math.min(MapTemp[x][y + 1], 1) + math.min(MapTemp[x][y - 1], 1)) == 1 then
							-- if rng:NextInteger(0, 4) == 1 then

							local x2 = 0
							local y2 = 0

							if MapTemp[x + 1][y] then
								x2 = x + 1
								y2 = y
							elseif MapTemp[x - 1][y] then
								x2 = x - 1
								y2 = y
							elseif MapTemp[x][y + 1] then
								x2 = x
								y2 = y + 1
							elseif MapTemp[x][y - 1] then
								x2 = x
								y2 = y - 1
							end

							local placed = false

							if MapTemp[x2][y2] > 1 and MapTemp[x2][y2] < 4 and (y < y_max or y2 < y or i == 0) then
								if MapTemp[x2][y2] == 2 then
									if math.min(MapTemp[x2 + 1][y2], 1) + math.min(MapTemp[x2 - 1][y2], 1) == 2 then
										Room2Amount[i] -= 1
										Room3Amount[i] += 1

										placed = true
									elseif math.min(MapTemp[x2][y2 + 1], 1) + math.min(MapTemp[x2][y2 - 1], 1) == 2 then
										Room2Amount[i] -= 1
										Room3Amount[i] += 1

										placed = true
									end
								elseif MapTemp[x2][y2] == 3 then
									Room3Amount[i] -= 1
									Room4Amount[i] += 1

									placed = true
								end

								if placed then
									MapTemp[x2][y2] += 1
									MapTemp[x][y] = 1
									Room1Amount[i] += 1

									temp -= 1
								end
							end
						end
					end

					if temp == 0 then
						break
					end
				end

				if temp == 0 then
					break
				end
			end
		end
	end

	-- force more room4s and room2Cs
	for i = 0, 2 do
		local zone = 1
		local temp2 = 0

		if i == 2 then y_min = 2 else y_min = Transition[i] end
		if i == 0 then y_max = MapHeight - 2 else y_max = Transition[i - 1] - 2 end
		x_min = 1
		x_min = MapWidth - 2
		
		if Room4Amount[i] < 1 then -- we want at least 1 ROOM4
			print("forcing a ROOM4 into zone " .. i)
			temp = 0

			for y = y_min, y_max do
				for x = x_min, x_max do
					if MapTemp[x][y] == 3 then
						if MapTemp[x + 1][y] > 0 or MapTemp[x + 1][y + 1] > 0 or MapTemp[x + 1][y - 1] > 0 or MapTemp[x + 2][y] > 0 or x == x_max then
							MapTemp[x + 1][y] = 1
							temp = 1
						elseif MapTemp[x - 1][y] > 0 or MapTemp[x - 1][y + 1] > 0 or MapTemp[x - 1][y - 1] > 0 or MapTemp[x - 2][y] > 0 or x == x_min then
							MapTemp[x - 1][y] = 1
							temp = 1
						elseif MapTemp[x][y + 1] > 0 or MapTemp[x + 1][y + 1] > 0 or MapTemp[x - 1][y + 1] > 0 or MapTemp[x][y + 2] > 0 or i == 0 and y == y_max then
							MapTemp[x][y + 1] = 1
							temp = 1
						elseif MapTemp[x][y - 1] > 0 or MapTemp[x + 1][y - 1] > 0 or MapTemp[x - 1][y - 1] > 0 or MapTemp[x][y - 2] > 0 or i < 2 and y == y_min then
							MapTemp[x][y-1] = 1
							temp = 1
						end

						if temp == 1 then
							MapTemp[x][y] = 4 -- turn this room into a ROOM4
							print("ROOM4 forced into slot (" .. x .. ", " .. y .. ")")
							Room4Amount[i] += 1
							Room3Amount[i] -= 1
							Room1Amount[i] += 1
						end
					end

					if temp == 1 then
						break
					end
				end

				if temp == 1 then
					break
				end
			end

			if temp == 0 then
				warn("Couldn't place ROOM4 in zone " .. i)
			end
		end

		if Room2CAmount[i] < 1 then -- we want at least 1 ROOM2C
			print("forcing a ROOM2C into zone " .. i)
			temp = 0

			for y = y_max, y_min, -1 do
				for x = x_min, x_max do
					if MapTemp[x][y] == 1 then
						if MapTemp[x - 1][y] > 0 then -- see if adding some rooms is possible
							if MapTemp[x + 1][y - 1] + MapTemp[x + 1][y + 1] + MapTemp[x + 2][y] == 0 and x < x_max then
								if MapTemp[x + 1][y - 2] + MapTemp[x + 2][y - 1] + MapTemp[x + 1][y - 1] == 0 and (y > y_min or i == 2) then
									MapTemp[x][y] = 2
									MapTemp[x + 1][y] = 2
									print("ROOM2C forced into slot (" .. x + 1 .. ", " .. y .. ")")
									MapTemp[x + 1][y - 1] = 1
									temp = 1
								elseif MapTemp[x + 1][y + 2] + MapTemp[x + 2][y + 1] + MapTemp[x + 1][y + 1] == 0 and (y < y_max or i > 0) then
									MapTemp[x][y] = 2
									MapTemp[x + 1][y] = 2
									print("ROOM2C forced into slot (" .. x + 1 .. ", " .. y .. ")")
									MapTemp[x + 1][y + 1] = 1
									temp = 1
								end
							end
						elseif MapTemp[x + 1][y] > 0 then
							if MapTemp[x - 1][y - 1] + MapTemp[x - 1][y + 1] + MapTemp[x - 2][y] == 0 and x > x_min then
								if MapTemp[x - 1][y - 2] + MapTemp[x - 2][y - 1] + MapTemp[x - 1][y - 1] == 0 and (y > y_min or i == 2) then
									MapTemp[x][y] = 2
									MapTemp[x - 1][y] = 2
									print("ROOM2C forced into slot (" .. x - 1 .. ", " .. y .. ")")
									MapTemp[x - 1][y - 1] = 1
									temp = 1
								elseif MapTemp[x - 1][y + 2] + MapTemp[x - 2][y + 1] + MapTemp[x - 1][y + 1] == 0 and (y < y_max or i > 0) then
									MapTemp[x][y] = 2
									MapTemp[x - 1][y] = 2
									print("ROOM2C forced into slot (" .. x - 1 .. ", " .. y .. ")")
									MapTemp[x - 1][y + 1] = 1
									temp = 1
								end
							end
						elseif MapTemp[x][y - 1] > 0 then
							if MapTemp[x - 1][y + 1] + MapTemp[x + 1][y + 1] + MapTemp[x][y + 2] == 0 and (y < y_max or i > 0) then
								if MapTemp[x - 2][y + 1] + MapTemp[x - 1][y + 2] + MapTemp[x - 1][y + 1] == 0 and x > x_min then
									MapTemp[x][y] = 2
									MapTemp[x][y + 1] = 2
									print("ROOM2C forced into slot (" .. x .. ", " .. y + 1 .. ")")
									MapTemp[x - 1][y + 1] = 1
									temp = 1
								elseif MapTemp[x + 2][y + 1] + MapTemp[x + 1][y + 2] + MapTemp[x + 1][y + 1] == 0 and x < x_max then
									MapTemp[x][y] = 2
									MapTemp[x][y + 1] = 2
									print("ROOM2C forced into slot (" .. x .. ", " .. y + 1 .. ")")
									MapTemp[x + 1][y + 1] = 1
									temp = 1
								end
							end
						elseif MapTemp[x][y + 1] > 0 then
							if MapTemp[x - 1][y - 1] + MapTemp[x + 1][y - 1] + MapTemp[x][y - 2] == 0 and (y > y_min or i == 2) then
								if MapTemp[x - 2][y - 1] + MapTemp[x - 1][y - 2] + MapTemp[x - 1][y - 1] == 0 and x > x_min then
									MapTemp[x][y] = 2
									MapTemp[x][y - 1] = 2
									print("ROOM2C forced into slot (" .. x .. ", " .. y - 1 .. ")")
									MapTemp[x - 1][y - 1] = 1
									temp = 1
								elseif MapTemp[x + 2][y - 1] + MapTemp[x + 1][y - 2] + MapTemp[x + 1][y - 1] == 0 and x < x_max then
									MapTemp[x][y] = 2
									MapTemp[x][y - 1] = 2
									print("ROOM2C forced into slot (" .. x .. ", " .. y - 1 .. ")")
									MapTemp[x + 1][y - 1] = 1
									temp = 1
								end
							end
						end

						if temp == 1 then
							Room2CAmount[i] += 1
							Room2Amount[i] += 1
						end
					end
					if temp == 1 then
						break
					end
				end
				if temp == 1 then
					break
				end
			end
			if temp == 0 then
				warn("Couldn't place ROOM2C in zone " .. i)
			end
		end
	end

	local MaxRooms = math.floor(55 * MapWidth / 20)
	MaxRooms = math.max(MaxRooms, Room1Amount[0] + Room1Amount[1] + Room1Amount[2] + 1)
	MaxRooms = math.max(MaxRooms, Room2Amount[0] + Room2Amount[1] + Room2Amount[2] + 1)
	MaxRooms = math.max(MaxRooms, Room2CAmount[0] + Room2CAmount[1] + Room2CAmount[2] + 1)
	MaxRooms = math.max(MaxRooms, Room3Amount[0] + Room3Amount[1] + Room3Amount[2] + 1)
	MaxRooms = math.max(MaxRooms, Room4Amount[0] + Room4Amount[1] + Room4Amount[2] + 1)
	local MapRoom = Sized2DArray(RoomType.ROOM4 + 1, MaxRooms, "")

	-- zone 1
	local min_pos = 1
	local max_pos = Room1Amount[0] - 1

	MapRoom[RoomType.ROOM1][0] = "start"
	SetRoom(MapRoom, "roompj", RoomType.ROOM1, math.floor(0.1 * Room1Amount[0]), min_pos, max_pos)
	SetRoom(MapRoom, "914", RoomType.ROOM1, math.floor(0.3 * Room1Amount[0]), min_pos, max_pos)
	SetRoom(MapRoom, "room1archive", RoomType.ROOM1, math.floor(0.5 * Room1Amount[0]), min_pos, max_pos)
	SetRoom(MapRoom, "room205", RoomType.ROOM1, math.floor(0.6 * Room1Amount[0]), min_pos, max_pos)

	MapRoom[RoomType.ROOM2][0] = "lockroom"

	min_pos = 1
	max_pos = Room2Amount[0] - 1

	MapRoom[RoomType.ROOM2][0] = "room2closets"
	SetRoom(MapRoom, "room2testroom2", RoomType.ROOM2, math.floor(0.1 * Room2Amount[0]), min_pos, max_pos)
	SetRoom(MapRoom, "room2scps", RoomType.ROOM2, math.floor(0.2 * Room2Amount[0]), min_pos, max_pos)
	SetRoom(MapRoom, "room2storage", RoomType.ROOM2, math.floor(0.3 * Room2Amount[0]), min_pos, max_pos)
	SetRoom(MapRoom, "room2gw_b", RoomType.ROOM2, math.floor(0.4 * Room2Amount[0]), min_pos, max_pos)
	SetRoom(MapRoom, "room2sl", RoomType.ROOM2, math.floor(0.5 * Room2Amount[0]), min_pos, max_pos)
	SetRoom(MapRoom, "room012", RoomType.ROOM2, math.floor(0.55 * Room2Amount[0]), min_pos, max_pos)
	SetRoom(MapRoom, "room2scps2", RoomType.ROOM2, math.floor(0.6 * Room2Amount[0]), min_pos, max_pos)
	SetRoom(MapRoom, "room1123", RoomType.ROOM2, math.floor(0.7 * Room2Amount[0]), min_pos, max_pos)
	SetRoom(MapRoom, "room2elevator", RoomType.ROOM2, math.floor(0.85 * Room2Amount[0]), min_pos, max_pos)

	MapRoom[RoomType.ROOM3][math.floor(rng:NextInteger(20, 80) / 100 * Room3Amount[0])] = "room3storage"
	MapRoom[RoomType.ROOM2C][math.floor(0.5 * Room2CAmount[0])] = "room1162"
	MapRoom[RoomType.ROOM4][math.floor(0.3 * Room4Amount[0])] = "room4info"

	-- zone 2
	min_pos = Room1Amount[0]
	max_pos = Room1Amount[0] + Room1Amount[1] - 1

	SetRoom(MapRoom, "room079", RoomType.ROOM1, Room1Amount[0] + math.floor(0.15 * Room1Amount[1]), min_pos, max_pos)
	SetRoom(MapRoom, "room106", RoomType.ROOM1, Room1Amount[0] + math.floor(0.3 * Room1Amount[1]), min_pos, max_pos)
	SetRoom(MapRoom, "008", RoomType.ROOM1, Room1Amount[0] + math.floor(0.4 * Room1Amount[1]), min_pos, max_pos)
	SetRoom(MapRoom, "room035", RoomType.ROOM1, Room1Amount[0] + math.floor(0.5 * Room1Amount[1]), min_pos, max_pos)
	SetRoom(MapRoom, "coffin", RoomType.ROOM1, Room1Amount[0] + math.floor(0.7 * Room1Amount[1]), min_pos, max_pos)

	min_pos = Room2Amount[0]
	max_pos = Room2Amount[0] + Room2Amount[1] - 1

	MapRoom[RoomType.ROOM2][Room2Amount[0] + math.floor(0.1 * Room2Amount[1])] = "room2nuke"
	SetRoom(MapRoom, "room2tunnel", RoomType.ROOM2, Room2Amount[0] + math.floor(0.25 * Room2Amount[1]), min_pos, max_pos)
	SetRoom(MapRoom, "room049", RoomType.ROOM2, Room2Amount[0] + math.floor(0.4 * Room2Amount[1]), min_pos, max_pos)
	SetRoom(MapRoom, "room2shaft", RoomType.ROOM2, Room2Amount[0] + math.floor(0.6 * Room2Amount[1]), min_pos, max_pos)
	SetRoom(MapRoom, "testroom", RoomType.ROOM2, Room2Amount[0] + math.floor(0.7 * Room2Amount[1]), min_pos, max_pos)
	SetRoom(MapRoom, "room2servers", RoomType.ROOM2, Room2Amount[0] + math.floor(0.9 * Room2Amount[1]), min_pos, max_pos)

	MapRoom[RoomType.ROOM3][Room3Amount[0] + math.floor(0.3 * Room3Amount[1])] = "room513"
	MapRoom[RoomType.ROOM3][Room3Amount[0] + math.floor(0.6 * Room3Amount[1])] = "room966"

	MapRoom[RoomType.ROOM2C][Room2Amount[0] + math.floor(0.5 * Room2Amount[1])] = "room2cpit"

	-- zone 3
	MapRoom[RoomType.ROOM1][Room1Amount[0] + Room1Amount[1] + Room1Amount[2] - 2] = "exit1"
	MapRoom[RoomType.ROOM1][Room1Amount[0] + Room1Amount[1] + Room1Amount[2] - 1] = "gateaentrance"
	MapRoom[RoomType.ROOM1][Room1Amount[0] + Room1Amount[1]] = "room1lifts"

	min_pos = Room2Amount[0] + Room2Amount[1]
	max_pos = Room2Amount[0] + Room2Amount[1] + Room2Amount[2] - 1

	MapRoom[RoomType.ROOM2][min_pos + math.floor(0.1 * Room2Amount[2])] = "room2poffices"
	SetRoom(MapRoom, "room2cafeteria", RoomType.ROOM2, min_pos + math.floor(0.2 * Room2Amount[2]), min_pos, max_pos)
	--SetRoom(MapRoom, "room2toilets", RoomType.ROOM2, min_pos + math.floor(0.25 * Room2Amount[2]), min_pos, max_pos) -- force room2toilets spawn
	SetRoom(MapRoom, "room2sroom", RoomType.ROOM2, min_pos + math.floor(0.3 * Room2Amount[2]), min_pos, max_pos)
	SetRoom(MapRoom, "room2servers2", RoomType.ROOM2, min_pos + math.floor(0.4 * Room2Amount[2]), min_pos, max_pos)
	SetRoom(MapRoom, "room2offices", RoomType.ROOM2, min_pos + math.floor(0.45 * Room2Amount[2]), min_pos, max_pos)
	SetRoom(MapRoom, "room2offices4", RoomType.ROOM2, min_pos + math.floor(0.5 * Room2Amount[2]), min_pos, max_pos)
	SetRoom(MapRoom, "room860", RoomType.ROOM2, min_pos + math.floor(0.6 * Room2Amount[2]), min_pos, max_pos)
	SetRoom(MapRoom, "medibay", RoomType.ROOM2, min_pos + math.floor(0.7 * Room2Amount[2]), min_pos, max_pos)
	SetRoom(MapRoom, "room2poffices2", RoomType.ROOM2, min_pos + math.floor(0.8 * Room2Amount[2]), min_pos, max_pos)
	SetRoom(MapRoom, "room2offices2", RoomType.ROOM2, min_pos + math.floor(0.8 * Room2Amount[2]), min_pos, max_pos)

	MapRoom[RoomType.ROOM2C][Room2CAmount[0] + Room2CAmount[1]] = "room2ccont"
	MapRoom[RoomType.ROOM2C][Room2CAmount[0] + Room2CAmount[1] + 1] = "lockroom2"

	MapRoom[RoomType.ROOM3][Room3Amount[0] + Room3Amount[1] + math.floor(0.3 * Room3Amount[2])] = "room3servers"
	MapRoom[RoomType.ROOM3][Room3Amount[0] + Room3Amount[1] + math.floor(0.7 * Room3Amount[2])] = "room3servers2"
	-- MapRoom[RoomType.ROOM3][Room3Amount[0] + Room3Amount[1]] = "room3gw"
	MapRoom[RoomType.ROOM3][Room3Amount[0] + Room3Amount[1] + math.floor(0.5 * Room3Amount[2])] = "room3offices"

	-- creating a map

	temp = 0
	local spacing = RoomSpacing

	local Debug = Sized2DArray(MapWidth, MapHeight, {})

	for y = MapHeight - 1, 1, -1 do
		-- zone = GetZone(y)

		if y < MapHeight / 3 + 1 then
			zone = 3
		elseif y < MapHeight * (2 / 3) then
			zone = 2
		else
			zone = 1
		end

		for x = 1, MapWidth - 2 do
			if MapTemp[x][y] == 255 then
				if y > MapHeight / 2 then -- zone = 2
					local r = CreateRoom(zone, RoomType.ROOM2, x, 0, y, "checkpoint1", rng)
					local modelCFrame = r:GetPivot()

					r.Rooms.Angle.Value = 180

					r:PivotTo(CFrame.new(modelCFrame.X, modelCFrame.Y, modelCFrame.Z) * CFrame.Angles(0, math.rad(r.Rooms.Angle.Value), 0))
				else
					local r = CreateRoom(zone, RoomType.ROOM2, x, 0, y, "checkpoint2", rng)
					local modelCFrame = r:GetPivot()

					r.Rooms.Angle.Value = 180

					r:PivotTo(CFrame.new(modelCFrame.X, modelCFrame.Y, modelCFrame.Z) * CFrame.Angles(0, math.rad(r.Rooms.Angle.Value), 0))
				end
			elseif MapTemp[x][y] > 0 then
				temp = math.min(MapTemp[x + 1][y], 1) + math.min(MapTemp[x - 1][y], 1) + math.min(MapTemp[x][y + 1], 1) + math.min(MapTemp[x][y - 1], 1)

				if temp == 1 then -- number of rooms in adjacent squares
					if MapRoomID[RoomType.ROOM1] < MaxRooms and MapName[x][y] == "" then
						if MapRoom[RoomType.ROOM1][MapRoomID[RoomType.ROOM1]] ~= "" then
							MapName[x][y] = MapRoom[RoomType.ROOM1][MapRoomID[RoomType.ROOM1]]
						end
					end

					local r = CreateRoom(zone, RoomType.ROOM1, x, 0, y, MapName[x][y], rng)
					local modelCFrame = r:GetPivot()

					r.Rooms.Angle.Value = 0

					if MapTemp[x][y + 1] > 0 then
						r.Rooms.Angle.Value = 0 --180
					elseif MapTemp[x - 1][y] > 0 then
						r.Rooms.Angle.Value = 270 --270
					elseif MapTemp[x + 1][y] > 0 then
						r.Rooms.Angle.Value = 90 --90
					else
						r.Rooms.Angle.Value = 180 --0
					end

					r:PivotTo(CFrame.new(modelCFrame.X, modelCFrame.Y, modelCFrame.Z) * CFrame.Angles(0, math.rad(r.Rooms.Angle.Value), 0))
					--r:PivotTo(r:GetPivot() * CFrame.Angles(0, math.rad(180), 0))
					--r.Rooms.Angle.Value += 180
					MapRoomID[RoomType.ROOM1] += 1
				elseif temp == 2 then
					if MapTemp[x - 1][y] > 0 and MapTemp[x + 1][y] > 0 then
						if MapRoomID[RoomType.ROOM2] < MaxRooms and MapName[x][y] == "" then
							if MapRoom[RoomType.ROOM2][MapRoomID[RoomType.ROOM2]] ~= "" then
								MapName[x][y] = MapRoom[RoomType.ROOM2][MapRoomID[RoomType.ROOM2]]
							end
						end

						local r = CreateRoom(zone, RoomType.ROOM2, x, 0, y, MapName[x][y], rng)
						local modelCFrame = r:GetPivot()

						r.Rooms.Angle.Value = 0

						if rng:NextInteger(0, 2) == 1 then
							r.Rooms.Angle.Value = 90
						else
							r.Rooms.Angle.Value = 270
						end

						r:PivotTo(CFrame.new(modelCFrame.X, modelCFrame.Y, modelCFrame.Z) * CFrame.Angles(0, math.rad(r.Rooms.Angle.Value), 0))
						MapRoomID[RoomType.ROOM2] += 1
					elseif MapTemp[x][y - 1] > 0 and MapTemp[x][y + 1] > 0 then
						if MapRoomID[RoomType.ROOM2] < MaxRooms and MapName[x][y] == "" then
							if MapRoom[RoomType.ROOM2][MapRoomID[RoomType.ROOM2]] ~= "" then
								MapName[x][y] = MapRoom[RoomType.ROOM2][MapRoomID[RoomType.ROOM2]]
							end
						end

						local r = CreateRoom(zone, RoomType.ROOM2, x, 0, y, MapName[x][y], rng)
						local modelCFrame = r:GetPivot()

						r.Rooms.Angle.Value = 0

						if rng:NextInteger(0, 2) == 1 then
							r.Rooms.Angle.Value = 180
						else
							r.Rooms.Angle.Value = 0
						end

						r:PivotTo(CFrame.new(modelCFrame.X, modelCFrame.Y, modelCFrame.Z) * CFrame.Angles(0, math.rad(r.Rooms.Angle.Value), 0))
						MapRoomID[RoomType.ROOM2] += 1
					else
						if MapRoomID[RoomType.ROOM2C] < MaxRooms and MapName[x][y] == "" then
							if MapRoom[RoomType.ROOM2C][MapRoomID[RoomType.ROOM2C]] ~= "" then
								MapName[x][y] = MapRoom[RoomType.ROOM2C][MapRoomID[RoomType.ROOM2C]]
							end
						end

						local r = CreateRoom(zone, RoomType.ROOM2C, x, 0, y, MapName[x][y], rng)
						local modelCFrame = r:GetPivot()

						r.Rooms.Angle.Value = 0

						if MapTemp[x - 1][y] > 0 and MapTemp[x][y + 1] > 0 then
							r.Rooms.Angle.Value = 270 --180
						elseif MapTemp[x + 1][y] > 0 and MapTemp[x][y + 1] > 0 then
							r.Rooms.Angle.Value = 0 --90
						elseif MapTemp[x - 1][y] > 0 and MapTemp[x][y - 1] > 0 then
							r.Rooms.Angle.Value = 180 --270
						else
							r.Rooms.Angle.Value = 90 --0
						end

						r:PivotTo(CFrame.new(modelCFrame.X, modelCFrame.Y, modelCFrame.Z) * CFrame.Angles(0, math.rad(r.Rooms.Angle.Value), 0))
						MapRoomID[RoomType.ROOM2C] += 1
					end
				elseif temp == 3 then
					if MapRoomID[RoomType.ROOM3] < MaxRooms and MapName[x][y] == "" then
						if MapRoom[RoomType.ROOM3][MapRoomID[RoomType.ROOM3]] ~= "" then
							MapName[x][y] = MapRoom[RoomType.ROOM3][MapRoomID[RoomType.ROOM3]]
						end
					end

					local r = CreateRoom(zone, RoomType.ROOM3, x, 0, y, MapName[x][y], rng)
					local modelCFrame = r:GetPivot()

					r.Rooms.Angle.Value = 0

					if MapTemp[x][y - 1] <= 0 then
						r.Rooms.Angle.Value = 0 --180
					elseif MapTemp[x - 1][y] <= 0 then
						r.Rooms.Angle.Value = 90 --90
					elseif MapTemp[x + 1][y] <= 0 then
						r.Rooms.Angle.Value = 270 --270
					else
						r.Rooms.Angle.Value = 180 --0
					end

					r:PivotTo(CFrame.new(modelCFrame.X, modelCFrame.Y, modelCFrame.Z) * CFrame.Angles(0, math.rad(r.Rooms.Angle.Value), 0))
					MapRoomID[RoomType.ROOM3] += 1
				elseif temp == 4 then
					if MapRoomID[RoomType.ROOM4] < MaxRooms and MapName[x][y] == "" then
						if MapRoom[RoomType.ROOM4][MapRoomID[RoomType.ROOM4]] ~= "" then
							MapName[x][y] = MapRoom[RoomType.ROOM4][MapRoomID[RoomType.ROOM4]]
						end
					end

					local r = CreateRoom(zone, RoomType.ROOM4, x, 0, y, MapName[x][y], rng)
					local modelCFrame = r:GetPivot()

					r.Rooms.Angle.Value = 0

					r:PivotTo(CFrame.new(modelCFrame.X, modelCFrame.Y, modelCFrame.Z) * CFrame.Angles(0, math.rad(r.Rooms.Angle.Value), 0))
					MapRoomID[RoomType.ROOM4] += 1
				end
			end
		end
	end

	for i, r in EachRooms do
		PreventRoomOverlap(r)
	end

	local ShouldSpawnDoor = false

	for y = MapHeight, 0, -1 do
		if y < Transition[1] - 1 then
			zone = 3
		elseif y >= Transition[1] - 1 and y < Transition[0] - 1 then
			zone = 2
		else
			zone = 1
		end

		for x = MapWidth, 0, -1 do
			if MapTemp[x][y] > 0 then
				if zone == 2 then
					temp = 2
				else
					temp = 0
				end

				for i, r: any in EachRooms do
					if r.Rooms.OriginalX.Value == x and r.Rooms.OriginalZ.Value == y then
						ShouldSpawnDoor = false
						if r.RoomTemplates.Shape.Value == RoomType.ROOM1 then
							if r.Rooms.Angle.Value == 90 then
								ShouldSpawnDoor = true
							end
						elseif r.RoomTemplates.Shape.Value == RoomType.ROOM2 then
							if r.Rooms.Angle.Value == 90 or r.Rooms.Angle.Value == 270 then
								ShouldSpawnDoor = true
							end
						elseif r.RoomTemplates.Shape.Value == RoomType.ROOM2C then
							if r.Rooms.Angle.Value == 0 or r.Rooms.Angle.Value == 90 then
								ShouldSpawnDoor = true
							end
						elseif r.RoomTemplates.Shape.Value == RoomType.ROOM3 then
							if r.Rooms.Angle.Value == 0 or r.Rooms.Angle.Value == 180 or r.Rooms.Angle.Value == 90 then
								ShouldSpawnDoor = true
							end
						else
							ShouldSpawnDoor = true
						end

						if ShouldSpawnDoor then
							if x + 1 < MapWidth + 1 then
								if MapTemp[x + 1][y] > 0 then
									--left side of room
									local d = CreateDoor(r.Rooms.Zone.Value, x * RoomSpacing + RoomSpacing / 2, 0, y * RoomSpacing, 90, false)
								end
							end
						end

						ShouldSpawnDoor = false

						if r.RoomTemplates.Shape.Value == RoomType.ROOM1 then
							if r.Rooms.Angle.Value == 0 then
								ShouldSpawnDoor = true
							end
						elseif r.RoomTemplates.Shape.Value == RoomType.ROOM2 then
							if r.Rooms.Angle.Value == 0 or r.Rooms.Angle.Value == 180 then
								ShouldSpawnDoor = true
							end
						elseif r.RoomTemplates.Shape.Value == RoomType.ROOM2C then
							if r.Rooms.Angle.Value == 0 or r.Rooms.Angle.Value == 270 then
								ShouldSpawnDoor = true
							end
						elseif r.RoomTemplates.Shape.Value == RoomType.ROOM3 then
							if r.Rooms.Angle.Value == 0 or r.Rooms.Angle.Value == 90 or r.Rooms.Angle.Value == 270 then
								ShouldSpawnDoor = true
							end
						else
							ShouldSpawnDoor = true
						end

						if ShouldSpawnDoor then
							if y + 1 < MapHeight + 1 then
								if MapTemp[x][y + 1] > 0 then
									--bottom of room
									local d = CreateDoor(r.Rooms.Zone.Value, x * RoomSpacing, 0, y * RoomSpacing + RoomSpacing / 2, 0, false)
								end
							end
						end
					end
				end
			end
		end
	end
end

return MapGenerator
