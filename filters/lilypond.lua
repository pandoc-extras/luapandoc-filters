-- Pandoc filter to process code blocks with class "ly" containing
-- lilypond notation.
--
-- * Assumes that Lilypond and Ghostscript are installed, plus
-- * [lyluatex](https://github.com/jperon/lyluatex) package for
-- * LaTeX, with LuaLaTeX.


os.execute("mkdir tmp_ly")


local filetypes = { html = {"png", "image/png"}
                  , latex = {"pdf", "application/pdf"}
                  }
local filetype = "png"
local mimetype = "image/png"
if filetypes[FORMAT] then
    filetype = filetypes[FORMAT][1] or "png"
    mimetype = filetypes[FORMAT][2] or "image/png"
end

local DEFAULT_PARAMS = {["staffsize"] = 20, ["width"] = "210mm"}
local LILY = [[\version "2.18.2"
#(define default-toplevel-book-handler
  print-book-with-defaults-as-systems )

#(define toplevel-book-handler
  (lambda ( . rest)
  (set! output-empty-score-list #f)
  (apply print-book-with-defaults rest)))

#(define toplevel-music-handler
  (lambda ( . rest)
   (apply collect-music-for-book rest)))

#(define toplevel-score-handler
  (lambda ( . rest)
   (apply collect-scores-for-book rest)))

#(define toplevel-text-handler
  (lambda ( . rest)
   (apply collect-scores-for-book rest)))

\paper{
indent=0\mm
oddFooterMarkup=##f
oddHeaderMarkup=##f
bookTitleMarkup = ##f
scoreTitleMarkup = ##f
line-width = %s
}
#(set-global-staff-size %s)

]]


local function file_exists(name)
    local f = io.open(name, 'r')
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
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


local function default_params(meta)
    if not meta['header-includes'] then
        meta['header-includes'] = pandoc.MetaList({})
    end
    if not contains(meta['header-includes'], '\\usepackage{lyluatex}\n') then
        table.insert(meta['header-includes'],
                     pandoc.MetaInlines({pandoc.RawInline('latex', '\\usepackage{lyluatex}\n')}))
    end
    if meta.music and meta.music.lilypond then
        for k, v in pairs(meta.music.lilypond) do
            if v[1] then
                DEFAULT_PARAMS[k] = v[1].text
            else
                DEFAULT_PARAMS[k] = v
            end
        end
    end
    return meta
end


function integral_content(original)
    local content =""
    --    for i, Line in ipairs(original:explode('\n')) do
    for i, Line in ipairs(original:explode('\n')) do
	if Line:find("^%s*[^%%]*\\include") then
	    local i = io.open(Line:gsub('%s*\\include%s*"(.*)"%s*$', "%1"), 'r')
	    if i then
		content = content .. integral_content(i:read('*a'))
	    else
		content = content .. Line .. "\n"
	    end
	else
	    content = content .. Line .. "\n"
	end
    end
    return content
end


local function lilypond(ly, filetype, params)
    local staffsize = params.staffsize or DEFAULT_PARAMS.staffsize
    local width = params.width or DEFAULT_PARAMS.width
    local fname = "tmp_ly/"
        .. pandoc.sha1(ly) .. "-" .. staffsize .. "-" .. width
    local iname
    local images = {}
    if not file_exists(fname .. "-systems.count") then
        pandoc.pipe("lilypond",{"-dno-point-and-click", "-djob-count=2",
                                "-dbackend=eps", "-ddelete-intermediate-files",
                                "-o", fname, "-"},
                    LILY:format(width:gsub("(%a+)", "\\%1"), staffsize) .. ly)
    end
    local i = io.open(fname .. '-systems.count', 'r')
    local n = tonumber(i:read('*a'))
    i:close()
    for i = 1, n, 1 do
        iname = fname .. "-" .. i .. "." .. filetype
        if filetype ~= "pdf" and not file_exists(iname) then
            os.execute("gs -dNOPAUSE -dBATCH -sDEVICE=pngalpha -r144 "
                           .. "-sOutputFile=" .. iname
                           .. " " .. fname .. "-" .. i .. ".pdf")
        end
        if i > 1 then table.insert(images, pandoc.LineBreak()) end
        table.insert(images, pandoc.Image({pandoc.Str("partition")}, iname))
    end
    return images
end


local function snippet(block)
    if has_value(block.classes, "ly") then
        if FORMAT == 'latex' then
            local staffsize = block.attributes.staffsize or DEFAULT_PARAMS.staffsize
            local width = block.attributes.width or DEFAULT_PARAMS.width
            return pandoc.RawBlock(
                'latex',
                string.format('\\lily[staffsize=%s]{%s}', staffsize, block.text)
            )
        else
            local images = lilypond(integral_content(block.text), filetype, block.attributes)
            return pandoc.Para(images)
        end
    end
end


local function score(content)
    if has_value(content.classes, "ly") then
        if FORMAT == 'latex' then
            local staffsize = content.attributes.staffsize or DEFAULT_PARAMS.staffsize
            local width = content.attributes.width or DEFAULT_PARAMS.width
            return pandoc.RawInline(
                'latex',
                string.format('\\includely[staffsize=%s]{%s}', staffsize, content.text)
            )
        else
            local i = io.open(content.text, 'r')
            ly = i:read('*a')
            i:close()
            local images = lilypond(integral_content(ly), filetype, content.attributes)
            return images
        end
    end
end


return {{Meta = default_params}, {CodeBlock = snippet}, {Code = score}}
