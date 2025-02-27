# preprocess.lua
A portable language-agnostic file preprocessor written in plain Lua and compatible with all major versions of (5.1+ and JIT). While it's designed primarily for use as a metaprogramming tool for Lua programs, it can be used for writing other document types as well. 

The preprocessor is primarily built around a robust macro expansion system. Advanced utilities for expanding the preprocessor's available behavior may be added in the fututre.

Originally created for [Luxtre](https://github.com/DimitriBarronmore/luxtre), and now featuring substantial improvements over the initial version.

# Usage

## As a standalone tool.

> NOTE: This only works properly on UNIX systems due to a hard dependency on the UNIX "file", "find" and "mkdir" commands and an expectation that the current file separator is "/". It might work on Windows under WSL, but I haven't tried it. If you're not on a system which supports this, you'll likely need to write your own build scripts in Lua.

If you want to use the utility from any directory, place **preprocess.lua** on your Lua PATH, and **preprocess_c.lua** on your system PATH. Otherwise, place them in the directory you intend to run the tool from. If you wish, you can rename **preprocess_c.lua** to something more appropriate.

You can then invoke the command-line utility as so:

```bash
preprocess_c.lua [options] [filenames]
OR
lua preprocess_c.lua [options] [filenames]
```

Invoking the utility without giving it any filenames or while passing the `-h` / `--help` flags will show the available options.

## As a Lua library.

Import the library as a single Lua file.

```lua
preprocess = require "preprocess"
```

The library exposes the following functions:
```lua
--- Takes in a string and an optional table of values to populate the preprocessor with.
--- Efficiently returns a table containing the file's metadata, or false if there is none.
metadata = preprocess.fmstring(text, arguments)

--- Takes in a path to a file and an optional table of values to populate the preprocessor with.
--- Efficiently returns a table containing the file's metadata, or false if there is none.
metadata = preprocess.fmfile(filepath, arguments)

--- Takes in a string and an optional table of values to populate the preprocessor with.
--- Returns a string output and an array of the source locations of each line.
text, linemap = preprocess.getstring(text, arguments)

--- Takes in a path to a file and an optional table of values to populate the preprocessor with.
--- Returns a string output and an array of the source locations of each line.
text, linemap = preprocess.getfile(filepath, arguments)

--- Takes in a path to an input file, a path to an output file, an optional table of values
--- to populate the preprocessor with, and a boolean flag.
--- Processes the input file, and saves the result to the output file.
--- If write_linemap == true, it saves a file "<output>.linemap" wherein each line is the
--- source location of the respective line in the output file.
preprocess.writefile(input, output, arguments, write_linemap)

-- Takes in a string and a linemap table as returned from getstring() or getfile().
-- Prints the string with the linemap values for each line prepended.
preprocess.debug_print(text, linemap)
```

# Preprocessing

Lines in the input file which begin with '#' (ignoring trailing whitespace and shebangs) are executed by the preprocessor as sandboxed Lua code.

Lines beginning with '##' are both run as preprocessor code and exported verbatim to the output, which is occasionally useful for setting constant values in both the output code and the preprocessor when metaprogramming Lua code.

If you need to have lines beginning with one or more #, such as writing a multiline string or as Markdown headings, you can escape the preprocessor with a single backslash as so:

```
--- Lua ---
local str = [[
    \# Line with a hash.
]]

--- Markdown ---
\# Heading 1
\## Heading 2
\### Heading 3
```

## Included Functions and Variables.

Within the sandbox, preprocessor code has access to the following standard functions and variables:
```lua
coroutine.*  io.*     math.*       string.*  table.*
os.clock     os.date  os.difftime  os.time   assert
error        ipairs   next         pairs     pcall
print        select   tonumber     tostring  type
unpack       xpcall   _VERSION
```

The sandbox also has access to the following non-standard functions and variables:

- `write(line)`: Inserts the given argument `line` as a line in the output file.

- `include(filename, arguments)`: Runs `filename` through the current preprocessor using the given `arguments` table, and inserts the result into the output file. See [Including Files](#including-files).

- `macros`: A special table which controls the preprocessor's macro system. See [Macros](#macros).

- `filename`: the full path of the current file as used to load it, or an empty string if the input came from loading a string.
    - for example:  `print(filename) --> folder/example.lua`

- `frontmatter(table)`: A special function used for handling external file metadata usable by advanced build tools. See [Frontmatter](#frontmatter).

Arguments provided to the preprocessor through the `arguments` parameters in the Lua API or through the command-line utility are exposed to the sandbox environment as standard Lua values. Be careful not to overwrite important values with preprocessor arguments.

### Special Flags

If an argument named `silent` is given to the preprocessor sandbox as `true`, then print statements from the preprocessor will be silenced.

If an argument named `__setup_sandbox` which is a Lua function is given to the preprocessor sandbox, at the end of the sandbox initialization process this function will be run with the sandbox as the sole argument. This can be used to expand the sandbox with new functions.

## Frontmatter

Advanced build scripts may wish to gather metadata about a file before it's actually compiled. Rather than futz about with standard YAML frontmatter, the preprocessor allows metadata to be written using the `frontmatter(table)` function.

```lua
# frontmatter {
#   foo = "bar",
#   apples = "oranges",
# }
```

The `frontmatter` function is special in that it must be called before any lines are written to the output, can only be called once, and cannot be called in any file being `include`ed in another file (See [Including Files](#including-files)).

All values in the table given to `frontmatter` must be primitive Lua types, which is to say booleans, numbers, strings, or tables containing only other primitive types. Metadata cannot include functions, coroutines, or userdata. Tables may have metatables, but may not have a __call metamethod.

Each value in `table` will be added to the preprocessor sandbox environment.

The `fmstring` and `fmfile` functions in the Lua API will attempt to retrieve only the file metadata as efficiently as possible. In order to do this, they will stop executing at the first line in the input which does not begin with '#' or '##'. In some cases this may not be enough. You can also force the search to end early by including a preprocessor line which contains only whitespace and a triple-dash.

```lua
# frontmatter = { ... }
# print("This will run when pulling metadata.")
# ---
# print("But this will not.")
```

## Conditional Lines

Within an unclosed preprocessor block (`do`, `if`, `while`, `repeat`, `for`, or inside function definitions), input lines will only be written to the output dependent on the surrounding preprocessor code. 
For example:
```lua
--- Conditionals:

# local hello = false
# if hello then
    print("hello world")
# else
    print("goodbye world")
# end

--- output ---
    print("goodbye world")
--- end output ---

--- Loops:

print(
# local count = 0
# repeat
# 	count = count + 1
	"the end is never " .. 
# until count == 10
"" )

--- output ---
print(
     "the end is never " .. 
     "the end is never " .. 
     "the end is never " .. 
     "the end is never " .. 
     "the end is never " .. 
     "the end is never " .. 
     "the end is never " .. 
     "the end is never " .. 
     "the end is never " .. 
     "the end is never " .. 
"" )
--- end output ---

--- Functions:

# function write_line()
print("hello world")
# end
# write_line()
print("something in the middle")
# write_line()

--- output ---
print("hello world")
print("something in the middle")
print("hello world")
-- end output ---

```

## Macros
Macros can be defined as string-keyed values in the preprocessor environment's `macros` table. There are three types of macro: simple, function-like, and callback.

Every currently defined macro is evaluated over each input line in sequence, in the order they were originally added. Multiple macros can run into each other if the output of one macro is the input of a different macro.

```lua
-- Simple macros are simply a string key and a primitive result.
-- The result can be a string, a number, or a boolean.
-- When the string key is found, it's replaced with the result.
# macros.constant = "1000"
print(constant) --> print(1000)

-- Non-standard characters also work.
# macros["😂"] = ":joy:"
print("😂") --> print(":joy:")

-- The result of a macro doesn't need to be constant. This is also a valid macro.
-- In this case, the value will change each time the file is processed.
# macros.RANDOM = math.random(1, 100)

-- Multiple macros can run into each other if defined in the correct order. Be careful.
# macros.MAC1 = "MAC2"
# macros.MAC2 = "MAC3"
print("MAC1") --> print("MAC3")


-- Function-like macros are written with parenthesized arguments in the key.
-- The argument names in the output string will be replaced with the discovered
-- parenthesized arguments in the input, or with empty space.
# macros["reverse(arg1, arg2)"] = "arg2 arg1"
print("reverse(world, hello)") --> print("hello world")
print("reverse(foo)") --> print(" foo")

-- Function-like macros support '...' as a catch-all last argument, similar to real Lua functions.
-- The arguments collected are separated by a comma and a space, for use in function calls.
# macros["discardfirst(first, ...)"] = "..."
print(discardfirst(1,2,3)) --> print(2, 3)


-- Callback macros are Lua functions defined and executed entirely in the preprocessor.
-- The parenthesized arguments in the source file are copied verbatim into the function call.
-- This means literals and expressions can be used, and preprocessor variables can be referenced.
-- The return value of the function is cast to a string and replaces the original text.
# macros["$"] = function(...)
# 	return ...
# end
# example_msg = "hi there"
print( "$(example_msg)" ) --> print( "hi there" )

-- Callback macros can be extremely useful for evaluating inline expressions at compile time.
-- If a callback macro returns multiple values, they're inserted into the text separated by commas.
print( "$("hello " .. "world")" ) --> print( "hello world" )
tab = { $( 200 * 100, 200 / 100) } --> tab = { 20000, 2.0 }


-- All macros will delete themselves from the input if they return an empty string.
-- Callback macros will also delete themselves if they return nil.
# macros["<blank>"] = ""
print(<blank>) --> print()

-- This can be useful when combined with conditional logic. For example, you can write code
-- to the output only if a DEBUG flag is passed to the preprocessor.
# if DEBUG == true then
#   macros["log(...)"] = "print(...)"
# else
#   macros["log(...)"] = ""
# end


-- Simple and Function-Like macros can be defined more easily with C-like syntax sugar.
-- #define <name>[parens] <result>
# define fizzbuzz "1 2 fizz 4 buzz fizz 7 8 fizz buzz"
# define add_bark(arg) bark arg bark
# define blank

print(fizzbuzz)         --> print("1 2 fizz 4 buzz fizz 7 8 fizz buzz")
print("add_bark(woof)") --> print("bark woof bark")
print(blank)            --> print()
```

## Including Files
You can insert the contents of another file into the current one using the `include(filename, arguments)` function. This will immediately run the file `filename` through the same preprocessor environment and write the result into the output file. If an `arguments` table is provided, those arguments will only apply to the included file.

The filepath given to `include` is parsed relative to the current file.

```lua
--- test/header.lua ---
print("abra cadabra")
# define apple orange

--- test/main.lua ---
print("apple")
# include "header.txt"
print("apple")

--- output ---
print("apple")
print("abra cadabra")
print("orange")
--- end output ---
```