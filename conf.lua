scale = 1

xpadding = 8.5
ypadding = 3.5
__pico_resolution = {128, 128}


-- picolove-hd options
drawscale = 4

pointmode = "rectangle" -- can be "circle", "rectangle", or "rectanglestrict"

spritereplace = true

textscale = true

fontscale = 2

bootcart = "scaletest.p8"

assetdir = "cartfiles/"

autosavecartdata = true

cartdatadirectory = "cartdata/"


scaledebug = false

-- don't touch beyond here! --


if fontscale > drawscale then 
  defaultfontscale = drawscale
end

spritescale = 1



if not textscale then
  fontscale = 1
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
