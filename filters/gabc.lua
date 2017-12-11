-- Pandoc filter to process code blocks with class "gabc" containing
-- gregorian notation.
--
-- * Assumes that LuaLaTeX (with a reasonable collection of packages),
-- * [Gregorio](http://gregorio-project.github.io/)
-- * and Ghostscript are installed.
--
-- * NOTE ABOUT PDF GENERATION: pandoc compiles the document from another
-- * directory than the current one. Because of that, you have to invoke pandoc
-- * with the environment variable openout_any set to a. Moreover, it needs to
-- * call Gregorio, which is an external program; hence the need for a
-- * shell-escape switch. For example:
-- *
-- *   openout_any=a pandoc --pdf-engine=lualatex --pdf-engine-opt="-shell-escape" --lua-filter=gabc.lua -s -o DOC.pdf DOC.md
-- *
-- * Another solution is to first generate a DOC.tex document, then compile it
-- * (twice to let Gregorio make its calculations):
-- *   pandoc --lua-filter=gabc.lua -s --self-contained -o DOC.tex DOC.md
-- *   lualatex -shell-escape DOC
-- *   lualatex -shell-escape DOC


local filetypes = { html = {"png", "image/png"}
                  , latex = {"pdf", "application/pdf"}
                  }
local filetype = "png"
local mimetype = "image/png"
if filetypes[FORMAT] then
    filetype = filetypes[FORMAT][1] or "png"
    mimetype = filetypes[FORMAT][2] or "image/png"
end

local DEFAULT_PARAMS = {
    ["fontsize"] = '10pt',
    ["width"] = '12cm',
    ["staffsize"] = 17,
    ["initiallines"] = 1
}
local DEFAULT_DIMS = {}
local LATEX_DOC = [[\RequirePackage{luatex85}
\documentclass[%s]{scrartcl}
\usepackage[autocompile]{gregoriotex}
\usepackage{libertine}

\hoffset-1in
\voffset-1in
\newbox\scorebox

%%\gresetheadercapture{commentary}{grecommentary}{string}
\catcode`\℣=\active \def ℣#1{{\Vbar\hspace{-.25ex}#1}}
\catcode`\℟=\active \def ℟#1{{\Rbar\hspace{-.25ex}#1}}
\catcode`\†=\active \def †{{\GreDagger}}
\catcode`\✠=\active \def ✠{{\grecross}}
\grechangecount{tolerance}{9999}
\grechangecount{pretolerance}{5000}

\begin{document}

\let\grevanillacommentary\grecommentary
\def\grecommentary#1{\grevanillacommentary{#1\/\rule{0pt}{0.8em}}}

\setbox\scorebox=\vbox{\hsize=%s\relax
	%s
}
\pdfpagewidth\wd\scorebox
\pdfpageheight\dimexpr\ht\scorebox+\dp\scorebox\relax
\shipout\box\scorebox
\end{document}
]]


local function file_exists(name)
    return io.open(name, 'r')
end


function string:explode(div) -- credit: http://richard.warburton.it
    if (div=='') then return false end
    local pos,arr = 0,{}
    -- for each divider found
    for st,sp in function() return string.find(self,div,pos,true) end do
        table.insert(arr,string.sub(self,pos,st-1)) -- Attach chars left of current divider
        pos = sp + 1 -- Jump past current divider
    end
    table.insert(arr,string.sub(self,pos)) -- Attach chars right of last divider
    return arr
end


local function has_value (tab, val)
    for _, value in ipairs(tab) do
        if value == val then
            return true
        end
    end
    return false
end


local function contains (self, line)
    for _, l in pairs(self) do
        if l[1].text == line then
            return true
        end
    end
    return false
end


function __genOrderedIndex( t )
    local orderedIndex = {}
    for key in pairs(t) do
        table.insert( orderedIndex, key )
    end
    table.sort( orderedIndex )
    return orderedIndex
end

function orderedNext(t, state)
    local key = nil
    if state == nil then
        t.__orderedIndex = __genOrderedIndex( t )
        key = t.__orderedIndex[1]
    else
        for i = 1, #t.__orderedIndex do
            if t.__orderedIndex[i] == state then
                key = t.__orderedIndex[i+1]
            end
        end
    end
    if key then
        return key, t[key]
    end
    t.__orderedIndex = nil
    return
end

function orderedPairs(t)
    return orderedNext, t, nil
end


local function default_params(meta)
    if not meta['header-includes'] then
        meta['header-includes'] = pandoc.MetaList({})
    end
    if not meta['include-before'] then
        meta['include-before'] = pandoc.MetaList({})
    end
    if not contains(meta['header-includes'],
                    '\\usepackage[autocompile]{gregoriotex}\n')
    then
        table.insert(
            meta['header-includes'],
            pandoc.MetaInlines({
                    pandoc.RawInline('latex',
                                     '\\usepackage[autocompile]{gregoriotex}\n')
            })
        )
    end
    table.insert(
        meta['header-includes'],
        pandoc.MetaInlines({
                pandoc.RawInline('latex', '\\catcode`\\℣=\\active ' ..
                                     '\\def ℣#1{{\\Vbar\\hspace{-.25ex}#1}}\n'),
                pandoc.RawInline('latex', '\\catcode`\\℟=\\active ' ..
                                     '\\def ℟#1{{\\Rbar\\hspace{-.25ex}#1}}\n'),
                pandoc.RawInline('latex', '\\catcode`\\†=\\active ' ..
                                     '\\def †{{\\GreDagger}}\n'),
                pandoc.RawInline('latex', '\\catcode`\\✠=\\active ' ..
                                     '\\def ✠{{\\grecross}}\n'),
        })
    )
    -- We need it to avoid a conflict with unicode-math.
    table.insert(
        meta['include-before'],
        pandoc.MetaInlines({
                pandoc.RawInline('latex',
                                 '\\gresimpledefbarredsymbol{V}{0.1em}\n')
        })
    )
    if meta.music and meta.music.gregorio then
        for k, v in pairs(meta.music.gregorio) do
            if not DEFAULT_PARAMS[k] then
                DEFAULT_DIMS[k] = pandoc.RawInline(
                    'latex', string.format('\\grechangedim{%s}{%s}{scalable}\n',
                                           k, v[1].text))
            else
                if v[1] then
                    DEFAULT_PARAMS[k] = v[1].text
                else
                    DEFAULT_PARAMS[k] = v
                end
            end
        end
    end
    if meta.fontsize then DEFAULT_PARAMS.fontsize = meta.fontsize[1].text end
    initialsize = 2.5 * DEFAULT_PARAMS.staffsize
    table.insert(
        meta['header-includes'],
        pandoc.MetaInlines({
                pandoc.RawInline('latex', string.format(
                                     "\\gresetinitiallines{%s}\n",
                                     DEFAULT_PARAMS.initiallines)),
                pandoc.RawInline('latex', string.format(
                                     "\\grechangestaffsize{%s}\n",
                                     DEFAULT_PARAMS.staffsize)),
                pandoc.RawInline('latex', string.format(
                                     '\\grechangedim{baselineskip}{' ..
                                         '%spt plus 5pt minus 5pt}{scalable}\n',
                                     3.3 * DEFAULT_PARAMS.staffsize)),
                pandoc.RawInline('latex', string.format(
                                     "\\grechangestyle{initial}" ..
                                         "{\\fontsize{%s}{%s}\\selectfont{}}\n",
                                     initialsize, initialsize))
        })
    )
    dimensions = {}
    for k, v in pairs(DEFAULT_DIMS) do
        table.insert(dimensions, v)
    end
    table.insert(meta['header-includes'], pandoc.MetaInlines(dimensions))
    return meta
end

local function latex_params(attrs)
    local params = {}
    local o_params = {}
    for k, v in pairs(attrs) do
        if k == 'fontsize' then
            table.insert(params,
                         string.format('\\fontsize{%s}{%s}\\selectfont{}', v, v))
        elseif k == 'staffsize' then
            initialsize = 2.5 * v
            o_initialsize = 2.5 * DEFAULT_PARAMS.staffsize
            table.insert(params,
                         string.format('\\grechangestaffsize{%s}\n' ..
                                           '\\grechangedim{baselineskip}{' ..
                                           '%spt plus 5pt minus 5pt}{scalable}\n' ..
                                           "\\grechangestyle{initial}" ..
                                           "{\\fontsize{%s}{%s}\\selectfont{}}",
                                       v, 3.3 * v, initialsize, initialsize))
            table.insert(o_params,
                         string.format('\\grechangestaffsize{%s}', DEFAULT_PARAMS.staffsize))
        elseif k == 'initiallines' then
            table.insert(params,
                         string.format('\\gresetinitiallines{%s}', v))
        elseif k == 'width' then ; -- TODO: take line width in account with tex/pdf export
        else
            table.insert(params,
                         string.format('\\grechangedim{%s}{%s}{scalable}', k, v))
        end
    end
    if #o_params > 0 then table.insert(o_params, '') end
    return {[1] = table.concat(params, '\n'), [2] = table.concat(o_params, '%\n')}
end


local function gregorio(gabc, filetype, p)
    local d = DEFAULT_DIMS
    local dims = {}
    local fn_dims = ''
    for k, v in pairs(DEFAULT_PARAMS) do
        if not p[k] then p[k] = DEFAULT_PARAMS[k] end
    end
    for k, v in orderedPairs(p) do
        if not DEFAULT_PARAMS[k] then d[k] = v end
        fn_dims = fn_dims .. '-' .. v
    end
    local fname = "tmp_gabc/"
        .. pandoc.sha1(gabc) .. fn_dims
    local iname = fname .. '.' .. filetype
    if not file_exists(iname) then
        os.execute("mkdir tmp_gabc")
        for k, v in pairs(d) do
            table.insert(dims, string.format("\\grechangedim{%s}{%s}{scalable}", k, v))
        end
        local snippet = string.format("\\gresetinitiallines{%s}\n", p.initiallines)
            .. string.format("\\grechangestaffsize{%s}\n", p.staffsize)
            .. string.format('\\grechangedim{baselineskip}' ..
                                 '{%spt plus 5pt minus 5pt}{scalable}\n',
                             3.3 * p.staffsize)
            .. string.format("\\grechangestyle{initial}{\\fontsize{%s}{%s}\\selectfont{}}\n",
                             2.5 * p.staffsize, 2.5 * p.staffsize)
            .. table.concat(dims, '\n') .. '\n'
        local i = io.open(fname .. '.tex', 'w')
        i:write(
            LATEX_DOC:format(p.fontsize, p.width, snippet .. '\\gabcsnippet{' .. gabc .. '}')
        )
        i:close()
        os.execute("lualatex -shell-escape -output-directory=tmp_gabc/ "
                       .. fname .. '.tex')
        if filetype ~= "pdf" then
            os.execute("gs -dNOPAUSE -dBATCH -sDEVICE=pngalpha -r144 "
                           .. "-sOutputFile=" .. iname
                           .. " " .. fname .. ".pdf")
        end
    end
    return pandoc.Image({pandoc.Str("partition grégorienne")}, iname)
end


local function snippet(block)
    if has_value(block.classes, "gabc") then
        if FORMAT == 'latex' then
            local params = latex_params(block.attributes)
            return pandoc.RawBlock(
                'latex',
                string.format('{%s\n\\gabcsnippet{%s}%%\n%s}',
                              params[1], block.text, params[2])
            )
        else
            local image = gregorio(block.text, filetype, block.attributes)
            return pandoc.Para({image})
        end
    end
end


local function score(content)
    if has_value(content.classes, "gabc") then
        if FORMAT == 'latex' then
            local params = latex_params(content.attributes)
            return pandoc.RawInline(
                'latex',
                string.format('{%s\n\\gregorioscore{%s}%%\n%s}',
                              params[1], content.text,params[2])
            )
        else
            local i = io.open(content.text, 'r')
            gabc = i:read('*a')
            i:close()
            local image = gregorio(gabc, filetype, content.attributes)
            return image
        end
    end
end


return {{Meta = default_params}, {CodeBlock = snippet}, {Code = score}}
