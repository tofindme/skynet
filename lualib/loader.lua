
--[[
LUA_SERVICE package.path : 约定扩展名都是 .lua

改动：
    1. 新增
    在默认Lua loader前增加了一个新loader，新loader读取
    package.path中的路径，并假定其每一项都是 .lua 结尾的，
    然后修改.lua为 .p.lua, 先用gcc预处理，保存到 .pp.lua文件后使用loadfile加载

    2. 修改
    修改了服务的加载方式，在原服务的搜索路径，优先检查.p.lua文件。

注意：
    普通lua文件的加载并没有改动；loadfile 也没有被替换;
    预处理后的文件也都使用了云风修改过的loadfile加载

note:
    用Lua实现简单地预处理功能，替换对gcc的调用
    也可以让预处理loader读自己的选项，不依赖package.path和.lua扩展名

Mon 14:42 Apr 11

--]]

local gcc_preprocess_cmd = 'gcc -w -C -P -E -xc '

--- this function should return
-- ok:   func, path
-- fail: nil | err_msg
local function p_lua_loader(module_name)
    local p_lua_path = package.path:gsub('(%.lua);','.p.lua;'):gsub('(%.lua)$','.p.lua')

    local path, err = package.searchpath(module_name, p_lua_path)
    if path then
        local new_filename = path:gsub('(%.p%.lua)$', '.pp.lua')
        local pf = io.open(new_filename, 'wb')
        if pf then
            local of = io.popen(gcc_preprocess_cmd .. path, 'r')
            pf:write(of:read('a'))
            of:close()
            pf:close()
            local f, le = loadfile(new_filename)
            if not f then
                return le
            end
            return f, new_filename
        else
            local f, e = loadfile(path)
            if not f then
                return e
            end
            return f, path
        end
    else
        return err
    end
end

-- insert a new lua loader before the default lua loader
table.insert(package.searchers, 2, p_lua_loader)

local function pp_loadfile(filename)
    local tf = io.open(filename, 'rb')
    if tf then
        tf:close()

        local ppf, n = filename:gsub('(%.p%.lua)$', '.pp.lua')
        assert(n == 1)
        local pf = io.open(ppf, 'wb')
        if pf then
            local of = io.popen(gcc_preprocess_cmd .. filename, 'r')
            pf:write(of:read('a'))
            of:close()
            pf:close()
            return loadfile(ppf)
        else
            return loadfile(filename)
        end
    end
end

local args = {}
for word in string.gmatch(..., "%S+") do
	table.insert(args, word)
end

SERVICE_NAME = args[1]
local main, pattern

local err = {}
for pat in string.gmatch(LUA_SERVICE, "([^;]+);*") do
    local filename = string.gsub(pat, "?", SERVICE_NAME)
    local pfilename = filename:gsub('(%.lua)$', '.p.lua')
    local f = pp_loadfile(pfilename)
    if f then
        pattern = pat
        main = f
        break
    else
        local f, msg = loadfile(filename)
        if f then
            pattern = pat
            main = f
            break
        end
        table.insert(err, msg)
    end
end

if not main then
	error(table.concat(err, "\n"))
end

LUA_SERVICE = nil
package.path , LUA_PATH = LUA_PATH
package.cpath , LUA_CPATH = LUA_CPATH

local service_path = string.match(pattern, "(.*/)[^/?]+$")

if service_path then
	service_path = string.gsub(service_path, "?", args[1])
	package.path = service_path .. "?.lua;" .. package.path
	SERVICE_PATH = service_path
else
	local p = string.match(pattern, "(.*/).+$")
	SERVICE_PATH = p
end

if LUA_PRELOAD then
	local f = assert(loadfile(LUA_PRELOAD))
	f(table.unpack(args))
	LUA_PRELOAD = nil
end

main(select(2, table.unpack(args)))
