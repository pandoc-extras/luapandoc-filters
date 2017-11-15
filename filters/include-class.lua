-- Use the file named in the code block to substitute the block content.
function CodeBlock (elem)
  if elem.classes[1] == 'include' then
    table.remove(elem.classes, 1)
    local f = io.open(elem.text:gsub('\n', ''), 'r')
    elem.text = f:read('*a')
    return elem
  end
end
