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

local function copy_file(a, b)
	local i, o, err1, err2
	i, err1 = io.open(a, "r")
	o, err2 = io.open(b, "w+")
	if err2 and err2:find("No such file or directory") then
		os.execute(("mkdir --p -v %s"):format(b:gsub("/[^/]*$", "")))
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
}

local inspect = require("kikito_inspect")

local files_to_process = {}
local function file_callback(short, full)
	local obj = {}
	obj.shortname = short
	obj.fullname = full
	if extensions_to_process[get_extension(short)] then
		-- print("html file not copied: " .. full)
		table.insert(files_to_process, obj)
		obj.metadata = pp.fmfile(arg[1] .. full) or {}
	else
		copy_file(arg[1] .. full, arg[2] .. full)
	end
	return obj
end

local tree = files.returnFiletree(arg[1], nil, file_callback)
for _, file in ipairs(files_to_process) do
	check_dir_handle, err = io.open(arg[2] .. file.fullname, "w+")
	if err and err:find("No such file or directory") then
		os.execute(("mkdir --p -v %s"):format(arg[2] .. file.fullname:gsub("/[^/]*$", "")))
	end
	if file.metadata and file.metadata.ignore then
		copy_file(arg[1] .. file.fullname, arg[2] .. file.fullname)
	elseif file.metadata and file.metadata.template then
		local text = pp.getfile(arg[1] .. file.fullname)
		file.content = text
		pp.writefile(arg[1] .. file.metadata.template, arg[2] .. file.fullname, {["file"] = file})
	else
		pp.writefile(arg[1] .. file.fullname, arg[2] .. file.fullname)
	end
end
--- testing
print(inspect(tree))
print("ls" .. inspect(tree:_lsrecurse()))
print(inspect(tree["index.html"]))
print(tree:_path("index.html"))