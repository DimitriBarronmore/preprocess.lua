-- local mod = {}

local function is_directory(path)
	local f = io.popen("file '" .. path .. "'")
	local txt = f:read("a")
	f:close()
	return (string.find(txt, ("%s: directory"):format(path))) and true or false
end

local function get_separated(str)
	local tab = {}
	for capture in str:gmatch("[^/\\]+") do
		tab[#tab+1] = capture
	end
	return tab
end

local function navigate(ftree, path, wants_directory)
	local working = ftree["*working"]
	local steps = get_separated(path)
	if path:match("^/") then
		working = working['/']
	end
	for i, step in ipairs(steps) do
		local in_f = working['*files']
		if step == "/" or step == ".." or step == "." then
			in_f = working
		elseif wants_directory or (i < #steps) then
			in_f = working['*folders']
		end
		working = in_f[step]
		if not working then 
			return false, ("file or directory '" .. table.concat(steps, "/", 1, i) .. "' was not found")
		end
	end
	return working
end

local return_directory_navigator
local directorynav_mtable = {}
directorynav_mtable.__index = function(t, k)
	-- print("getting " .. k)
	if directorynav_mtable[k] then
		return directorynav_mtable[k]
	elseif k == '..' then
		return t['*working']['..'] and return_directory_navigator(t['*working']['..'])
	elseif k == '.' then
		return t['*working']['.'] and return_directory_navigator(t['*working']['.'])
	elseif k == '/' then
		return t['*working']['/'] and return_directory_navigator(t['*working']['/'])
	elseif t['*working'][k] then
		return t['*working'][k]
	else
		local out, err = navigate(t, k, false)
		if out == false then
			out, err = navigate(t, k, true)
		end
		if err then
			-- error("attempt to access invalid file or directory\n\t" .. err, 2)
			return nil
		end
		if type(out) == "table" and out['*folders'] then
			return return_directory_navigator(out)
		else
			return out
		end
	end
end
directorynav_mtable.__newindex = function()
	error("attempt to modify read-only table", 2)
end
function directorynav_mtable:_cd(into)
	local working, err = navigate(self, into, true)
	if not working then error("attempt to navigate to invalid directory\n\t" .. err, 2) end
	self['*working'] = working
	return self
end
function directorynav_mtable:_path(filename)
	local path = ""
	local parent = self['..']
	if parent then
		-- print(parent)
		path = parent:_path()
	else
		return "/" .. (filename or "")
	end
	return path .. self['*name'] .. "/" .. (filename or "")
end
local function getkeys(tab, source, pre, post)
	pre = pre or ""
	post = post or ""
	for k in pairs(source) do
		tab[#tab+1] = pre .. k .. post
	end
	return tab
end
function directorynav_mtable:_lsfiles(from)
	local err
	if not from then
		from = self['*working']
	else
		from, err = navigate(self, from, true)
	end
	if err then
		error("attempt to access invalid directory\n\t" .. err, 2)
	end
	local tab = getkeys({}, from['*files']) 
	table.sort(tab)
	return tab
end
function directorynav_mtable:_lsdirec(from)
	local err
	if not from then
		from = self['*working']
	else
		from, err = navigate(self, from, true)
	end
	if err then
		error("attempt to access invalid directory\n\t" .. err, 2)
	end
	local tab = getkeys({}, from['*folders'], nil, "/") 
	table.sort(tab)
	return tab
end
function directorynav_mtable:_ls(from)
	local err
	if not from then
		from = self['*working']
	else
		from, err = navigate(self, from, true)
	end
	if err then
		error("attempt to access invalid directory\n\t" .. err, 2)
	end
	local tab = {}
	getkeys(tab, from['*files']) 
	getkeys(tab, from['*folders'], nil, "/") 
	table.sort(tab)
	return tab
end
local ls_intern_recurse
function ls_intern_recurse(gf, gd, working, pre, tabfull)
	local tabfull = tabfull or {}
	local tabdirs = {}
	if gf then getkeys(tabfull, working['*working']['*files'], pre) end
	if gd then getkeys(tabfull, working['*working']['*folders'], pre, "/") end
	getkeys(tabdirs, working['*working']['*folders']) 
	for _, v in ipairs(tabdirs) do
		ls_intern_recurse(gf, gd, working[v], (pre or "") .. v .. "/", tabfull)
	end
	return tabfull
end
function directorynav_mtable:_lsrecurse(from)
	local err
	if not from then
		from = self
	else
		from, err = return_directory_navigator(navigate(self, from, true))
	end
	if err then
		error("attempt to access invalid directory\n\t" .. err, 2)
	end
	local final = ls_intern_recurse(true, true, from)
	table.sort(final)
	return final
end
function directorynav_mtable:_lsfilesrecurse(from)
	local err
	if not from then
		from = self
	else
		from, err = return_directory_navigator(navigate(self, from, true))
	end
	if err then
		error("attempt to access invalid directory\n\t" .. err, 2)
	end
	local final = ls_intern_recurse(true, false, from)
	table.sort(final)
	return final
end
function directorynav_mtable:_lsdirecrecurse(from)
	local err
	if not from then
		from = self
	else
		from, err = return_directory_navigator(navigate(self, from, true))
	end
	if err then
		error("attempt to access invalid directory\n\t" .. err, 2)
	end
	local final = ls_intern_recurse(false, true, from)
	table.sort(final)
	return final
end

return_directory_navigator = function(ftree)
	assert(ftree, "internal error: made directory navigator without given directory object")
	return setmetatable({['*working'] = ftree}, directorynav_mtable)
end

local function return_skeleton_directory(name, root, parent)
	local tab = {
		['*files'] = {},
		['*folders'] = {},
		['*name'] = name,
		[".."] = parent,
	}
	tab["."] = tab
	tab["/"] = root or tab
	return tab
end
local function return_fullpath(a, b)
	return b
end

local function match_ignores(line, ignore)
	if ignore == nil then return false end
	local desired_result
	if ignore.mode == "whitelist" or ignore.mode == nil then
		desired_result = false
	elseif ignore.mode == "blacklist" then
		desired_result = true
	end
	for _, str in ipairs(ignore) do
		if line:match(str) then 
			return desired_result
		else
			return not desired_result
		end
	end
end
---@param path string
---@param ignore table | nil
---@param for_each_file_callback function | nil
local function returnFiletree(path, ignore, for_each_file_callback)
	assert(type(path) == "string")
	assert(type(ignore) == "table" or type(ignore) == "nil")
	assert(type(for_each_file_callback) == "function" or type(for_each_file_callback) == "nil")
	if not for_each_file_callback then for_each_file_callback = return_fullpath end
	path = path:gsub("/$", "")
	local f, err = io.popen("find -L " .. path)
	assert(f, err)
	local ftree_root = return_skeleton_directory(path)
	for full_line in f:lines() do
		local working_directory = ftree_root
		local line = full_line
		local is_directory = is_directory(full_line)
		local processed_line = "/"
		-- print('---')
		if not match_ignores(line, ignore) then --test
			local names = get_separated(line)
			for i, name in ipairs(names) do
				if name == path then
					;; -- do nothing, this is root
				elseif (i < #names) or is_directory then
					-- this must be a directory, either because it's not the top of the path
					-- or because the top of the path is a directory and not a file
					processed_line = processed_line .. name .. "/"
					-- make sure to check if it's already in the tree.
					if not working_directory['*folders'][name] then
						working_directory['*folders'][name] = return_skeleton_directory(name, ftree_root, working_directory)
					end
					working_directory = working_directory['*folders'][name]
				else
					-- we've reached the top, and it's aa file.
					processed_line = processed_line .. name
					working_directory['*files'][name] = for_each_file_callback(name, processed_line)
				end
			end
		end
	end
	return return_directory_navigator(ftree_root)
end

-- local inspect = require("kikito_inspect")
-- local tree = returnFiletree("testing/", {mode="whitelist", ".-%.lua$"})
-- print(inspect(tree))

return { returnFiletree = returnFiletree }


--[[ TODO
	- [x] add lsrecurse to get all files in current folder and below.
	- [x]full-path navigation based on `./`, `../`, and `/` at the start of an index (lower priority)
		- [x] make ls functions respect full-path navigation for even more unix-ness.
	- [x] make the "ignore" argument in the base function actually work.
		- blacklist or whitelist
	- [ ] integrate process library metadata snatching to ensure it works
--]]

--[[
		USAGE
		to get a filetree use:
			mod.returnFiletree(root_directory, ignore, for_each_file_callback)
		this creates and returns a filetree crawler object with the given directory as "/".
		ignore is a table of strings, with an optional 'mode' field which can be "whitelist" or "blacklist".
		  the mode is applied based on whether a full filepath matches one of these strings through string.match.
		  the default behavior is whitelist, unless ignore is empty.
		for_each_file_callback(short, full_line) is a callback function called for each file discovered.
		  it takes two arguments, the filename of the file and the full path to the file from root.
		  the callback must return a value, which will be keyed to that file in the filetree.
		  the default callback returns the string containing the full filepath.

		the filetree crawler object has the following functions:
		  _ls(from) - lists all files and folders in the wgiven or orking directory
		  _lsfiles(from) - lists only files in the given or working directory
		  _lsdirec(from) - lists only folders in the given or working directory
		  _lsrecurse(from), _lsfilesrecurse(from), lsdirecrecurse(from) - like the above, but returns all
		    files/directories below this point in the file structure.
		  _path(filename) - returns the full path from root to the file given, or to the current
		    working directory if one is not given.
		  _cd(into) - changes the current working directory, respecting '..' and '/'. returns the
		    filetree craweler for chaining.

		all the prior functions will respect full unix-like filepaths.

		attempting to index the crawler with the name of a directory returns a new crawlwer with
		  the working directory set to the indexed directory.
		attempting to index the crawler with the name of a file in the CWD returns the file object
		  as returned from for_each_file_callback.
--]]