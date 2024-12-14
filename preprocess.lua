
--[[ VERSION-AGNOSTIC FILE LOADING ]]

local function load_51(text, name, mode, env)
    local iter = function()
        local tx = text
        text = ""
        return tx
    end
    local func, err = load(iter, name)
    if err then
        -- error(err)
        return nil, err
    end
    if env then
        setfenv(func, env)
    end
    return func
end

local load_func
if _VERSION > "Lua 5.1" then
    load_func = load
else
    load_func = load_51
end

--[[ BASIC SANDBOX CREATION ]]

local unpack = unpack
if _VERSION > "Lua 5.1" then
    unpack = table.unpack
end

local export = {}

local function copy(tab)
    local newtab = {}
    for key, value in pairs(tab) do
        if type(value) == "table" then
            newtab[key] = copy(value)
        else
            newtab[key] = value
        end
    end
    return newtab
end
  
  -- A safe sandbox for directives.
  -- This will be copied anew for each new file being processed.
  local sandbox_blueprint = {
      _VERSION = _VERSION,
      coroutine = copy(coroutine),
      io = copy(io), -- Is this too much power? It's probably fine.
      math = copy(math),
      string = copy(string),
      table = copy(table),
      assert = assert,
      error = error,
      ipairs = ipairs,
      next = next,
      pairs = pairs,
      pcall = pcall,
      print = print,
      select = select,
      tonumber = tonumber,
      tostring = tostring,
      type = type,
      unpack = unpack,
      xpcall = xpcall
}

local function new_sandbox()
    return copy(sandbox_blueprint)
end

-- [[ FILESYSTEM HELPER ]]

local fs = {}

fs.open = function(filepath, mode)
	if mode == nil then mode = "r" end
	local file, err = io.open(filepath, mode)
	-- if file then
	-- 	return newfile_lua(file)
	-- end
    return file, err
end

fs.exists = function(filepath)
	local file = io.open(filepath)
	if file ~= nil then
		file:close()
		return true
	else
		return false
	end
end

fs.search_filepath = function(filepath, filetype)
	filetype = filetype or ".lua"
	local filepath = filepath:gsub("^%./+", "")
    for path in package.path:gmatch("[^;]+") do
        local fixed_path = path:gsub("%.lua", filetype):gsub("%?", (filepath:gsub("%.", "/")))
        if fs.exists(fixed_path) then return fixed_path end
    end
end

-- [[ ACTUAL FILE PREPROCESSING ]]

local export = {}

