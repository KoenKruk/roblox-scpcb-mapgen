--!native
--!strict

local AssetCache = {}

local RoomsModule = require(script.RoomsModule)

local RoomType = {
	ROOM1 = 0,
	ROOM2 = 1,
	ROOM2C = 2,
	ROOM3 = 3,
	ROOM4 = 4
}

local roomTypes = {
	[0] = "ROOM1",
	[1] = "ROOM2",
	[2] = "ROOM2C",
	[3] = "ROOM3",
	[4] = "ROOM4"
}

local function Shape(room_type: number)
	if room_type == RoomType.ROOM1 then
		return "1"
	elseif room_type == RoomType.ROOM2 then
		return "2"
	elseif room_type == RoomType.ROOM2C then
		return "2C"
	elseif room_type == RoomType.ROOM3 then
		return "3"
	elseif room_type == RoomType.ROOM4 then
		return "4"
	else
		return ""
	end
end

function AssetCache.LoadRoom(room_name, room_type, zone: number, rng)
	local names = {}

	if room_name == "" then
		for i, room in RoomsModule.rooms do
			local inzone = false
			
			if room["zone1"] == zone or room["zone2"] == zone or room["zone3"] == zone then
				inzone = true
			end
			
			if room["path"] and room["shape"] and room["commonness"] and inzone then
				local shape = room["shape"]

				if shape.upper(shape) == Shape(room_type) then
					for i = 0, room["commonness"] - 1 do
						table.insert(names, room["name"])
					end
				end
			end
		end
	end

	if room_name == "" and #names > 0 then
		room_name = names[rng:NextInteger(1, #names)]
	end
	
	if room_name == "" and not table.find(RoomsModule.rooms, room_name) then
		return Instance.new("Model"), false
	end
	
	if script["Zone" .. zone][roomTypes[room_type]]:FindFirstChild(room_name) then
		return script["Zone" .. zone][roomTypes[room_type]][room_name], RoomsModule.rooms[room_name]["disableoverlapcheck"]
	else
		--if zone == 2 then
			warn("room not found in zone " .. zone .. ": " .. room_name)
		--end
		return Instance.new("Model"), RoomsModule.rooms[room_name]["disableoverlapcheck"]
	end
end

function AssetCache.LoadDoor(zone, big)
	if big then
		print("Door not found")
		return Instance.new("Model")
	elseif zone == 1 or zone == 3 then
		return script["Doors"]["LCZ"]["LCZDoor"]
	elseif zone == 2 then
		return script["Doors"]["HCZ"]["HCZDoor"]
	else
		print("Door not found")
		return Instance.new("Model")
	end
end

return AssetCache
