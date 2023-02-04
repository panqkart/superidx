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

function superi.save(minpos, maxpos, name)
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
	local meta_table = {} -- luacheck: ignore
	local meta_positions = minetest.find_nodes_with_meta(emin, emax) -- luacheck: ignore

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

		-- Serialize metadata (WIP and non-working).

		--[[
		local pos = voxelarea:position(loc)
		for _, meta_pos in pairs(meta_positions) do
			if vector.equals(pos, meta_pos) then
				local meta = minetest.get_meta(meta_pos):to_table()
				meta_table[minetest.pos_to_string(pos)] = meta

				-- Convert metadata item stacks to item strings
				for inv_name, list in pairs(meta.inventory) do
					for i, stack in ipairs(list) do
						meta.inventory[inv_name][i] = stack:to_string()
					end
				end
			end
		end--]]
	end

	superi.saved[name] = { size = size, nodenames = nodenames, nodes = superi.rle(nodes), param1 = param1_data, param2 = param2_data }
	storage:set_string(name, minetest.serialize(superi.saved[name])) -- To be able to load the file properly.

	minetest.mkdir(minetest.get_worldpath() .. "/schems")
	local file = io.open(minetest.get_worldpath() .."/schems/" ..name ..".sdx", "w+")
	local serial_data = minetest.serialize(superi.saved[name])
	if superi.use_zlib_compression then
		file:write(minetest.compress(serial_data:gsub(" ", ""), "deflate", 9))
	else
		file:write(serial_data:gsub(" ", ""))
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
	voxelmanip:write_to_map(true)

	-- Deserialize node metadata (WIP and non-working).
	minetest.after(0.1, function()
		if data.meta then
			for pos_str, meta in pairs(data.meta) do
				local pos = minetest.string_to_pos(pos_str)
				local meta_ref = minetest.get_meta(pos)

				meta_ref:from_table(meta)
			end
		end
	end)
end

-- Commands only for testing, initial release
minetest.register_chatcommand("save", { -- Function needs to handle small amount of maths to determine min and max pos, not permanent
	privs = {server = true},
	func = function(name, param)
		if not minetest.get_player_by_name(name) then return end
		if not superi.temp[name]["1"] or not superi.temp[name]["2"] then return end
		-- you don't know how much I hate doing this but thank god it's temporary
		local newpos1 = {x = superi.lesser(superi.temp[name]["1"].x, superi.temp[name]["2"].x), y = superi.lesser(superi.temp[name]["1"].y, superi.temp[name]["2"].y), z = superi.lesser(superi.temp[name]["1"].z, superi.temp[name]["2"].z)}
		local newpos2 = {x = superi.greater(superi.temp[name]["1"].x, superi.temp[name]["2"].x), y = superi.greater(superi.temp[name]["1"].y, superi.temp[name]["2"].y), z = superi.greater(superi.temp[name]["1"].z, superi.temp[name]["2"].z)}
		superi.save(newpos1, newpos2, param)
		minetest.chat_send_player(name, "Saved as " .. param ..".sdx!")
	end
})

minetest.register_chatcommand("load", {
	privs = {server = true},
	func = function(name, param)
		if not minetest.get_player_by_name(name) then return end
		if not superi.temp[name]["1"] then return end

		if storage:get_string(param) == "" then
			minetest.chat_send_player(name, "File " .. param .. ".sdx does not exist or is not saved in the mod storage.")
			return
		end
		superi.load(superi.temp[name]["1"], minetest.deserialize(storage:get_string(param)))
		minetest.chat_send_player(name, "Loaded " .. param ..".sdx!")
	end
})

minetest.register_chatcommand("1", {
	privs = {server = true},
	func = function(name)
		if not minetest.get_player_by_name(name) then return end

		local tpos = minetest.get_player_by_name(name):get_pos()
		superi.temp[name]["1"] = {x = math.floor(tpos.x), y = math.floor(tpos.y), z = math.floor(tpos.z)}
		minetest.chat_send_player(name, "Coordinates of 1 set to " .. dump(superi.temp[name]["1"]))
	end
})

minetest.register_chatcommand("2", {
	privs = {server = true},
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