--states:
-- need_left_parens (look for leftparen)
-- between_args (ignore spaces)
-- non_string (match chars and split on commas)
-- in_string (try to exit the string)
-- gather_multiline (for gathering the brackets)
-- gather_multiline_closing
-- in_multiline (try to exit the string)
local function extract_args(iter_str)
    local args = {}
    local curr_arg = {}
    local full_iter = {}
    local current_state = "need_left_parens"
    local string_type, last_char
    local eq_count = 0
    local paren_count = 0
    for char in iter_str:gmatch(".") do
        table.insert(full_iter, char)
        -- print(char)
        if current_state == "need_left_parens" then
            if not ( char:match("%s") or (char == "(") ) then
                return false
            elseif char == "(" then
                paren_count = paren_count + 1
                current_state = "non_string"
            end

        elseif current_state == "inbetween_args" then
            if not char:match("%s") then
                current_state = "non_string"
                    -- hotpatch in main state behavior
                    if char == "," then
                        table.insert(args, table.concat(curr_arg) or "")
                        curr_arg = {}
                        current_state = "inbetween_args"
                    elseif char == "(" then
                        table.insert(curr_arg, char)
                        paren_count = paren_count + 1
                    elseif char == ")" then
                        paren_count = paren_count - 1
                        if paren_count == 0 then
                            table.insert(args, table.concat(curr_arg) or "")
                            return args, table.concat(full_iter)
                        else
                            table.insert(curr_arg, char)
                        end
                    elseif char == '"' or char == "'" then
                        current_state = "in_string"
                        string_type = char
                        table.insert(curr_arg, char)
                    elseif char == "[" then
                        string_type = 0
                        current_state = "gather_multiline"
                        table.insert(curr_arg, char)
                    else
                        table.insert(curr_arg, char)
                    end
            end

        elseif current_state == "non_string" then
            if char == "," then
                table.insert(args, table.concat(curr_arg) or "")
                curr_arg = {}
                current_state = "inbetween_args"
            elseif char == "(" then
                table.insert(curr_arg, char)
                paren_count = paren_count + 1
            elseif char == ")" then
                paren_count = paren_count - 1
                if paren_count == 0 then
                    table.insert(args, table.concat(curr_arg) or "")
                    return args, table.concat(full_iter)
                else
                    table.insert(curr_arg, char)
                end
            elseif char == '"' or char == "'" then
                current_state = "in_string"
                string_type = char
                table.insert(curr_arg, char)
            elseif char == "[" then
                string_type = 0
                current_state = "gather_multiline"
                table.insert(curr_arg, char)
            else
                table.insert(curr_arg, char)
            end

        elseif current_state == "in_string" then
            table.insert(curr_arg, char)
            if char == string_type then
                if last_char ~= "\\" then
                    current_state = "non_string"
                end
            end

        elseif current_state == "gather_multiline" then
            if char == "=" then
                string_type = string_type + 1
                table.insert(curr_arg, char)
            elseif char == "[" then
                current_state = "in_multiline"
                table.insert(curr_arg, char)
            else
                current_state = "non_string" -- quickpatch main state behavior
                if char == "," then
                    table.insert(args, table.concat(curr_arg) or "")
                    curr_arg = {}
                    current_state = "inbetween_args"
                elseif char == "(" then
                    table.insert(curr_arg, char)
                    paren_count = paren_count + 1
                elseif char == ")" then
                    paren_count = paren_count - 1
                    if paren_count == 0 then
                        table.insert(args, table.concat(curr_arg) or "")
                        return args
                    else
                        table.insert(curr_arg, char)
                    end
                elseif char == '"' or char == "'" then
                    current_state = "in_string"
                    string_type = char
                    table.insert(curr_arg, char)
                else
                    table.insert(curr_arg, char)
                end
            end

        elseif current_state == "in_multiline" then
            if char == "]" and last_char ~= "\\" then
                current_state = "gather_multiline_closing"
            end
            table.insert(curr_arg, char)

        elseif current_state == "gather_multiline_closing" then
            if char == "=" then
                eq_count = eq_count + 1
                if eq_count > string_type then
                    eq_count = 0
                    current_state = "in_multiline"
                end
            elseif char == "]" then
                if eq_count == string_type then
                    current_state = "non_string"
                    eq_count = 0
                else
                    current_state = "in_multiline"
                end
            end
            table.insert(curr_arg, char)
        end
        last_char = char
    end
    -- print("end of input")
end

