--[[
    Tests for checker/version_check.lua.

    Runs the real checker in plain Lua 5.4 with stand-ins for the FiveM functions it uses
    (GetResourceMetadata, GetConvar, PerformHttpRequest, SetTimeout, json.decode, print),
    then checks what it printed and what it requested.

    Run from the repository root:
        lua tools/test/checker.test.lua
    Add --show to print every scenario's console output.
]]

local CHECKER = os.getenv('CHECKER') or 'checker/version_check.lua'
local write = io.write
local SHOW = arg and arg[1] == '--show'

---------------------------------------------------------------------------
-- Minimal JSON decoder (FiveM provides json.decode; plain Lua doesn't)

local function decode(text)
    local pos = 1
    local function skip() pos = text:find('[^ \t\r\n]', pos) or #text + 1 end
    local value
    local function err(message) error(('json: %s at %d'):format(message, pos)) end
    local function str()
        local out, i = {}, pos + 1
        while true do
            local c = text:sub(i, i)
            if c == '' then err('unterminated string') end
            if c == '"' then pos = i + 1; return table.concat(out) end
            if c == '\\' then
                local e = text:sub(i + 1, i + 1)
                local map = { b = '\b', f = '\f', n = '\n', r = '\r', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
                if e == 'u' then
                    out[#out + 1] = utf8.char(tonumber(text:sub(i + 2, i + 5), 16)); i = i + 6
                else
                    out[#out + 1] = map[e] or err('bad escape'); i = i + 2
                end
            else
                out[#out + 1] = c; i = i + 1
            end
        end
    end
    function value()
        skip()
        local c = text:sub(pos, pos)
        if c == '{' then
            local t = {}; pos = pos + 1; skip()
            if text:sub(pos, pos) == '}' then pos = pos + 1; return t end
            while true do
                skip(); local k = str(); skip()
                if text:sub(pos, pos) ~= ':' then err('expected :') end
                pos = pos + 1; t[k] = value(); skip()
                local d = text:sub(pos, pos); pos = pos + 1
                if d == '}' then return t elseif d ~= ',' then err('expected , or }') end
            end
        elseif c == '[' then
            local t = {}; pos = pos + 1; skip()
            if text:sub(pos, pos) == ']' then pos = pos + 1; return t end
            while true do
                t[#t + 1] = value(); skip()
                local d = text:sub(pos, pos); pos = pos + 1
                if d == ']' then return t elseif d ~= ',' then err('expected , or ]') end
            end
        elseif c == '"' then return str()
        elseif text:sub(pos, pos + 3) == 'true' then pos = pos + 4; return true
        elseif text:sub(pos, pos + 4) == 'false' then pos = pos + 5; return false
        elseif text:sub(pos, pos + 3) == 'null' then pos = pos + 4; return nil
        else
            local n = text:match('^-?%d+%.?%d*[eE]?[-+]?%d*', pos)
            if not n or n == '' then err('unexpected character') end
            pos = pos + #n; return tonumber(n)
        end
    end
    local result = value(); skip()
    if pos <= #text then err('trailing data') end
    return result
end

---------------------------------------------------------------------------
-- Registry documents

local function encode(v)
    local t = type(v)
    if t == 'nil' then return 'null' end
    if t == 'boolean' or t == 'number' then return tostring(v) end
    if t == 'string' then return '"' .. v:gsub('[%c"\\]', function(c) return ('\\u%04x'):format(c:byte()) end) .. '"' end
    if #v > 0 or next(v) == nil and getmetatable(v) == 'array' then
        local parts = {}
        for i = 1, #v do parts[i] = encode(v[i]) end
        return '[' .. table.concat(parts, ',') .. ']'
    end
    local parts = {}
    for k, val in pairs(v) do parts[#parts + 1] = encode(k) .. ':' .. encode(val) end
    return '{' .. table.concat(parts, ',') .. '}'
end

local function doc(overrides)
    local d = {
        schema = 2,
        slug = 'pigeon-test',
        name = 'Pigeon Test',
        status = 'active',
        latest = {
            version = '1.2.0',
            date = '2026-11-02',
            title = 'Smoother rolling',
            security = false,
            highlights = { 'First change', 'Second change', 'Third change', 'Fourth change' },
            url = 'https://github.com/WelshPigeon/pigeon-test/releases/tag/v1.2.0',
        },
        security_releases = {},
        links = { download = 'https://github.com/WelshPigeon/pigeon-test/releases/tag/v1.2.0', support = 'https://pigeonstudios.co.uk/support/' },
    }
    for k, v in pairs(overrides or {}) do
        if k == 'latest' then for lk, lv in pairs(v) do d.latest[lk] = lv end else d[k] = v end
    end
    return encode(d)
end

---------------------------------------------------------------------------
-- FiveM stand-ins

local function run(scenario)
    local output, raw, requests, timers = {}, {}, {}, {}
    local responses = scenario.responses or { { 200, doc(scenario.doc) } }

    _G.GetCurrentResourceName = function() return 'pigeon-test' end
    _G.GetResourceMetadata = function(_, key, index)
        assert(index == 0)
        local meta = scenario.meta or { version = '1.2.0', pigeon_slug = 'pigeon-test' }
        return meta[key]
    end
    _G.GetConvar = function(name, default)
        if name == 'pigeon_update_check' and scenario.convar then return scenario.convar end
        return default
    end
    _G.SetTimeout = function(ms, fn) timers[#timers + 1] = { ms = ms, fn = fn } end
    _G.PerformHttpRequest = function(url, cb, method, data, headers)
        requests[#requests + 1] = { url = url, method = method, headers = headers }
        local r = responses[#requests] or { 0, nil }
        cb(r[1], r[2], {}, r[3])
    end
    _G.json = { decode = decode }
    _G.print = function(line)
        raw[#raw + 1] = line
        -- Remove only the checker's own colour codes; anything else would be registry text that slipped through.
        output[#output + 1] = (line:gsub('^%^6%[Pigeon Studios%]%^7 ', '[Pigeon Studios] '):gsub('^(%[Pigeon Studios%] )%^[1235]', '%1'):gsub('%^7$', ''))
    end

    dofile(CHECKER)
    local i = 1
    while timers[i] do timers[i].fn(); i = i + 1 end

    return table.concat(output, '\n'), requests, timers
end

---------------------------------------------------------------------------
-- Scenarios

local passed, failed = 0, 0

local function test(name, scenario, expect)
    local out, requests, timers, raw = run(scenario)
    local problems = {}
    for _, needle in ipairs(expect.contains or {}) do
        if not out:find(needle, 1, true) then problems[#problems + 1] = 'missing: ' .. needle end
    end
    for _, needle in ipairs(expect.excludes or {}) do
        if out:find(needle, 1, true) then problems[#problems + 1] = 'unexpected: ' .. needle end
    end
    if expect.silent and out ~= '' then problems[#problems + 1] = 'expected no output' end
    if expect.requests and #requests ~= expect.requests then
        problems[#problems + 1] = ('expected %d request(s), made %d'):format(expect.requests, #requests)
    end
    if expect.lines and select(2, out:gsub('\n', '')) + (out == '' and 0 or 1) ~= expect.lines then
        problems[#problems + 1] = ('expected %d line(s)'):format(expect.lines)
    end
    if expect.check then
        local ok, message = pcall(expect.check, out, requests, timers, raw)
        if not ok then message = 'check crashed: ' .. tostring(message) end
        if message then problems[#problems + 1] = message end
    end

    if #problems == 0 then
        passed = passed + 1
        io.write(('  \27[32mpass\27[0m  %s\n'):format(name))
    else
        failed = failed + 1
        io.write(('  \27[31mFAIL\27[0m  %s\n'):format(name))
        for _, p in ipairs(problems) do io.write('          ' .. p .. '\n') end
    end
    if SHOW or #problems > 0 then
        for line in (out .. '\n'):gmatch('(.-)\n') do io.write('        | ' .. line .. '\n') end
    end
end

local function meta(version, slug) return { version = version, pigeon_slug = slug or 'pigeon-test' } end

write('Pigeon Studios update checker tests\n')

test('up to date: one green line', {}, {
    contains = { 'Pigeon Test v1.2.0 is up to date.' }, lines = 1, requests = 1,
    check = function(_, requests)
        local r = requests[1]
        if r.url ~= 'https://raw.githubusercontent.com/WelshPigeon/pigeon-versions/main/api/v2/pigeon-test.json' then return 'wrong URL: ' .. r.url end
        if r.method ~= 'GET' then return 'expected GET' end
        if not r.headers['User-Agent']:match('^PigeonStudios%-UpdateChecker/') then return 'missing User-Agent' end
    end,
})

test('update available: headline, title, three highlights, link', { meta = meta('1.1.2') }, {
    contains = { 'Update available for Pigeon Test: v1.1.2 -> v1.2.0 (released 2026-11-02)', 'Smoother rolling', '- First change', '- Third change', 'Get it: https://github.com/WelshPigeon/pigeon-test/releases/tag/v1.2.0' },
    excludes = { 'Fourth change', 'Security' }, lines = 6,
})

test('security fix in a newer release', { meta = meta('1.0.0'), doc = { security_releases = { '1.1.0' } } }, {
    contains = { 'Security update available for Pigeon Test: v1.0.0 -> v1.2.0', 'fixes a security problem' },
})

test('security fix only in an older release than installed', { meta = meta('1.1.5'), doc = { security_releases = { '1.1.0' } } }, {
    contains = { 'Update available for Pigeon Test' }, excludes = { 'Security' },
})

test('below minimum version', { meta = meta('0.9.0'), doc = { minimum_version = '1.0.0' } }, {
    contains = { 'Important update available', 'v0.9.0 is no longer supported' },
})

test('development build newer than release', { meta = meta('1.3.0-dev.2') }, {
    contains = { 'v1.3.0-dev.2 is a development build (latest release: v1.2.0)' }, lines = 1,
})

test('pre-release older than its release', { meta = meta('1.2.0-beta.3') }, {
    contains = { 'Update available for Pigeon Test: v1.2.0-beta.3 -> v1.2.0' },
})

test('pre-release ordering: beta.11 is newer than beta.2', { meta = meta('2.0.0-beta.11'), doc = { latest = { version = '2.0.0-beta.2' } } }, {
    contains = { 'development build' },
})

test('pre-release ordering: alpha before beta', { meta = meta('2.0.0-alpha'), doc = { latest = { version = '2.0.0-beta' } } }, {
    contains = { 'Update available' },
})

test('build metadata is ignored', { meta = meta('1.2.0+build.7') }, { contains = { 'is up to date' } })

test('leading v and two-part versions', { meta = meta('v1.2') }, { contains = { 'is up to date' } })

test('numeric comparison, not text (1.10.0 > 1.9.0)', { meta = meta('1.9.0'), doc = { latest = { version = '1.10.0' } } }, {
    contains = { 'Update available' },
})

test('deprecated with notice', { doc = { status = 'deprecated', notice = 'Use Pigeon Dice 2 instead.' } }, {
    contains = { 'Pigeon Test is deprecated.', 'Use Pigeon Dice 2 instead.', 'is up to date' },
})

test('discontinued with notice', { meta = meta('1.0.0'), doc = { status = 'discontinued', notice = 'No longer supported.' } }, {
    contains = { 'Pigeon Test is discontinued', 'No longer supported.', 'Update available' },
})

test('general notice on an active resource', { doc = { notice = 'Version 2 is coming soon.' } }, {
    contains = { 'Version 2 is coming soon.' },
})

test('colour codes and control characters in registry text are stripped', { meta = meta('1.0.0'), doc = { latest = { title = '^1Red^7 title\nsecond line' } } }, {
    contains = { 'Red title second line' }, excludes = { '^1', '\nsecond line' },
})

test('very long registry text is shortened', { meta = meta('1.0.0'), doc = { latest = { highlights = { string.rep('x', 400) } } } }, {
    check = function(out) for line in out:gmatch('[^\n]+') do if #line > 200 then return 'line too long: ' .. #line end end end,
})

test('not in the registry (404)', { responses = { { 404, nil, 'HTTP 404' } } }, {
    contains = { '"pigeon-test" isn\'t in the version registry' }, requests = 1,
})

test('GitHub unreachable: retries once after 60 seconds, then one calm line', { responses = { { 0, nil }, { 0, nil } } }, {
    contains = { 'Couldn\'t check for updates (no connection). The resource works normally.' }, requests = 2, lines = 1,
    check = function(_, _, timers)
        if not timers[2] then return 'no retry was scheduled' end
        if timers[2].ms ~= 60000 then return 'retry delay should be 60000 ms, was ' .. tostring(timers[2].ms) end
    end,
})

test('server error then success on retry', { responses = { { 503, nil }, { 200, doc() } } }, {
    contains = { 'is up to date' }, excludes = { 'Couldn\'t' }, requests = 2,
})

test('start is delayed 2 to 6 seconds', {}, {
    check = function(_, _, timers)
        local ms = timers[1].ms
        if ms < 2000 or ms > 6000 then return 'start delay out of range: ' .. ms end
    end,
})

test('invalid JSON', { responses = { { 200, '{not json' } } }, { contains = { 'couldn\'t be read' } })

test('newer registry schema than this checker understands', { responses = { { 200, '{"schema":3}' } } }, {
    contains = { 'too old to read the registry' },
})

test('missing latest version in registry', { responses = { { 200, '{"schema":2,"name":"Pigeon Test","latest":{}}' } } }, {
    contains = { 'couldn\'t be read' },
})

test('missing version in fxmanifest', { meta = { pigeon_slug = 'pigeon-test' } }, {
    contains = { 'needs a version such as' }, requests = 0,
})

test('invalid version in fxmanifest', { meta = meta('latest') }, {
    contains = { 'needs a version such as', '"latest"' }, requests = 0,
})

test('missing pigeon_slug in fxmanifest', { meta = { version = '1.0.0' } }, {
    contains = { 'needs pigeon_slug' }, requests = 0,
})

test('convar off: no request, no output', { convar = 'off' }, { silent = true, requests = 0 })

test('convar quiet + up to date: silent', { convar = 'quiet' }, { silent = true, requests = 1 })

test('convar quiet + update: prints', { convar = 'quiet', meta = meta('1.0.0') }, { contains = { 'Update available' } })

test('convar quiet + unreachable: silent', { convar = 'QUIET', responses = { { 0, nil }, { 0, nil } } }, { silent = true, requests = 2 })

test('every line is prefixed or indented consistently', { meta = meta('1.0.0') }, {
    check = function(out)
        for line in out:gmatch('[^\n]+') do
            if not (line:match('^%[Pigeon Studios%] ') or line:match('^                 %S')) then return 'badly formatted line: ' .. line end
        end
    end,
})

test('no globals leak from the checker', {}, {
    check = function()
        for _, name in ipairs({ 'parseVersion', 'compareVersions', 'check', 'report', 'say', 'clean' }) do
            if rawget(_G, name) ~= nil then return 'global leaked: ' .. name end
        end
    end,
})

write(('\n%d passed, %d failed\n'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
