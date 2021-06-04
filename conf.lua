scale = 2

xpadding = 8.5
ypadding = 3.5
__pico_resolution = {128, 128}


-- hd options
drawscale = 2

pointmode = "rectanglestrict" -- can be "circle", "rectangle", or "rectanglestrict"

scaledebug = false

textscale = true

defaultfontscale = 1

bootcart = "scaletest.p8"



-- don't touch beyond here! --


if defaultfontscale > scale then 
  defaultfontscale = scale
end

fontscale = defaultfontscale
if textscale then
  fontscale = drawscale
end

function love.conf(t)
	t.console = true

	t.identity = "picolove"

	-- 0.9.2  is wip
	-- 0.10.2 is default
	-- 11.3   is wip
	if t.version ~= "0.9.2" and t.version ~= "0.10.2" and t.version ~= "11.3" then
		-- show default version if no match
		t.version = "0.10.2"
	end

	t.window.title = "picolove 0.1 - (love " .. t.version .. ")"
	t.window.width = __pico_resolution[1] * drawscale * scale + xpadding * scale * 2 
	t.window.height = __pico_resolution[2] * drawscale * scale + ypadding * scale * 2
	t.window.resizable = true
end
