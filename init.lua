superi = {}
local storage = minetest.get_mod_storage()

-- Whether to save it as raw text as serialized or under binary data via zlib
superi.use_zlib_compression = false
superi.saved = {}
superi.temp = {}

function superi.lesser(v1, v2)
	if v1 < v2 then return v1 end
	return v2
end

function superi.greater(v1, v2)
	if v1 < v2 then return v2 end
	return v1
end

function superi.rle(nodes)
	local ti = 1
	local tstr

	local nodes_rle = {}

	for i = 1, #nodes do
		if nodes[i] ~= nodes[i+1] then
			tstr = "{" ..nodes[i] .."," ..ti .."}"
			if #tstr > ti then
				for _ = 1, ti do
					table.insert(nodes_rle, nodes[i])
				end
			else
				table.insert(nodes_rle, {nodes[i], ti})
			end
			ti = 1
		else
			ti = ti + 1
		end

	end
	return nodes_rle
end

function superi.save(minpos, maxpos, name, track_name)
	local nodenames = {}
	local nodes = {}
	local tempnode
	local is_nodename = false
	local size = vector.subtract(maxpos, minpos)
	local c_ids = {}
	local param2_data, param1_data = { }, { }

	local voxelmanip = minetest.get_voxel_manip(minpos, maxpos)
	local emin, emax = voxelmanip:read_from_map(minpos, maxpos)
	local voxelarea = VoxelArea:new{MinEdge = emin, MaxEdge = emax}

	-- Get node meta of all the nodes.
	local meta_table = {}
	local meta_positions = minetest.find_nodes_with_meta(emin, emax)

	local vm_nodes = voxelmanip:get_data()
	local param1 = voxelmanip:get_light_data()
	local param2 = voxelmanip:get_param2_data()

	for loc in voxelarea:iterp(minpos, maxpos) do
		table.insert(param1_data, param1[loc])
		table.insert(param2_data, param2[loc])

		tempnode = vm_nodes[loc]
		for n = 1, #nodenames do
			is_nodename = false
			if tempnode == c_ids[n] then
				table.insert(nodes, n)
				is_nodename = true
				break
			end
		end
		if not is_nodename then
			table.insert(nodenames, minetest.get_name_from_content_id(tempnode))
			table.insert(c_ids, tempnode)
			table.insert(nodes, #nodenames)
		end

		-- Serialize metadata
		--
		-- START: Code taken from the `modgen` mod by BuckarooBanzay.
		-- Thanks! https://github.com/BuckarooBanzay/modgen/blob/master/serialize.lua#L118
		for _, meta_pos in pairs(meta_positions) do
			local relative_pos = vector.subtract(meta_pos, minpos)
			local meta = minetest.get_meta(meta_pos):to_table()

			-- Convert metadata item stacks to item strings
			for _, invlist in pairs(meta.inventory) do
				for index = 1, #invlist do
					local itemstack = invlist[index]
					if itemstack.to_string then
						invlist[index] = itemstack:to_string()
					end
				end
			end

			if next(meta) and (next(meta.fields) or next(meta.inventory)) then
				meta_table = meta_table or {}
				meta_table[minetest.pos_to_string(relative_pos)] = meta
			end
			-- END: Code taken from the `modgen` mod by BuckarooBanzay.
		end
	end

	superi.saved[name] = {size = size, nodenames = nodenames, meta = meta_table, nodes = superi.rle(nodes), param1 = param1_data, param2 = param2_data}
	storage:set_string(name, minetest.serialize(superi.saved[name])) -- To be able to load the file properly.

	minetest.mkdir(minetest.get_worldpath() .. "/schems")
	local file = io.open(minetest.get_worldpath() .. "/schems/" .. name ..".lua", "w+")
	local serial_data = minetest.serialize(superi.saved[name])
	if superi.use_zlib_compression then
		file:write(minetest.compress(serial_data, "deflate", 9))
	else
		local return_pos = serial_data:find("return")
		serial_data = serial_data:sub(1, return_pos - 1) .. "\n" .. serial_data:sub(return_pos)

		serial_data = serial_data:gsub("return", "tracks.all_tracks[\"" .. track_name .."\"].data =")

		-- Remove all digits at the very end of the file.
		while serial_data:sub(-1):match("%d") do
			serial_data = serial_data:sub(1, -2)
		end

		serial_data = serial_data .. "\n"
		file:write(serial_data)
	end
	file:close()
end

function superi.load(minpos, data)
	local i, k = 1, 1
	local ti = 1
	local maxpos = vector.add(minpos, data.size)
	local c_ids = {}

	local voxelmanip = minetest.get_voxel_manip(minpos, maxpos)
	local emin, emax = voxelmanip:read_from_map(minpos, maxpos)
	local voxelarea = VoxelArea:new{MinEdge = emin, MaxEdge = emax}

	local param1 = voxelmanip:get_light_data()
	local param2 = voxelmanip:get_param2_data()

	local vm_nodes = voxelmanip:get_data()

	for j = 1, #data.nodenames do
		table.insert(c_ids, minetest.get_content_id(data.nodenames[j]))
	end

	for loc in voxelarea:iterp(minpos, maxpos) do
		param1[loc] = data.param1[k]
		param2[loc] = data.param2[k]
		k = k + 1

		if data.nodenames[data.nodes[i]] then
			vm_nodes[loc] = c_ids[data.nodes[i]]
			i = i + 1
		else
			vm_nodes[loc] = c_ids[data.nodes[i][1]]

			if ti < data.nodes[i][2] then
				ti = ti + 1
			else
				i = i + 1
				ti = 1
			end
		end
	end

	voxelmanip:set_data(vm_nodes)
	voxelmanip:set_light_data(param1)
	voxelmanip:set_param2_data(param2)
	voxelmanip:write_to_map(false)

	-- Deserialize and set node metadata from `data.meta`.
	minetest.after(0.1, function()
		if data.meta then
			for pos, value in pairs(data.meta) do
				local absolute_pos = vector.add(minpos, minetest.string_to_pos(pos))
				minetest.get_meta(absolute_pos):from_table(value)
			end
		end
	end)
end

-- Commands only for testing, initial release
minetest.register_chatcommand("save", { -- Function needs to handle small amount of maths to determine min and max pos, not permanent
	privs = { pk_map_creator = true },
	params = "<filename> <track_name>", -- PanqKart edition.
	func = function(name, param)
		if not minetest.get_player_by_name(name) then return end
		if not superi.temp[name]["1"] or not superi.temp[name]["2"] then return end

		local newpos1 = {x = superi.lesser(superi.temp[name]["1"].x, superi.temp[name]["2"].x), y = superi.lesser(superi.temp[name]["1"].y, superi.temp[name]["2"].y), z = superi.lesser(superi.temp[name]["1"].z, superi.temp[name]["2"].z)}
		local newpos2 = {x = superi.greater(superi.temp[name]["1"].x, superi.temp[name]["2"].x), y = superi.greater(superi.temp[name]["1"].y, superi.temp[name]["2"].y), z = superi.greater(superi.temp[name]["1"].z, superi.temp[name]["2"].z)}

		-- Multiple parameter support.
		local filename = param:split(" ")[1]
		local track_name = param:split(" ")[2]

		superi.save(newpos1, newpos2, filename, track_name)

		minetest.chat_send_player(name, "Saved as " .. filename .. ".lua!")
		minetest.chat_send_player(name, "\nIf you're in the map maker mode in PanqKart, check out the map maker guide for more information on how to use this file.")
		minetest.chat_send_player(name, "Link to the guide: <GitHub link>")
	end
})

minetest.register_chatcommand("load", {
	privs = { pk_map_creator = true },
	func = function(name, param)
		if not minetest.get_player_by_name(name) then return end
		if not superi.temp[name]["1"] then return end

		if storage:get_string(param) == "" then
			minetest.chat_send_player(name, "File " .. param .. ".sdx does not exist or is not saved in the mod storage.")
			return
		end
		superi.load(superi.temp[name]["1"], minetest.deserialize(storage:get_string(param)))
		minetest.chat_send_player(name, "Loaded " .. param ..".lua!")
	end
})

minetest.register_chatcommand("1", {
	privs = { pk_map_creator = true },
	func = function(name)
		if not minetest.get_player_by_name(name) then return end

		local tpos = minetest.get_player_by_name(name):get_pos()
		superi.temp[name]["1"] = {x = math.floor(tpos.x), y = math.floor(tpos.y), z = math.floor(tpos.z)}
		minetest.chat_send_player(name, "Coordinates of 1 set to " .. dump(superi.temp[name]["1"]))
	end
})

minetest.register_chatcommand("2", {
	privs = { pk_map_creator = true },
	func = function(name)
		if not minetest.get_player_by_name(name) then return end
		local tpos = minetest.get_player_by_name(name):get_pos()
		superi.temp[name]["2"] = {x = math.floor(tpos.x), y = math.floor(tpos.y), z = math.floor(tpos.z)}
		minetest.chat_send_player(name, "Coordinates of 2 set to " .. dump(superi.temp[name]["2"]))
	end
})

minetest.register_on_joinplayer(function(player)
	superi.temp[player:get_player_name()] = {}
end)

minetest.register_on_leaveplayer(function(player)
	superi.temp[player:get_player_name()] = nil
end)
