#!/usr/bin/env lua
-- Command-line invocation for the preprocessor.
local pp = require "preprocess"

local help_txt = ([[
usage: %s [options] [filenames]
Preprocesses files and exports them into a directory.
Available options are:
	-o name          | the directory to place the output files (default: "luapp.out/")
	-v               | display the names of each file being processed
	-d               | perform a dry run; the names of the files to be created will be printed. 
	-r, --recursive  | compile directories and their contents recursively
	-l, --linemaps   | output linemap files; these will be named [filename].linemap
	--silent         | silences print statements from processing files
	--help           | show this help message

Additional options given will be set to 'true' in the preprocessor. For example,
debug builds could be enabled by passing the --DEBUG option.

Additional options with given values will be set to those values in the preprocessor.
For example, build numbers could be tracked by passing a --BUILDNUM=42 option.
]]):format(arg[0])

local out_direc = "luapp.out/"
local verbose = false  -- CHANGE LATER
local recursive = false
local linemaps = false
local dry_run = false
local extra_arguments = {}
local filenames = {}

for i = 1, #arg do
	if arg[i] == "--help" or arg[i] == "-h" then
		print(help_txt)
		return
	end
end
-- File handling...
-- This is all very linux-dependent.

local function is_directory(path)
	local f = io.popen("file " .. path)
	local txt = f:read("a")
	f:close()
	return (string.find(txt, ("%s: directory"):format(path))) and true or false
end

local function insert_direc_contents(path)
	local f = io.popen("find " .. path)
	for line in f:lines() do
		if not is_directory(line) then
			table.insert(filenames, line)
		end
	end
	f:close()
end

-- Process the arguments.
local count = 0
while count < #arg do
	count = count + 1
	local argument = arg[count]
	-- This must be a flag.
	if string.match(argument, "^%-") then
		local stripped = argument:gsub("^%-%-?", "")
		-- Option: -o : change output directory
		if stripped == "o" then
			count = count + 1
			out_direc = arg[count]
			if not out_direc then
				error("flag '-o' must be followed by a valid filepath")
			end
			if not (out_direc:gsub(-1, -1) == "/") then
				out_direc = out_direc .. "/"
			end
		-- Option: -v : enable verbose
		elseif stripped == "v" then
			verbose = true
		-- Option: -d : enable dry-run
		elseif stripped == "d" then
			dry_run = true
		-- Option: -r : enable recursion
		elseif stripped == "r" or stripped == "recursive" then
			recursive = true
		-- Option: -l : enable linemaps
		elseif stripped == "l" or stripped == "linemaps" then
			linemaps = true
		-- Export all other flags to the preprocessor.
		else
			local _, _, key, val = stripped:find("^(%S+)=(.+)$")
			if key then
				extra_arguments[key] = tonumber(val) or val
			else
				extra_arguments[stripped] = true
			end
		end
	else
		-- Insert filenames into the list.
		if not recursive then
			if is_directory(argument) then
				error("filepath '" .. argument .. "' is a directory")
			else
				table.insert(filenames, argument)
			end
		else
			insert_direc_contents(argument)
		end
	end
end

-- Print help if no files were given.
if #filenames == 0 then
	print(help_txt)
	return
end

-- Process the files...
for _, filename in ipairs(filenames) do
	if filename:find("/") then
		local filename_base = filename:gsub("/[^/]+$", "")
		if dry_run then
			print("create directory '" .. out_direc .. filename_base .. "'")
		else
			os.execute(("mkdir --p %s %s"):format(verbose and "-v" or "", out_direc .. filename_base))
		end
	end
	if verbose or dry_run then
		print("processing file: " .. filename)
	end
	if not dry_run then
		pp.writefile(filename, out_direc .. filename, extra_arguments, linemaps)
	end
end
if dry_run then
	print("(no changes made)")
end