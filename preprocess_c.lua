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

if #arg == 0 then
	print(help_txt)
end
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

local filenames_to_process = {}
-- Process the arguments.
local count = 0
while count < #arg do
	count = count + 1
	local argument = arg[count]
	-- This must be an option.
	if string.match(argument, "^%-%w") then
		for opt in argument:gmatch("%w") do
		-- Option: -o : change output directory
			if opt == "o" then
				count = count + 1
				out_direc = arg[count]
				if not out_direc then
					print("error: flag '-o' must be followed by a valid filepath")
					return
				end
				if not (out_direc:gsub(-1, -1) == "/") then
					out_direc = out_direc .. "/"
				end
			-- Option: -v : enable verbose
			elseif opt == "v" then
				verbose = true
			-- Option: -d : enable dry-run
			elseif opt == "d" then
				dry_run = true
			-- Option: -r : enable recursion
			elseif opt == "r" then
				recursive = true
			-- Option: -l : enable linemaps
			elseif opt == "l" then
				linemaps = true
			end
		end
	-- This must be a flag.
	elseif string.match(argument,"^%-%-%w") then
		local stripped = argument:gsub("^%-%-", "")
		if stripped == "recursive" then
			recursive = true
		elseif stripped == "linemaps" then
			linemaps = true
		else -- Export all other flags to the preprocessor.
			local _, _, key, val = stripped:find("^(%S+)=(.+)$")
			if key then
				extra_arguments[key] = tonumber(val) or val
			else
				extra_arguments[stripped] = true
			end
		end
	else
		-- Insert filenames into an intermediate list, to make argument order less important.
		table.insert(filenames_to_process, argument)
	end
end
-- Insert filenames into the final list.
for _, filename in ipairs(filenames_to_process) do
	if not recursive then
		if is_directory(filename) then
			print("error: filepath '" .. filename .. "' is a directory. did you mean to use -r?")
			return
		else
			table.insert(filenames, filename)
		end
	else
		insert_direc_contents(filename)
	end
end

-- Print help if no files were given.
if #filenames == 0 then
	print("error: one or more files must be provided")
	return
end

local dry_created_directories = {}
-- Process the files...
for _, filename in ipairs(filenames) do
	if filename:find("/") then
		local filename_base = filename:gsub("/[^/]+$", "")
		local new_direc = out_direc .. filename_base
		if dry_run then
			if not dry_created_directories[new_direc] then
				print("create directory '" .. new_direc .. "'")
				dry_created_directories[new_direc] = true
			end
		else
			os.execute(("mkdir --p %s %s"):format(verbose and "-v" or "", new_direc))
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