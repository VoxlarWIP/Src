local Util = {}

function Util.NewRNG(seed)
    local state = seed or (os.clock() * 1e9) % 0xFFFFFFFF
    if state == 0 then state = 0xDEADBEEF end
    return {
        Next = function(self, lo, hi)
            state = bit32.bxor(state, bit32.lshift(state, 13))
            state = bit32.bxor(state, bit32.rshift(state, 17))
            state = bit32.bxor(state, bit32.lshift(state, 5))
            state = state % 0xFFFFFFFF
            if lo and hi then
                return lo + (state % (hi - lo + 1))
            end
            return state
        end,
        Choice = function(self, t)
            return t[self:Next(1, #t)]
        end,
        Shuffle = function(self, t)
            for i = #t, 2, -1 do
                local j = self:Next(1, i)
                t[i], t[j] = t[j], t[i]
            end
            return t
        end,
        Float = function(self)
            return (self:Next() % 100000) / 100000
        end,
    }
end

function Util.NewIdentGen(rng, prefix)
    prefix = prefix or "_"
    local used = {}


    local CONFUSE_CHARS = {"l","I","1","O","0","o","i"}
    local ALPHA = {"a","b","c","d","e","f","g","h","i","j","k","l","m",
                   "n","o","p","q","r","s","t","u","v","w","x","y","z",
                   "A","B","C","D","E","F","G","H","I","J","K","L","M",
                   "N","O","P","Q","R","S","T","U","V","W","X","Y","Z"}
    local ALNUM = {}
    for _,v in ipairs(ALPHA) do table.insert(ALNUM, v) end
    for i=0,9 do table.insert(ALNUM, tostring(i)) end

    local function gen(len, style)
        len = len or rng:Next(8, 18)
        local chars
        if style == "confuse" then
            chars = CONFUSE_CHARS
        else
            chars = ALNUM
        end

        local first = rng:Choice(ALPHA)
        local buf = {prefix, first}
        for _=1, len do
            table.insert(buf, rng:Choice(chars))
        end
        return table.concat(buf)
    end

    return {
        Get = function(self, style)
            local id
            local tries = 0
            repeat
                id = gen(rng:Next(6, 16), style or "confuse")
                tries = tries + 1
                if tries > 1000 then
                    id = id .. tostring(rng:Next(0, 99999))
                    break
                end
            until not used[id]
            used[id] = true
            return id
        end,
    }
end

function Util.EncodeString(s, xorKey)
    local parts = {}
    for i = 1, #s do
        local b = string.byte(s, i)
        if xorKey then
            b = bit32.bxor(b, xorKey)
        end
        table.insert(parts, tostring(b))
    end
    return parts
end

function Util.DecodeExpr(encodedTable, xorKey, strcharName, tableconcatName)


    if xorKey then
        return string.format(
            "(function(t,k)local r={}for i=1,#t do r[i]=string.char(bit32.bxor(t[i],k))end return table.concat(r)end)(%s,%d)",
            encodedTable, xorKey
        )
    else
        return string.format(
            "(function(t)local r={}for i=1,#t do r[i]=string.char(t[i])end return table.concat(r)end)(%s)",
            encodedTable
        )
    end
end

function Util.ObfuscateNumber(n, rng)
    if type(n) ~= "number" or n ~= n or math.abs(n) == math.huge then
        return tostring(n)
    end

    if n == math.floor(n) and math.abs(n) < 1e9 then
        local strategies = {

            function()
                local a = rng:Next(0, math.min(math.abs(math.floor(n)), 1000))
                local b = n - a
                return string.format("(%d+%d)", a, b)
            end,

            function()
                if n ~= 0 and math.abs(n) < 10000 then
                    local f = 2
                    local abs_n = math.abs(math.floor(n))
                    if abs_n > 1 then
                        while f * f <= abs_n do
                            if abs_n % f == 0 then
                                local q = abs_n // f
                                if n < 0 then
                                    return string.format("(-(%d*%d))", f, q)
                                end
                                return string.format("(%d*%d)", f, q)
                            end
                            f = f + 1
                        end
                    end
                end
                return nil
            end,

            function()
                if n >= 0 and n < 65536 then
                    local mask = rng:Next(0, 255)
                    local a = bit32.bxor(n, mask)
                    return string.format("bit32.bxor(%d,%d)", a, mask)
                end
                return nil
            end,
        }
        rng:Shuffle(strategies)
        for _, strat in ipairs(strategies) do
            local result = strat()
            if result then return result end
        end
    end
    return tostring(n)
end

function Util.Checksum(s)
    local h = 5381
    for i = 1, #s do
        h = bit32.bxor(bit32.lshift(h, 5) + h, string.byte(s, i))
        h = h % 0xFFFFFFFF
    end
    return h
end

function Util.Split(s, sep)
    local t = {}
    local pattern = "([^" .. sep .. "]*)" .. sep .. "?"
    for chunk in s:gmatch("([^"..sep.."]+)") do
        table.insert(t, chunk)
    end
    return t
end

function Util.Trim(s)
    return s:match("^%s*(.-)%s*$")
end

function Util.DeepCopy(orig)
    local t = type(orig)
    local copy
    if t == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[Util.DeepCopy(k)] = Util.DeepCopy(v)
        end
        setmetatable(copy, getmetatable(orig))
    else
        copy = orig
    end
    return copy
end

local Lexer = {}

Lexer.TK = {

    NAME    = "NAME",
    NUMBER  = "NUMBER",
    STRING  = "STRING",
    RAWSTR  = "RAWSTR",


    AND="AND",BREAK="BREAK",DO="DO",ELSE="ELSE",ELSEIF="ELSEIF",
    END="END",FALSE="FALSE",FOR="FOR",FUNCTION="FUNCTION",GOTO="GOTO",
    IF="IF",IN="IN",LOCAL="LOCAL",NIL="NIL",NOT="NOT",
    OR="OR",REPEAT="REPEAT",RETURN="RETURN",THEN="THEN",TRUE="TRUE",
    UNTIL="UNTIL",WHILE="WHILE",

    TYPE="TYPE", EXPORT="EXPORT", CONTINUE="CONTINUE",


    PLUS="+",MINUS="-",STAR="*",SLASH="/",DOUBLESLASH="//",
    PERCENT="%",CARET="^",HASH="#",AMP="&",TILDE="~",PIPE="|",
    LSHIFT="<<",RSHIFT=">>",EQ="==",NEQ="~=",LT="<",LE="<=",
    GT=">",GE=">=",ASSIGN="=",LPAREN="(",RPAREN=")",
    LBRACE="{",RBRACE="}",LBRACKET="[",RBRACKET="]",
    SEMICOL=";",COLON=":",DOUBLECOLON="::",COMMA=",",
    DOT=".",DOTDOT="..",DOTDOTDOT="...",
    ARROW="->",


    EOF = "EOF",
    COMMENT = "COMMENT",
}

local KEYWORDS = {
    ["and"]=true,["break"]=true,["do"]=true,["else"]=true,
    ["elseif"]=true,["end"]=true,["false"]=true,["for"]=true,
    ["function"]=true,["goto"]=true,["if"]=true,["in"]=true,
    ["local"]=true,["nil"]=true,["not"]=true,["or"]=true,
    ["repeat"]=true,["return"]=true,["then"]=true,["true"]=true,
    ["until"]=true,["while"]=true,

    ["type"]=true,["export"]=true,["continue"]=true,
}

function Lexer.Tokenize(source)
    local tokens = {}
    local i = 1
    local line = 1
    local len = #source

    local function peek(offset)
        offset = offset or 0
        return source:sub(i + offset, i + offset)
    end
    local function peeks(n)
        return source:sub(i, i + n - 1)
    end
    local function advance(n)
        n = n or 1
        for _=1,n do
            if source:sub(i,i) == "\n" then line = line + 1 end
            i = i + 1
        end
    end
    local function addtok(kind, value, raw)
        table.insert(tokens, {kind=kind, value=value, raw=raw or value, line=line})
    end
    local function err(msg)
        error("[Perplex Lexer] Line " .. line .. ": " .. msg)
    end


    local function readLongString(level)
        local close = "]" .. string.rep("=", level) .. "]"
        local start = i
        local buf = {}
        while i <= len do
            if source:sub(i, i + #close - 1) == close then
                advance(#close)
                return table.concat(buf)
            end
            local c = source:sub(i,i)
            table.insert(buf, c)
            advance()
        end
        err("Unfinished long string")
    end


    local function readString(quote)
        advance()
        local buf = {}
        while i <= len do
            local c = peek()
            if c == quote then advance(); break end
            if c == "\\" then
                advance()
                local esc = peek()
                advance()
                local escapes = {
                    n="\n", t="\t", r="\r", ["\\"]="\\",
                    ["'"]="'", ['"']='"', ["0"]="\0",
                    a="\a", b="\b", f="\f", v="\v",
                }
                if escapes[esc] then
                    table.insert(buf, escapes[esc])
                elseif esc:match("%d") then
                    local nums = esc
                    for _=1,2 do
                        if peek():match("%d") then
                            nums = nums .. peek(); advance()
                        end
                    end
                    table.insert(buf, string.char(tonumber(nums)))
                elseif esc == "x" then
                    local h = peeks(2); advance(2)
                    table.insert(buf, string.char(tonumber(h, 16)))
                elseif esc == "u" then

                    if peek() == "{" then
                        advance()
                        local h = ""
                        while peek() ~= "}" do h = h .. peek(); advance() end
                        advance()

                        local cp = tonumber(h, 16) or 0

                        if cp < 0x80 then
                            table.insert(buf, string.char(cp))
                        elseif cp < 0x800 then
                            table.insert(buf, string.char(
                                bit32.bor(0xC0, bit32.rshift(cp,6)),
                                bit32.bor(0x80, bit32.band(cp,0x3F))
                            ))
                        else

                            table.insert(buf, "\\u{"..h.."}")
                        end
                    end
                elseif esc == "z" then

                    while peek():match("%s") do advance() end
                elseif esc == "\n" or esc == "\r" then
                    table.insert(buf, "\n")
                    if esc == "\r" and peek() == "\n" then advance() end
                else

                    table.insert(buf, "\\" .. esc)
                end
            elseif c == "\n" or c == "\r" then
                err("Unfinished string at line " .. line)
            else
                table.insert(buf, c)
                advance()
            end
        end
        return table.concat(buf)
    end

    while i <= len do
        local c = peek()


        if c:match("%s") then
            advance()


        elseif peeks(2) == "--" then
            advance(2)

            if peek() == "[" then
                local lvl = 0
                local j = i + 1
                while source:sub(j,j) == "=" do lvl = lvl + 1; j = j + 1 end
                if source:sub(j,j) == "[" then
                    advance(lvl + 2)
                    local content = readLongString(lvl)
                    addtok(Lexer.TK.COMMENT, content, "--[" .. string.rep("=",lvl) .. "[" .. content .. "]" .. string.rep("=",lvl) .. "]")
                else

                    local buf = {}
                    while i <= len and peek() ~= "\n" do
                        table.insert(buf, peek()); advance()
                    end
                    addtok(Lexer.TK.COMMENT, table.concat(buf), "--"..table.concat(buf))
                end
            else
                local buf = {}
                while i <= len and peek() ~= "\n" do
                    table.insert(buf, peek()); advance()
                end
                addtok(Lexer.TK.COMMENT, table.concat(buf), "--"..table.concat(buf))
            end


        elseif c == "[" then
            local lvl = 0
            local j = i + 1
            while source:sub(j,j) == "=" do lvl = lvl + 1; j = j + 1 end
            if source:sub(j,j) == "[" then
                advance(lvl + 2)
                local content = readLongString(lvl)
                local raw = "[" .. string.rep("=",lvl) .. "[" .. content .. "]" .. string.rep("=",lvl) .. "]"
                addtok(Lexer.TK.RAWSTR, content, raw)
            else
                addtok(Lexer.TK.LBRACKET, "["); advance()
            end


        elseif c == '"' or c == "'" then
            local raw_start = i
            local value = readString(c)
            local raw = source:sub(raw_start, i - 1)
            addtok(Lexer.TK.STRING, value, raw)


        elseif c:match("%d") or (c == "." and peek(1):match("%d")) then
            local start = i

            if c == "0" and (peek(1) == "x" or peek(1) == "X") then
                advance(2)
                while peek():match("[%x_]") do advance() end

                if peek() == "." then
                    advance()
                    while peek():match("[%x_]") do advance() end
                end
                if peek():lower() == "p" then
                    advance()
                    if peek() == "+" or peek() == "-" then advance() end
                    while peek():match("%d") do advance() end
                end
            else
                while peek():match("[%d_]") do advance() end
                if peek() == "." and peek(1) ~= "." then
                    advance()
                    while peek():match("[%d_]") do advance() end
                end
                if peek():lower() == "e" then
                    advance()
                    if peek() == "+" or peek() == "-" then advance() end
                    while peek():match("%d") do advance() end
                end
            end
            local raw = source:sub(start, i-1)

            local cleaned = raw:gsub("_","")
            addtok(Lexer.TK.NUMBER, tonumber(cleaned) or 0, raw)


        elseif c:match("[%a_]") then
            local start = i
            while peek():match("[%w_]") do advance() end
            local word = source:sub(start, i-1)
            if KEYWORDS[word] then
                addtok(word:upper(), word, word)
            else
                addtok(Lexer.TK.NAME, word, word)
            end


        elseif c == "." then
            if peeks(3) == "..." then addtok(Lexer.TK.DOTDOTDOT, "..."); advance(3)
            elseif peeks(2) == ".." then addtok(Lexer.TK.DOTDOT, ".."); advance(2)
            else addtok(Lexer.TK.DOT, "."); advance()
            end
        elseif c == "=" then
            if peeks(2) == "==" then addtok(Lexer.TK.EQ,"=="); advance(2)
            else addtok(Lexer.TK.ASSIGN,"="); advance()
            end
        elseif c == "<" then
            if peeks(2) == "<=" then addtok(Lexer.TK.LE,"<="); advance(2)
            elseif peeks(2) == "<<" then addtok(Lexer.TK.LSHIFT,"<<"); advance(2)
            else addtok(Lexer.TK.LT,"<"); advance()
            end
        elseif c == ">" then
            if peeks(2) == ">=" then addtok(Lexer.TK.GE,">="); advance(2)
            elseif peeks(2) == ">>" then addtok(Lexer.TK.RSHIFT,">>"); advance(2)
            else addtok(Lexer.TK.GT,">"); advance()
            end
        elseif c == "~" then
            if peeks(2) == "~=" then addtok(Lexer.TK.NEQ,"~="); advance(2)
            else addtok(Lexer.TK.TILDE,"~"); advance()
            end
        elseif c == ":" then
            if peeks(2) == "::" then addtok(Lexer.TK.DOUBLECOLON,"::"); advance(2)
            else addtok(Lexer.TK.COLON,":"); advance()
            end
        elseif c == "/" then
            if peeks(2) == "//" then addtok(Lexer.TK.DOUBLESLASH,"//"); advance(2)
            else addtok(Lexer.TK.SLASH,"/"); advance()
            end
        elseif c == "-" then
            if peeks(2) == "->" then addtok(Lexer.TK.ARROW,"->"); advance(2)
            else addtok(Lexer.TK.MINUS,"-"); advance()
            end
        else
            local simple = {
                ["+"]=Lexer.TK.PLUS, ["*"]=Lexer.TK.STAR, ["%"]=Lexer.TK.PERCENT,
                ["^"]=Lexer.TK.CARET, ["#"]=Lexer.TK.HASH, ["&"]=Lexer.TK.AMP,
                ["|"]=Lexer.TK.PIPE, ["("]=Lexer.TK.LPAREN, [")"]=Lexer.TK.RPAREN,
                ["{"]=Lexer.TK.LBRACE, ["}"]=Lexer.TK.RBRACE,
                ["]"]=Lexer.TK.RBRACKET,
                [";"]=Lexer.TK.SEMICOL, [","]=Lexer.TK.COMMA,
            }
            if simple[c] then
                addtok(simple[c], c); advance()
            else

                addtok("RAW", c, c); advance()
            end
        end
    end

    addtok(Lexer.TK.EOF, "")
    return tokens
end

local IR = {}

IR.NodeKind = {
    LOCAL_DECL   = "LOCAL_DECL",
    ASSIGN       = "ASSIGN",
    FUNC_DEF     = "FUNC_DEF",
    LOCAL_FUNC   = "LOCAL_FUNC",
    CALL         = "CALL",
    IF_BLOCK     = "IF_BLOCK",
    WHILE_LOOP   = "WHILE_LOOP",
    FOR_NUM      = "FOR_NUM",
    FOR_GEN      = "FOR_GEN",
    DO_BLOCK     = "DO_BLOCK",
    RETURN_STMT  = "RETURN_STMT",
    STRING_LIT   = "STRING_LIT",
    NUMBER_LIT   = "NUMBER_LIT",
    NAME_REF     = "NAME_REF",
    RAW          = "RAW",
}

function IR.Build(tokens)

    local toks = {}
    for _, t in ipairs(tokens) do
        if t.kind ~= Lexer.TK.COMMENT then
            table.insert(toks, t)
        end
    end




    local localDecls = {}
    local i = 1
    while i <= #toks do
        local t = toks[i]
        if t.kind == "LOCAL" then
            local j = i + 1
            if toks[j] and toks[j].kind == "FUNCTION" then

                j = j + 1
                if toks[j] and toks[j].kind == Lexer.TK.NAME then
                    toks[j]._localDecl = true
                    localDecls[toks[j].value] = true
                end
            else

                while toks[j] and toks[j].kind == Lexer.TK.NAME do
                    toks[j]._localDecl = true
                    localDecls[toks[j].value] = true
                    j = j + 1
                    if toks[j] and toks[j].kind == Lexer.TK.COMMA then
                        j = j + 1
                    else
                        break
                    end
                end
            end
        end
        i = i + 1
    end


    for _, t in ipairs(toks) do
        if t.kind == Lexer.TK.NAME and localDecls[t.value] then
            t._isLocal = true
        end
    end

    return {tokens = toks, localDecls = localDecls}
end

local Optimizer = {}

function Optimizer.ConstantFold(ir, rng)
    local toks = ir.tokens
    local i = 1
    local changed = false
    local result = {}

    while i <= #toks do
        local t = toks[i]

        if t.kind == Lexer.TK.NUMBER
            and toks[i+1] and toks[i+2]
            and toks[i+2].kind == Lexer.TK.NUMBER
        then
            local op = toks[i+1].kind
            local a = t.value
            local b = toks[i+2].value
            local folded = nil

            if type(a) == "number" and type(b) == "number"
               and a == a and b == b
               and math.abs(a) < 1e14 and math.abs(b) < 1e14
            then
                if op == Lexer.TK.PLUS then
                    folded = a + b
                elseif op == Lexer.TK.MINUS then
                    folded = a - b
                elseif op == Lexer.TK.STAR then
                    folded = a * b
                elseif op == Lexer.TK.SLASH and b ~= 0 then
                    folded = a / b
                elseif op == Lexer.TK.DOUBLESLASH and b ~= 0
                    and a == math.floor(a) and b == math.floor(b) then
                    folded = math.floor(a / b)
                elseif op == Lexer.TK.PERCENT and b ~= 0
                    and a == math.floor(a) and b == math.floor(b) then
                    folded = a % b
                end
            end
            if folded ~= nil then
                table.insert(result, {
                    kind = Lexer.TK.NUMBER,
                    value = folded,
                    raw = tostring(folded),
                    line = t.line,
                    _folded = true,
                })
                i = i + 3
                changed = true
            else
                table.insert(result, t)
                i = i + 1
            end
        else
            table.insert(result, t)
            i = i + 1
        end
    end

    ir.tokens = result
    return changed
end

function Optimizer.StripSemicolons(ir)
    local result = {}
    for _, t in ipairs(ir.tokens) do
        if t.kind ~= Lexer.TK.SEMICOL then
            table.insert(result, t)
        end
    end
    ir.tokens = result
end

function Optimizer.FindDuplicateStrings(ir)
    local counts = {}
    for _, t in ipairs(ir.tokens) do
        if t.kind == Lexer.TK.STRING then
            counts[t.value] = (counts[t.value] or 0) + 1
        end
    end

    local pool = {}
    for s, c in pairs(counts) do
        if c > 1 then
            pool[s] = true
        end
    end
    return pool
end

function Optimizer.Run(ir, level, rng)
    level = level or 1
    if level >= 1 then
        Optimizer.StripSemicolons(ir)
        Optimizer.ConstantFold(ir, rng)
    end
    if level >= 2 then

        Optimizer.ConstantFold(ir, rng)
    end



    return ir
end

local Transformers = {}

Transformers.Rename = {}

function Transformers.Rename.Apply(ir, rng, prefix)
    local idents = Util.NewIdentGen(rng, prefix or "_")
    local renameMap = {}


    for _, t in ipairs(ir.tokens) do
        if t._localDecl and t.kind == Lexer.TK.NAME then
            if not renameMap[t.value] then
                renameMap[t.value] = idents:Get("confuse")
            end
        end
    end


    for _, t in ipairs(ir.tokens) do
        if t.kind == Lexer.TK.NAME and t._isLocal and renameMap[t.value] then
            t.raw = renameMap[t.value]
            t.value = renameMap[t.value]
        end
    end

    return renameMap
end

Transformers.Strings = {}

function Transformers.Strings.Apply(ir, rng, idents, options)
    options = options or {}
    local pool = {}
    local poolOrder = {}
    local poolVarName = idents:Get("confuse")
    local decodeVarName = idents:Get("confuse")


    local dupOnly = options.StringsPoolDupOnly
    local dupSet = dupOnly and Optimizer.FindDuplicateStrings(ir) or nil


    local function getSlot(value)
        if pool[value] then return pool[value] end
        local xorKey = rng:Next(1, 254)
        local encoded = Util.EncodeString(value, xorKey)
        local idx = #poolOrder + 1
        pool[value] = idx
        poolOrder[idx] = {value = value, xorKey = xorKey, encoded = encoded}
        return idx
    end


    local i = 1
    local toks = ir.tokens
    while i <= #toks do
        local t = toks[i]
        if t.kind == Lexer.TK.STRING then
            local shouldPool = true
            if dupOnly and not dupSet[t.value] then
                shouldPool = false
            end

            if #t.value <= 1 then shouldPool = false end

            if t.value == "" then shouldPool = false end

            if shouldPool then
                local idx = getSlot(t.value)

                t.raw = poolVarName .. "[" .. idx .. "]"
                t.kind = "POOL_REF"
                t._poolIdx = idx
            end
        elseif t.kind == Lexer.TK.RAWSTR then

        end
        i = i + 1
    end



    if #poolOrder > 1 then
        local indices = {}
        for k=1,#poolOrder do indices[k]=k end
        rng:Shuffle(indices)
        local newPool = {}
        local newOrder = {}
        for newIdx, oldIdx in ipairs(indices) do
            newOrder[newIdx] = poolOrder[oldIdx]
            newPool[poolOrder[oldIdx].value] = newIdx
        end

        for _, t in ipairs(ir.tokens) do
            if t.kind == "POOL_REF" then
                t.raw = poolVarName .. "[" .. newPool[poolOrder[t._poolIdx].value] .. "]"
            end
        end
        pool = newPool
        poolOrder = newOrder
    end


    if #poolOrder == 0 then
        return nil, nil
    end



    local decodeFuncSrc = string.format(
        "local %s=function(k,t)local r={}for i=1,#t do r[i]=string.char(bit32.bxor(t[i],k))end return table.concat(r)end;",
        decodeVarName
    )



    local entries = {}
    for _, entry in ipairs(poolOrder) do
        local byteParts = table.concat(entry.encoded, ",")
        table.insert(entries, string.format(
            "%s(%d,{%s})",
            decodeVarName, entry.xorKey, byteParts
        ))
    end

    local poolSrc = string.format(
        "local %s={%s};",
        poolVarName, table.concat(entries, ",")
    )

    return decodeFuncSrc .. poolSrc, poolVarName
end

Transformers.Numbers = {}

function Transformers.Numbers.Apply(ir, rng)
    for _, t in ipairs(ir.tokens) do
        if t.kind == Lexer.TK.NUMBER then


            local v = t.value
            if type(v) == "number" and v ~= 0 and v ~= 1 and v == math.floor(v)
                and math.abs(v) < 100000 and v == v
            then
                t.raw = Util.ObfuscateNumber(v, rng)
                t.kind = "NUMBER_OBF"
            end
        end
    end
end

Transformers.ControlFlow = {}

function Transformers.ControlFlow.Apply(ir, rng, idents)








    local toks = ir.tokens
    local depth = 0
    local i = 1
    local result = {}

    while i <= #toks do
        local t = toks[i]

        if t.kind == "DO" or t.kind == "THEN" or t.kind == "FUNCTION"
            or t.kind == "WHILE" or t.kind == "FOR" or t.kind == "REPEAT"
        then

            if t.kind == "DO" and depth == 0 and rng:Next(1,3) == 1 then

                local stateVar = idents:Get("confuse")

                local n = rng:Next(1, 65535)
                table.insert(result, {kind="RAW", raw="do ", value="do ", line=t.line})
                table.insert(result, {kind="RAW",
                    raw=string.format("local %s=bit32.bxor(%d,%d);if %s==0 then ", stateVar, n, n, stateVar),
                    value="",line=t.line})
                depth = depth + 1
                i = i + 1

                local inner = {}
                local innerDepth = 1
                while i <= #toks and innerDepth > 0 do
                    local it = toks[i]
                    if it.kind == "DO" or it.kind == "THEN" or it.kind == "FUNCTION"
                        or it.kind == "WHILE" or it.kind == "FOR" or it.kind == "REPEAT"
                    then
                        innerDepth = innerDepth + 1
                    elseif it.kind == "END" or it.kind == "UNTIL" then
                        innerDepth = innerDepth - 1
                        if innerDepth == 0 then

                            for _, iv in ipairs(inner) do table.insert(result, iv) end
                            table.insert(result, {kind="RAW", raw=" end end ", value="", line=it.line})
                            i = i + 1
                            depth = depth - 1
                            break
                        end
                    end
                    table.insert(inner, it)
                    i = i + 1
                end
            else
                if t.kind ~= "THEN" then depth = depth + 1 end
                table.insert(result, t)
                i = i + 1
            end
        elseif t.kind == "END" or t.kind == "UNTIL" then
            depth = math.max(0, depth - 1)
            table.insert(result, t)
            i = i + 1
        else
            table.insert(result, t)
            i = i + 1
        end
    end

    ir.tokens = result
end

Transformers.Junk = {}

function Transformers.Junk.Apply(ir, rng, idents, count)
    count = count or 3
    local toks = ir.tokens
    local result = {}
    local inserted = 0
    local total = #toks


    local function makeJunk()
        local jVar = idents:Get("confuse")
        local strategies = {

            function()
                local a = rng:Next(1, 9999)
                local b = rng:Next(1, 99)
                return string.format("local %s=bit32.bxor(%d,%d);", jVar, a, b)
            end,

            function()
                local n = rng:Next(2, 16)
                local dummy = string.rep("x", n)
                return string.format("local %s=string.len(%q);", jVar, dummy)
            end,

            function()
                return string.format("local %s=table.concat({});", jVar)
            end,

            function()
                local a = rng:Next(100, 9999)
                local b = rng:Next(1, a)
                return string.format("local %s=math.floor(%d/%d);", jVar, a, b)
            end,
        }
        return rng:Choice(strategies)()
    end


    local spacing = math.max(math.floor(total / (count + 1)), 5)
    local nextInsert = spacing

    for i, t in ipairs(toks) do
        table.insert(result, t)
        if inserted < count and i >= nextInsert then

            local prev = toks[i]
            if prev and (prev.kind == "END" or prev.kind == Lexer.TK.SEMICOL
                or prev.kind == "UNTIL" or prev.kind == Lexer.TK.RBRACE
                or (i > 1 and toks[i-1] and toks[i-1].kind == Lexer.TK.RPAREN)
            ) then
                table.insert(result, {kind="RAW", raw=makeJunk(), value="", line=t.line})
                inserted = inserted + 1
                nextInsert = i + spacing
            end
        end
    end

    ir.tokens = result
end

local VM = {}

VM.OPS = {
    LOAD_CONST     = 1,
    LOAD_NIL       = 2,
    LOAD_TRUE      = 3,
    LOAD_FALSE     = 4,
    LOAD_LOCAL     = 5,
    STORE_LOCAL    = 6,
    MOVE           = 7,
    GET_GLOBAL     = 8,
    CALL           = 9,
    RETURN         = 10,
    JUMP           = 11,
    JUMP_IF_FALSE  = 12,
    JUMP_IF_TRUE   = 13,
    ADD            = 14,
    SUB            = 15,
    MUL            = 16,
    DIV            = 17,
    MOD            = 18,
    POW            = 19,
    CONCAT         = 20,
    UNM            = 21,
    NOT_OP         = 22,
    LEN            = 23,
    EQ             = 24,
    NE             = 25,
    LT             = 26,
    LE             = 27,
    NEW_TABLE      = 28,
    GET_INDEX      = 29,
    SET_INDEX      = 30,
}

function VM.RandomizeOpcodes(rng)
    local names = {}
    for k in pairs(VM.OPS) do table.insert(names, k) end
    local values = {}
    for k=1,#names do table.insert(values, k) end
    rng:Shuffle(values)
    local mapping = {}
    for i, name in ipairs(names) do
        mapping[name] = values[i]
    end
    return mapping
end

VM.Compiler = {}

function VM.Compiler.CompileSimple(source, constants, opcodes, rng)




    local instrs = {}
    local localSlots = {}
    local nextSlot = 0

    local function emit(op, a, b, c)
        table.insert(instrs, {opcodes[op] or VM.OPS[op], a or 0, b or 0, c or 0})
    end
    local function constIdx(v)
        for i, c in ipairs(constants) do
            if c == v then return i - 1 end
        end
        table.insert(constants, v)
        return #constants - 1
    end
    local function slot(name)
        if not localSlots[name] then
            localSlots[name] = nextSlot
            nextSlot = nextSlot + 1
        end
        return localSlots[name]
    end



    local srcIdx = constIdx(source)
    emit("LOAD_CONST", 0, srcIdx)

    local lsIdx = constIdx("loadstring")
    emit("GET_GLOBAL", 1, lsIdx)
    emit("CALL", 1, 1, 1)
    emit("CALL", 1, 0, 0)
    emit("RETURN", 0, 0)

    return instrs
end

function VM.Compiler.Encode(instrs, rng)
    local key = rng:Next(1, 255)
    local encoded = {}
    for _, instr in ipairs(instrs) do
        local e = {}
        for _, field in ipairs(instr) do
            table.insert(e, bit32.bxor(field, key))
        end
        table.insert(encoded, e)
    end
    return encoded, key
end

VM.Generator = {}

function VM.Generator.Emit(constants, encodedInstrs, decodeKey, opcodes, rng, idents)
    local vmName     = idents:Get("confuse")
    local regName    = idents:Get("confuse")
    local instrName  = idents:Get("confuse")
    local pcName     = idents:Get("confuse")
    local constName  = idents:Get("confuse")
    local keyName    = idents:Get("confuse")
    local opMapName  = idents:Get("confuse")
    local envName    = idents:Get("confuse")


    local opRevLines = {}
    for name, val in pairs(opcodes) do
        table.insert(opRevLines, string.format("[%d]=%q", val, name))
    end


    local constParts = {}
    for _, c in ipairs(constants) do
        if type(c) == "string" then
            table.insert(constParts, string.format("%q", c))
        elseif type(c) == "number" then
            table.insert(constParts, tostring(c))
        elseif type(c) == "boolean" then
            table.insert(constParts, tostring(c))
        else
            table.insert(constParts, "nil")
        end
    end


    local instrParts = {}
    for _, instr in ipairs(encodedInstrs) do
        table.insert(instrParts, "{" .. table.concat(instr, ",") .. "}")
    end

    local src = {}
    local function w(s) table.insert(src, s) end

    w(string.format("local %s=%d;", keyName, decodeKey))
    w(string.format("local %s={%s};", constName, table.concat(constParts, ",")))
    w(string.format("local %s={%s};", instrName, table.concat(instrParts, ",")))
    w(string.format("local %s={%s};", opMapName, table.concat(opRevLines, ",")))
    w(string.format("local %s=getfenv and getfenv() or _ENV or {};", envName))


    w(string.format("local function %s()", vmName))
    w(string.format("  local %s={};local %s=1;", regName, pcName))
    w(string.format("  while %s<=#%s do", pcName, instrName))
    w(string.format("    local _i=%s[%s];", instrName, pcName))
    w(string.format("    local _op=bit32.bxor(_i[1],%s);", keyName))
    w(string.format("    local _a=bit32.bxor(_i[2],%s);", keyName))
    w(string.format("    local _b=bit32.bxor(_i[3],%s);", keyName))
    w(string.format("    local _c=bit32.bxor(_i[4],%s);", keyName))
    w(string.format("    local _opname=%s[_op];", opMapName))

    w(string.format("    if _opname=='LOAD_CONST' then %s[_a]=%s[_b+1]", regName, constName))
    w(string.format("    elseif _opname=='LOAD_NIL' then %s[_a]=nil", regName))
    w(string.format("    elseif _opname=='LOAD_TRUE' then %s[_a]=true", regName))
    w(string.format("    elseif _opname=='LOAD_FALSE' then %s[_a]=false", regName))
    w(string.format("    elseif _opname=='MOVE' then %s[_a]=%s[_b]", regName, regName))
    w(string.format("    elseif _opname=='GET_GLOBAL' then %s[_a]=%s[%s[_b+1]]", regName, envName, constName))
    w(string.format("    elseif _opname=='CALL' then"))
    w(string.format("      local _fn=%s[_a];local _args={};", regName))
    w(string.format("      for _ai=1,_b do _args[_ai]=%s[_a+_ai] end", regName))
    w(string.format("      local _rets={_fn(table.unpack(_args))};"))
    w(string.format("      for _ri=1,_c do %s[_a+_ri-1]=_rets[_ri] end", regName))
    w(string.format("    elseif _opname=='RETURN' then return table.unpack(%s,_a+1,_a+_b)", regName))
    w(string.format("    elseif _opname=='JUMP' then %s=_a-1", pcName))
    w(string.format("    elseif _opname=='JUMP_IF_FALSE' then if not %s[_a] then %s=_b-1 end", regName, pcName))
    w(string.format("    elseif _opname=='JUMP_IF_TRUE' then if %s[_a] then %s=_b-1 end", regName, pcName))
    w(string.format("    elseif _opname=='ADD' then %s[_a]=%s[_b]+%s[_c]", regName, regName, regName))
    w(string.format("    elseif _opname=='SUB' then %s[_a]=%s[_b]-%s[_c]", regName, regName, regName))
    w(string.format("    elseif _opname=='MUL' then %s[_a]=%s[_b]*%s[_c]", regName, regName, regName))
    w(string.format("    elseif _opname=='DIV' then %s[_a]=%s[_b]/%s[_c]", regName, regName, regName))
    w(string.format("    elseif _opname=='MOD' then %s[_a]=%s[_b]%%%s[_c]", regName, regName, regName))
    w(string.format("    elseif _opname=='POW' then %s[_a]=%s[_b]^%s[_c]", regName, regName, regName))
    w(string.format("    elseif _opname=='CONCAT' then %s[_a]=%s[_b]..%s[_c]", regName, regName, regName))
    w(string.format("    elseif _opname=='UNM' then %s[_a]=-%s[_b]", regName, regName))
    w(string.format("    elseif _opname=='NOT_OP' then %s[_a]=not %s[_b]", regName, regName))
    w(string.format("    elseif _opname=='LEN' then %s[_a]=#%s[_b]", regName, regName))
    w(string.format("    elseif _opname=='EQ' then %s[_a]=%s[_b]==%s[_c]", regName, regName, regName))
    w(string.format("    elseif _opname=='NE' then %s[_a]=%s[_b]~=%s[_c]", regName, regName, regName))
    w(string.format("    elseif _opname=='LT' then %s[_a]=%s[_b]<%s[_c]", regName, regName, regName))
    w(string.format("    elseif _opname=='LE' then %s[_a]=%s[_b]<=%s[_c]", regName, regName, regName))
    w(string.format("    elseif _opname=='NEW_TABLE' then %s[_a]={}", regName))
    w(string.format("    elseif _opname=='GET_INDEX' then %s[_a]=%s[_b][%s[_c]]", regName, regName, regName))
    w(string.format("    elseif _opname=='SET_INDEX' then %s[_a][%s[_b]]=%s[_c]", regName, regName, regName))
    w(string.format("    end"))
    w(string.format("    %s=%s+1", pcName, pcName))
    w(string.format("  end"))
    w(string.format("end"))
    w(string.format("%s()", vmName))

    return table.concat(src, "\n")
end

local Integrity = {}

function Integrity.Emit(body, rng, idents)
    local checkVarName = idents:Get("confuse")
    local expectedHash = Util.Checksum(body)



    local marker = tostring(expectedHash)
    local markerEncoded = Util.EncodeString(marker)
    local markerTableLit = "{" .. table.concat(markerEncoded, ",") .. "}"

    local src = string.format([[
local %s=(function()
  local _m=%s
  local _s={}
  for _i=1,#_m do _s[_i]=string.char(_m[_i]) end
  local _r=table.concat(_s)
  local _h=5381
  for _i=1,#_r do
    _h=bit32.bxor(bit32.lshift(_h,5)+_h,string.byte(_r,_i))
    _h=_h%%4294967295
  end
  return _h
end)();
if %s~=%d then return end
]], checkVarName, markerTableLit, checkVarName, expectedHash)

    return src
end

local Minifier = {}

function Minifier.Run(source)






    local result = {}
    local i = 1
    local n = #source
    local inStr = false
    local strChar = nil
    local lastWasSpace = false

    while i <= n do
        local c = source:sub(i,i)

        if inStr then
            table.insert(result, c)
            if c == "\\" then

                i = i + 1
                if i <= n then
                    table.insert(result, source:sub(i,i))
                end
            elseif c == strChar then
                inStr = false
            end
            lastWasSpace = false
        elseif c == '"' or c == "'" then
            inStr = true
            strChar = c
            table.insert(result, c)
            lastWasSpace = false
        elseif c:match("%s") then

            if not lastWasSpace then

                table.insert(result, " ")
                lastWasSpace = true
            end
        else
            table.insert(result, c)
            lastWasSpace = false
        end

        i = i + 1
    end

    return table.concat(result):match("^%s*(.-)%s*$")
end

local Generator = {}

local NEEDS_SPACE_BEFORE = {
    [Lexer.TK.NAME]=true, [Lexer.TK.NUMBER]=true,
    ["NUMBER_OBF"]=true, ["POOL_REF"]=true, ["NUMBER_LIT"]=true,
    ["LOCAL"]=true,["FUNCTION"]=true,["IF"]=true,["THEN"]=true,
    ["ELSE"]=true,["ELSEIF"]=true,["END"]=true,["DO"]=true,
    ["WHILE"]=true,["FOR"]=true,["IN"]=true,["REPEAT"]=true,
    ["UNTIL"]=true,["RETURN"]=true,["BREAK"]=true,["AND"]=true,
    ["OR"]=true,["NOT"]=true,["NIL"]=true,["TRUE"]=true,["FALSE"]=true,
    ["GOTO"]=true,["TYPE"]=true,["EXPORT"]=true,["CONTINUE"]=true,
}

local NEEDS_SPACE_AFTER = {
    ["LOCAL"]=true,["FUNCTION"]=true,["IF"]=true,["THEN"]=true,
    ["ELSE"]=true,["ELSEIF"]=true,["DO"]=true,["WHILE"]=true,
    ["FOR"]=true,["IN"]=true,["REPEAT"]=true,["UNTIL"]=true,
    ["RETURN"]=true,["AND"]=true,["OR"]=true,["NOT"]=true,
    ["GOTO"]=true,["TYPE"]=true,["EXPORT"]=true,["CONTINUE"]=true,
    [Lexer.TK.ASSIGN]=true,
    [Lexer.TK.PLUS]=true,[Lexer.TK.MINUS]=true,[Lexer.TK.STAR]=true,
    [Lexer.TK.SLASH]=true,[Lexer.TK.DOUBLESLASH]=true,
    [Lexer.TK.PERCENT]=true,[Lexer.TK.CARET]=true,
    [Lexer.TK.EQ]=true,[Lexer.TK.NEQ]=true,[Lexer.TK.LT]=true,
    [Lexer.TK.LE]=true,[Lexer.TK.GT]=true,[Lexer.TK.GE]=true,
    [Lexer.TK.DOTDOT]=true,[Lexer.TK.DOTDOTDOT]=true,
    [Lexer.TK.COMMA]=true,
}

function Generator.Emit(ir, header)
    local parts = {}
    if header then
        table.insert(parts, header)
    end

    local prev = nil
    for _, t in ipairs(ir.tokens) do
        if t.kind == Lexer.TK.EOF then break end

        local raw = t.raw or t.value or ""
        if raw == "" then goto continue end


        local needSpace = false
        if prev then
            local pk = prev.kind
            local ck = t.kind

            if NEEDS_SPACE_AFTER[pk] then needSpace = true end

            if NEEDS_SPACE_BEFORE[ck] then

                if not NEEDS_SPACE_AFTER[pk] then needSpace = true end
            end

            if (pk == Lexer.TK.NAME or KEYWORDS[prev.value or ""])
                and (ck == Lexer.TK.NAME or ck == Lexer.TK.NUMBER or KEYWORDS[t.value or ""])
            then needSpace = true end

            if pk == Lexer.TK.NUMBER and (ck == Lexer.TK.NAME or ck == Lexer.TK.NUMBER) then
                needSpace = true
            end

            if pk == Lexer.TK.COMMA then needSpace = true end

            if NEEDS_SPACE_BEFORE[ck] and prev.kind == Lexer.TK.NAME then needSpace = true end
        end

        if needSpace and #parts > 0 then
            local last = parts[#parts]
            if last:sub(-1) ~= " " and last:sub(-1) ~= "\n" and raw:sub(1,1) ~= " " then
                table.insert(parts, " ")
            end
        end

        table.insert(parts, raw)
        prev = t
        ::continue::
    end

    return table.concat(parts)
end

local Presets = {}

Presets.Definitions = {
    Light = {
        RenameLocals    = true,
        Strings         = true,
        Constants       = false,
        Numbers         = false,
        ControlFlow     = false,
        JunkCode        = false,
        VM              = false,
        Optimize        = true,
        OptimizeLevel   = 1,
        Minify          = true,
        AntiTamper      = false,
        IntegrityCheck  = false,
    },
    Balanced = {
        RenameLocals    = true,
        Strings         = true,
        Constants       = true,
        Numbers         = true,
        ControlFlow     = true,
        JunkCode        = true,
        JunkLevel       = 2,
        VM              = false,
        Optimize        = true,
        OptimizeLevel   = 2,
        Minify          = true,
        AntiTamper      = false,
        IntegrityCheck  = false,
    },
    Strong = {
        RenameLocals    = true,
        Strings         = true,
        Constants       = true,
        Numbers         = true,
        ControlFlow     = true,
        JunkCode        = true,
        JunkLevel       = 3,
        VM              = true,
        VMLevel         = 2,
        Optimize        = true,
        OptimizeLevel   = 2,
        Minify          = true,
        AntiTamper      = true,
        IntegrityCheck  = true,
    },
    VM = {
        RenameLocals    = true,
        Strings         = true,
        Constants       = true,
        Numbers         = false,
        ControlFlow     = true,
        JunkCode        = true,
        JunkLevel       = 2,
        VM              = true,
        VMLevel         = 2,
        Optimize        = true,
        OptimizeLevel   = 1,
        Minify          = true,
        AntiTamper      = true,
        IntegrityCheck  = false,
    },
    Maximum = {
        RenameLocals    = true,
        Strings         = true,
        Constants       = true,
        Numbers         = true,
        ControlFlow     = true,
        JunkCode        = true,
        JunkLevel       = 4,
        VM              = true,
        VMLevel         = 3,
        Optimize        = true,
        OptimizeLevel   = 2,
        Minify          = true,
        AntiTamper      = true,
        IntegrityCheck  = true,
    },
}

function Presets.Resolve(options)
    local base = {}
    if options.Preset then
        local def = Presets.Definitions[options.Preset]
        if def then
            for k, v in pairs(def) do
                base[k] = v
            end
        end
    end

    for k, v in pairs(options) do
        if k ~= "Preset" then
            base[k] = v
        end
    end
    return base
end

local PerplexObf = {}
PerplexObf.__index = PerplexObf

local DEFAULT_OPTIONS = {
    Name              = "Perplex_",
    Watermark         = "Perplex Obf v1.0.4 --> dsc.gg/perplexware",

    Preset            = nil,

    VM                = false,
    VMLevel           = 1,

    Optimize          = true,
    OptimizeLevel     = 1,

    Strings           = true,
    Constants         = true,
    Numbers           = false,
    ControlFlow       = false,
    RenameLocals      = true,
    JunkCode          = false,
    JunkLevel         = 1,

    AntiTamper        = false,
    IntegrityCheck    = false,

    RobloxCompatible  = true,
    LuauCompatible    = true,

    Minify            = true,

    Seed              = nil,
}

function PerplexObf:Protect(source, options)

    if type(source) ~= "string" then
        return nil, "[Perplex] Error: source must be a string"
    end
    if #source == 0 then
        return nil, "[Perplex] Error: source is empty"
    end

    options = options or {}


    local opts = {}
    for k, v in pairs(DEFAULT_OPTIONS) do opts[k] = v end
    opts = Presets.Resolve(options)

    for k, v in pairs(DEFAULT_OPTIONS) do
        if opts[k] == nil then opts[k] = v end
    end


    local seed = opts.Seed
    if seed == nil then
        seed = math.floor(os.clock() * 1e9) % 0xFFFFFF
    end
    local rng = Util.NewRNG(seed)


    local ok, tokens = pcall(Lexer.Tokenize, source)
    if not ok then
        return nil, "[Perplex] Lexer error: " .. tostring(tokens)
    end


    local ok2, ir = pcall(IR.Build, tokens)
    if not ok2 then
        return nil, "[Perplex] IR error: " .. tostring(ir)
    end


    if opts.Optimize then
        local ok3, err3 = pcall(Optimizer.Run, ir, opts.OptimizeLevel or 1, rng)
        if not ok3 then
            return nil, "[Perplex] Optimizer error: " .. tostring(err3)
        end
    end


    local idents = Util.NewIdentGen(rng, opts.Name or "Perplex_")
    local preamble = {}


    if opts.RenameLocals then
        local ok4, err4 = pcall(Transformers.Rename.Apply, ir, rng, opts.Name)
        if not ok4 then
            return nil, "[Perplex] Rename error: " .. tostring(err4)
        end
    end


    local poolSrc = nil
    if opts.Strings then
        local ok5, p, _ = pcall(Transformers.Strings.Apply, ir, rng, idents, opts)
        if not ok5 then
            return nil, "[Perplex] String transformer error: " .. tostring(p)
        end
        poolSrc = p
    end


    if opts.Numbers then
        local ok6, err6 = pcall(Transformers.Numbers.Apply, ir, rng)
        if not ok6 then
            return nil, "[Perplex] Number transformer error: " .. tostring(err6)
        end
    end


    if opts.ControlFlow then
        local ok7, err7 = pcall(Transformers.ControlFlow.Apply, ir, rng, idents)
        if not ok7 then
            return nil, "[Perplex] ControlFlow error: " .. tostring(err7)
        end
    end


    if opts.JunkCode then
        local junkCount = (opts.JunkLevel or 1) * 3
        local ok8, err8 = pcall(Transformers.Junk.Apply, ir, rng, idents, junkCount)
        if not ok8 then
            return nil, "[Perplex] Junk error: " .. tostring(err8)
        end
    end


    local vmSrc = nil
    if opts.VM then
        local opcodes = VM.RandomizeOpcodes(rng)
        local constants = {}
        local instrs = VM.Compiler.CompileSimple(source, constants, opcodes, rng)
        local encodedInstrs, decodeKey = VM.Compiler.Encode(instrs, rng)
        local ok9, vs = pcall(VM.Generator.Emit,
            constants, encodedInstrs, decodeKey, opcodes, rng, idents)
        if not ok9 then
            return nil, "[Perplex] VM generation error: " .. tostring(vs)
        end
        vmSrc = vs
    end



    local wmHeader = string.format(
        "",
        opts.Watermark or "Perplex Obf v1.0.4 --> dsc.gg/perplexware"
    )

    local body
    if opts.VM then

        body = vmSrc
    else

        local ok10, emitted = pcall(Generator.Emit, ir, poolSrc)
        if not ok10 then
            return nil, "[Perplex] Generator error: " .. tostring(emitted)
        end
        body = emitted
    end


    local integrityHeader = ""
    if opts.IntegrityCheck or opts.AntiTamper then
        local ok11, ih = pcall(Integrity.Emit, body, rng, idents)
        if not ok11 then
            return nil, "[Perplex] Integrity error: " .. tostring(ih)
        end
        integrityHeader = ih
    end


    local finalBody = integrityHeader .. body
    if opts.Minify then
        local ok12, minified = pcall(Minifier.Run, finalBody)
        if not ok12 then
            return nil, "[Perplex] Minifier error: " .. tostring(minified)
        end
        finalBody = minified
    end


    local output = wmHeader .. "\n" .. finalBody
    return output
end

function PerplexObf:ProtectSafe(source, options)
    local ok, result, err = pcall(function()
        return self:Protect(source, options)
    end)
    if not ok then
        return nil, "[Perplex] Uncaught error: " .. tostring(result)
    end
    return result, err
end

return PerplexObf