local function change_macros(ppenv, line, count, name)
    for _, macro in ipairs(ppenv.macros.__listed) do
        local res = ppenv.macros[macro]
        local fixedmacro = macro:gsub("([%^$()%.[%]*+%-%?%%])", "%%%1")

        -- Simple text-based Macros.
        if type(res) == "string" or type(res) == "number" or type(res) == "boolean" then
            res = tostring(res)
            line = line:gsub(fixedmacro, ( res:gsub("%%", "%%%%")) )

        -- Function-like macros.
        elseif type(res) == "table" then
            local s, e = 1,1
            repeat
                -- Opening paren.
                s, e = string.find(line, fixedmacro .. "%s*%(", e)
                if s then
                    local after = line:sub(e, -1)
                    local args, full = extract_args(after)
                    if args then
                        -- Pad special characters?
                        local fulltext = (fixedmacro .. full:gsub("([%^$()%.[%]*+%-%?%%])", "%%%1"))
                        line = line:gsub(fulltext, function()
                           local result = res._res
                            if #args < # res._args then
                                for i = 1, #res._args - #args do
                                    args[#args+1] = ""
                                end
                            end
                            for i, argument in ipairs(args) do
                                local argname = res._args[i]
                                if argname and argname ~= "..." then
                                    result = result:gsub(argname, (argument:gsub("%%","%%%%")) )
                                elseif argname == "..." then
                                    result = result:gsub("%.%.%.", table.concat(args, ", ", i))
                                end
                            end
                           e = 1
                           return result
                        end)

                    end
                end
            until s == nil

        -- Callback macros.
        elseif type(res) == "function" then
            local s, e = 1,1
            repeat
                s, e = string.find(line, fixedmacro .. "%s*%(", e)
                if s then
                    local after = line:sub(e, -1)
                    local args, full = extract_args(after)
                    if args then
                        local full_match = fixedmacro .. full:gsub("([%^$()%.[%]*+%-%?%%])", "%%%1")
                        line = line:gsub(full_match, function()
                            local chunk = string.rep("\n", count - 1) .. string.format("return macros[\"%s\"]( %s )", macro, table.concat(args, ", "))
                            local f, err = load_func(chunk, name .. " (preprocessor function)", "t", ppenv)
                            if err then
                                error(err,2)
                            end
                            local returns = { f() }
                            for i, val in ipairs(returns) do
                                returns[i] = tostring(val)
                            end
                            local res = "" .. table.concat(returns, ", ")
                            return res
                        end)
                    end
                end
            until s == nil
        end

    end
    return line
end

local macros_mt = {
    __newindex = function(t,k,v)
        local s, e, parens = k:find("(%b())$")
        if s then
            k = k:sub(1, s-1)
            -- print(k)
            parens = parens:sub(2,-1)
            -- print(parens)
            local argnames = {}

            for arg in parens:gmatch("%s*([%a%d_ %.]+)[,)]") do
                -- print(arg)
                table.insert(argnames, arg)
            end
            v = {_args = argnames, _res = v}
            -- print(v._res)
        end

        table.insert(t.__listed, k)
        rawset(t,k,v)
    end
}

-- Set up local variable back here for the sake of forward definition.
local compile_lines


local fm_check_tab_contents -- Backdefined for frontmatter checking.
fm_check_tab_contents = function(tab, seen, level)
    level = (level and level + 1) or 3
    seen = seen or {}
    for _, v in pairs(tab) do
        local ty = type(v)
        if (ty == "function") or (ty == "thread") or (ty == "userdata") then
            error("frontmatter can only contain primitive values", level)
        elseif (ty == "table") and not seen[ty] then
            seen[ty] = true
            fm_check_tab_contents(v, seen, level)
        end
    end
end

local function setup_sandbox(name, arguments, base_env)
    local sandbox
    if not base_env then
        sandbox = new_sandbox()
        sandbox.macros = setmetatable({__listed = {}}, macros_mt)
        sandbox.__included = {}
    else
        sandbox = {}
    end
    if arguments then
        for k, v in pairs(arguments) do
            sandbox[k] = v
        end
    end
    if sandbox.silent == true then
        sandbox.print = function() end
    end

    sandbox.filename = name or ""
    sandbox._output = { }
    sandbox.__write_lines = {}
    sandbox.__define_lines = {}
    sandbox._linemap = {}
    sandbox.__special_positions = {}
    sandbox.__count = 0
    sandbox.__frontmatter = false

    sandbox.frontmatter = function(tab)
        if sandbox.__frontmatter then
            error("frontmatter can only be defined once", 2)
        elseif sandbox.__included[sandbox.filename] then -- If this file is an inclusion...
            error("cannot define frontmatter from an included file", 2)
        elseif #sandbox._output > 0 then -- If anything has been marked for output...
            error("frontmatter must be defined at the beginning of the file", 2)
        end

        fm_check_tab_contents(tab)
        for k, v in pairs(tab) do
            sandbox[k] = v
        end

        sandbox.__frontmatter = tab
    end

    sandbox.__writefromline = function(num, skip_macros)
        local line = sandbox.__write_lines[num][1]
        if not skip_macros then
            line = change_macros(sandbox, line, num, name)
        end
        table.insert(sandbox._output, line)
        sandbox._linemap[#sandbox._output] = sandbox.__write_lines[num][2]
    end

    sandbox.__write_define = function(a, b)
        sandbox.__define_lines[sandbox.__count] = {a, b or ""}
        return ("__define(%s)"):format(sandbox.__count)
    end
    sandbox.__define = function(num)
        local l = sandbox.__define_lines[num]
        local key, result = l[1], l[2]
        sandbox.macros[key] = result
    end

    sandbox.write = function(str, skip_macros)
        local line = tostring(str)
        if not skip_macros then
            line = change_macros(sandbox, line, sandbox.__count, name)
        end
        table.insert(sandbox._output, line)
        sandbox._linemap[#sandbox._output] = debug.getinfo(2, "l").currentline
    end

    sandbox.include = function(filename, flags)
        if sandbox.filename:find("[/\\]") then
            local filename_base = sandbox.filename:gsub("[^/\\]+$", "")
            filename = filename_base .. filename
        end
        if sandbox.__included[filename] then
            error("detected cyclic inclusion loop", 2)
        else
            sandbox.__included[filename] = true
        end
        local file, err = fs.open(filename, "r")
        if file == nil then
            error("file " .. filename .. " could not be included\n" .. err, 2)
        end
        local inclbox = compile_lines(file, filename, flags, sandbox)
        file:close()
        for count, line in ipairs(inclbox._output) do
            table.insert(sandbox._output, line)
            local pos_string = tostring(sandbox.__count - 1) .. (" > %s:%s"):format(filename, inclbox._linemap[count])
            sandbox._linemap[#sandbox._output] = pos_string
        end
        sandbox.__included[filename] = nil
    end
    if base_env then
        setmetatable(sandbox, {__index = base_env, __newindex = base_env})
    end
    return sandbox
end

local function multiline_status(line, in_string, eqs)
    local s, e = 1, nil
    repeat
        if not in_string then
            s, e, eqs = line:find("%[(=*)%[", s)
            if s then
                in_string = true
            end
        else
            s, e = line:find(("]%s]"):format(eqs), s, true)
            if s then
                in_string = false
                eqs = ""
            end
        end
    until s == nil
    return in_string, eqs
end

local function find_invalid_block_positions(input)
    local cache = {}
    local s, e = 0, nil -- uniline
    repeat
        s, e = string.find(input, "(['\"])[^\n]-[^\\]%1", s)
        if s then
            table.insert(cache, {s, e})
            s = e
        end
    until s == nil

    s, e = 0, nil -- multiline
    repeat
        s, e = string.find(input, "%[(=-)%[.-%]%1%]", s)
        if s then
            table.insert(cache, {s, e})
            s = e
        end
    until s == nil    
    s, e = 0, nil -- comments
    repeat
        s, e = string.find(input, "%-%-[^\n]*", s)
        if s then
            table.insert(cache, {s, e})
            s = e
        end
    until s == nil
    return cache
end

local function is_block_pos_invalid(position, invalid_pos_map)
    for i,v in ipairs(invalid_pos_map) do
        local is_in = (position >= v[1]) and (position <= v[2])
        if is_in == true then
            return true
        end
    end
    return false
end

local find_frontmatter = function(input, name, arguments)
    local ppenv = setup_sandbox(name, arguments)
    name = name or "<frontmatter input>"

    local iterator, cursor
    if type(input) == "string" then
        iterator = string.gmatch(input .. "\n", ".-\n")
    elseif type(input) == "userdata" then -- File object.
        cursor = input:seek()
        input:seek("set")
        iterator = input:lines()
    else
        error("input must be a string or a file handle", 2)
    end

    local direc = {}
    for line in iterator do
        if line:match("^#!") then -- Ignore shebang.

        elseif line:match("^%s*#") then
            local line = line:gsub("^%s*##?", "")
            table.insert(direc, line)
        else -- Stop looking on any non-directive line.
            break
        end
    end
    local chunk = table.concat(direc, "\n")
    local func, err = load_func(chunk, name .. " (frontmatter)", "t", ppenv)
    if err then
        error(err,2)
    end
    func()
    return ppenv.__frontmatter
end

-- See back-defined local variable.
compile_lines = function(input, name, arguments, base_env)
    local ppenv = setup_sandbox(name, arguments, base_env)
	name = name or "<preprocessor input>"
    -- ppenv.__count = 1
    local positions_count = 0
    -- local in_string, eqs = false, ""
    local direc_lines = {}

    local iterator, cursor
    if type(input) == "string" then
        iterator = string.gmatch(input .. "\n", ".-\n")
    elseif type(input) == "userdata" then -- File object.
        cursor = input:seek()
        input:seek("set")
        iterator = input:lines()
    else
        error("input must be a string or a file handle", 2)
    end
    
    for line in iterator do
        ppenv.__count = ppenv.__count + 1
        local special_count
        if ppenv.__special_positions[ppenv.__count] then
            special_count = ppenv.__special_positions[ppenv.__count]
        else
            positions_count = positions_count + 1
        end

        line = line:gsub("\n", "")
        -- Ignore leading shebang.
        if ppenv.__count == 1 and line:match("^#!") then
            ppenv.__write_lines[ppenv.__count] = {line, 1}
            table.insert(direc_lines,("__writefromline(%d)"):format(ppenv.__count))
        elseif line:match("^%s*#")
        --   and not in_string then -- DIRECTIVES 
        then
          
            -- DOUBLE-EXPORT
            if line:match("^%s*##") then
                local line = line:gsub("^%s*##", "")

                -- write blocks (MOSTLY DUPLICATED, see below)
                -- in_string, eqs = multiline_status(line, in_string, eqs)
                ppenv.__write_lines[ppenv.__count] = {line, special_count or positions_count}
                line = line .. ("; __writefromline(%d, true)"):format(ppenv.__count)
            end

            -- Special Directives
            -- #define syntax
            line = line:gsub("^%s*#%s*define%s+([^%s()]+)%s+(.+)$", ppenv.__write_define)
            -- function-like define
            line = line:gsub("^%s*#%s*define%s+([^%s]+%b())%s+(.+)$", ppenv.__write_define)
            -- blank define
            line = line:gsub("^%s*#%s*define%s+([^%s()]+)%s*$", ppenv.__write_define)
            line = line:gsub("^%s*#%s*define%s+([^%s]+%b())%s*$", ppenv.__write_define)

            local stripped = line:gsub("^%s*##?", "")
            table.insert(direc_lines, stripped)

        else --normal lines
            line = line:gsub("^(%s*)\\(##?)", "%1%2")
            -- in_string, eqs = multiline_status(line, in_string, eqs)
            ppenv.__write_lines[ppenv.__count] = {line, special_count or positions_count}
            table.insert(direc_lines,("__writefromline(%d)"):format(ppenv.__count))
        end
    end
    if cursor then -- Reset the file position to where it was, just in case.
        input:seek("set", cursor)
    end
    
    local chunk = table.concat(direc_lines, "\n")
    -- direc_lines = {}
    local func, err = load_func(chunk, name .. " (preprocessor)", "t", ppenv)
    if err then
        error(err,2)
    end
    func()
    return ppenv
end

local function validate_type(val, desired_type, number, optional)
    if type(val) ~= desired_type then
        if not (optional and val == nil) then
            error(("expected argument [%s] to be type %s, got %s"):format(number, desired_type, type(val)), 3)
        end
    end
end

function export.fmstring(text, arguments)
    validate_type(text, "string", 1, false)
    validate_type(arguments, "table", 2, true)
    return find_frontmatter(text, nil, arguments)
end

function export.fmfile(filepath, arguments)
    validate_type(filepath, "string", 1, false)
    validate_type(arguments, "table", 2, true)
    local file, err = fs.open(filepath)
    if file == nil then
        error("could not find file '" .. filepath .. "'\n" .. err, 2)
    end
    local out = find_frontmatter(file, filepath, arguments)
    file:close()
    return out
end

function export.getstring(text, arguments)
    validate_type(text, "string", 1, false)
    validate_type(arguments, "table", 2, true)
    local out = compile_lines(text, nil, arguments)
    return table.concat(out._output, "\n"), table.concat(out._linemap, "\n")
end

function export.getfile(filepath, arguments)
    validate_type(filepath, "string", 1, false)
    validate_type(arguments, "table", 2, true)
    local file, err = fs.open(filepath)
    if file == nil then
        error("could not find file '" .. filepath .. "'\n" .. err, 2)
    end
    local out = compile_lines(file, filepath, arguments)
    file:close()
    return table.concat(out._output, "\n"), out._linemap
end

function export.writefile(input, output, arguments, write_linemap)
    validate_type(input, "string", 1, false)
    validate_type(output, "string", 2, false)
    validate_type(arguments, "table", 3, true)
    validate_type(write_linemap, "boolean", 4, true)
    local text, linemap = export.getfile(input, arguments)
    local output_handle, err = fs.open(output, "w+")
    if not output_handle then
        error("failed to open output file '" .. output .. "'\n" .. err, 2)
    end
    local linemap_handle
    if write_linemap then
        linemap_handle, err = fs.open(output .. ".linemap", "w+")
        if not linemap_handle then
            error("failed to open linemap file '" .. output .. ".linemap'\n" .. err, 2)
        end
    end
    output_handle:write(text)
    output_handle:close()
    if write_linemap then
        linemap_handle:write(table.concat(linemap, "\n"))
        linemap_handle:close()
    end
    return true
end

function export.debug_print(text, linemap)
    local count = 0
    for line in text:gmatch("([^\n]*)\n") do
        count = count + 1
        print(linemap[count] .. " |" ..  line)
    end
end

return export