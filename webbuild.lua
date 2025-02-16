#!/usr/bin/env lua
--[[
	GOALS
	- [x] Get the filetree for the given directory.
	- [ ] For each valid file, extract metadata. Otherwise, copy.
	- [ ] Go through html, css, and xml files in order and process them into an output directory.
		- [ ] Ensure that the files being processed have access to the filetree,
			  and that they can require files themselves.
--]]
local pp = require "preprocess"
local files = require "filetree"
-- local rss = require "rss"

local help_txt = ([[
usage: %s [input] [output] [options]
Processes files from the folder [input] and places the result in [output].
]]):format(arg[0])

local function is_directory(path)
	local f = io.popen("file '" .. path .. "'")
	local txt = f:read("a")
	f:close()
	return (string.find(txt, ("%s: directory"):format(path))) and true or false
end

if #arg < 2 then
	print(help_txt)
	return
end
for i = 1, #arg do
	if arg[i] == "--help" or arg[i] == "-h" then
		print(help_txt)
		return
	end
end

if is_directory(arg[2]) then
	local bool = false
	while not (bool == "y" or bool == "n") do
		io.stdout:write("Directory '" .. arg[2] .. "' already exists. Overwrite?  y/n) ")
		bool = io.stdin:read("l")
		if bool == "y" then
			io.popen("rm -r '" .. arg[2] .. "'")
			io.stdout:write("\nDeleted directory '" .. arg[2] .. "'.\n")
		elseif bool == "n" then
			print("aborted")
			return
		else
			print("invalid: try again")
		end
	end
end

local function copy_file(a, b)
	local i, o, err1, err2
	i, err1 = io.open(a, "r")
	o, err2 = io.open(b, "w+")
	if err2 and err2:find("No such file or directory") then
		os.execute(("mkdir --p -v '%s'"):format(b:gsub("/[^/]*$", "")))
		o, err2 = io.open(b, "w")
	end
	assert(i, err1)
	assert(o, err2)
	o:write(i:read("a"))
	i:close()
	o:flush()
	o:close()
end

local function get_extension(str)
	return string.match(str, ".*(%.[^.]+)$")
end
local extensions_to_process = {
	[".html"] = true,
	[".xml"] = true,
}

local files_to_process = {}
local function file_callback(short, full)
	local obj = {}
	obj.shortname = short
	obj.fullname = full
	obj.containing_directory = full:gsub("/[^/]*$", "")
	if obj.containing_directory == "" then
		obj.containing_directory = "/"
	end
	if extensions_to_process[get_extension(short)] then
		obj.metadata = pp.fmfile(arg[1] .. full) or {}
		if obj.metadata.ignore then
			copy_file(arg[1] .. full, arg[2] .. full)
		else
			table.insert(files_to_process, obj)
		end
	else
		copy_file(arg[1] .. full, arg[2] .. full)
	end
	return obj
end

local function file_sandbox_fix(base_tree, file_obj)
	local function internal(sbox)
		sbox.file = file_obj
		sbox.tree = base_tree[file_obj.containing_directory]
		sbox.macros["$"] = function(...) return ... end
		sbox.require_cache = {}
		sbox.require = function(path)
			if not path:find("%.lua$") then
				path = path .. ".lua"
			end
			if sbox.require_cache[path] then
				return sbox.require_cache[path]
			end
			local chunk, err = loadfile(arg[1] .. sbox.tree[path].fullname, "t", sbox)
			if err then
				error(err, 2)
			end
			if setfenv then
				setfenv(chunk, sbox)
			end
			sbox.require_cache[path] = chunk(file_obj.fullname) or true
			return sbox.require_cache[path]
		end
	end
	return internal
end

local tree = files.returnFiletree(arg[1], nil, file_callback)
for _, file in ipairs(files_to_process) do
	check_dir_handle, err = io.open(arg[2] .. file.fullname, "w+")
	if err and err:find("No such file or directory") then
		os.execute(("mkdir --p -v %s"):format(arg[2] .. file.containing_directory))
	end
	local sbox_fix = file_sandbox_fix(tree, file)
	if file.metadata.template then
		file.content = pp.getfile(arg[1] .. file.fullname)
		-- we gotta copy the tree rq to get the template
		local tree2 = tree["/"]
		tree2:_cd(file.containing_directory)
		local template_name = tree2[file.metadata.template]
		pp.writefile(arg[1] .. template_name.fullname, arg[2] .. file.fullname, {__setup_sandbox = sbox_fix})
	else
		pp.writefile(arg[1] .. file.fullname, arg[2] .. file.fullname, {__setup_sandbox = sbox_fix})
	end
end
--- testing
-- local inspect = require("kikito_inspect")
-- print(inspect(tree))
-- print("ls" .. inspect(tree:_lsrecurse()))
-- print(inspect(tree["index.html"]))
-- print(tree:_path("index.html"))