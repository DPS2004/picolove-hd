require 'strict'
local api = require 'api'


local cart = nil
cartname = nil -- used by api.reload
local love_args = nil

pico8 = {
	clip = nil,
	fps = 30,
	resolution = __pico_resolution,
	screen = nil,
	palette = {
		{0,0,0,255},
		{29,43,83,255},
		{126,37,83,255},
		{0,135,81,255},
		{171,82,54,255},
		{95,87,79,255},
		{194,195,199,255},
		{255,241,232,255},
		{255,0,77,255},
		{255,163,0,255},
		{255,240,36,255},
		{0,231,86,255},
		{41,173,255,255},
		{131,118,156,255},
		{255,119,168,255},
		{255,204,170,255}
	},
	color = nil,
	spriteflags = {},
	map = {},
	audio_channels = {},
	sfx = {},
	music = {},
	current_music = nil,
	keypressed = {
		[0] = {},
		[1] = {}
	},
	keymap = {
		[0] = {
			[0] = {'left','kp4'},
			[1] = {'right','kp6'},
			[2] = {'up','kp8'},
			[3] = {'down','kp5'},
			[4] = {'z','c','n','kp-','kp1','insert'},
			[5] = {'x','v','m','8','kp2','delete'},
			[6] = {'return','escape'},
			[7] = {},
		},
		[1] = {
			[0] = {'s'},
			[1] = {'f'},
			[2] = {'e'},
			[3] = {'d'},
			[4] = {'tab','lshift','w'},
			[5] = {'q','a'},
			[6] = {},
			[7] = {},
		}
	},
	cursor = {0, 0},
	camera_x = 0,
	camera_y = 0,
	draw_palette = {},
	display_palette = {},
	pal_transparent = {},
	draw_shader = nil,
}

local bit = require('bit')

frametime = 1 / pico8.fps

__pico_quads = nil -- used by api.spr
__pico_spritesheet_data = nil -- used by api.sget
__pico_spritesheet = nil -- used by api.spr
__sprite_shader = nil -- used by api.spr
__text_shader = nil -- used by api.print
__display_shader = nil
local __accum = 0
local loaded_code = nil

local eol_chars = '\n'

local __audio_buffer_size = 1024


local video_frames = nil
local osc
local host_time = 0
local retro_mode = false
local paused = false
local focus = true

local __audio_channels
local __sample_rate = 22050
local channels = 1
local bits = 16

currentDirectory = '/'
local fontchars = 'abcdefghijklmnopqrstuvwxyz"\'`-_/1234567890!?[](){}.,;:<>+=%#^*~ '

function shdr_unpack(tbl)
	return unpack(tbl, 1, 17) -- change to 16 once love2d shader bug is fixed
end

function get_bits(v,s,e)
	local mask = api.shl(api.shl(1,s)-1,e)
	return api.shr(api.band(mask,v))
end

local QueueableSource = require 'QueueableSource'

function lowpass(y0,y1, cutoff)
	local RC = 1.0/(cutoff*2*3.14)
	local dt = 1.0/__sample_rate
	local alpha = dt/(RC+dt)
	return y0 + (alpha*(y1 - y0))
end

function note_to_hz(note)
	return 440*math.pow(2,(note-33)/12)
end

function love.load(argv)
	love_args = argv
	if love.system.getOS() == 'Android' then
		love.resize(love.graphics.getDimensions())
	end

	osc = {}
	-- tri
	osc[0] = function(x)
		return (api.abs((x%1)*2-1)*2-1) * 0.7
	end
	-- uneven tri
	osc[1] = function(x)
		local t = x%1
		return (((t < 0.875) and (t * 16 / 7) or ((1-t)*16)) -1) * 0.7
	end
	-- saw
	osc[2] = function(x)
		return (x%1-0.5) * 0.9
	end
	-- sqr
	osc[3] = function(x)
		return (x%1 < 0.5 and 1 or -1) * 1/3
	end
	-- pulse
	osc[4] = function(x)
		return (x%1 < 0.3125 and 1 or -1) * 1/3
	end
	-- tri/2
	osc[5] = function(x)
		x=x*4
		return (api.abs((x%2)-1)-0.5 + (api.abs(((x*0.5)%2)-1)-0.5)/2-0.1) * 0.7
	end
	-- noise
	osc[6] = function()
		local lastx=0
		local sample=0
		local lsample=0
		local tscale=note_to_hz(63)/__sample_rate
		return function(x)
			local scale=(x-lastx)/tscale
			lsample=sample
			sample=(lsample+scale*(math.random()*2-1))/(1+scale)
			lastx=x
			return math.min(math.max((lsample+sample)*4/3*(1.75-scale), -1), 1)*0.7
		end
	end
	-- detuned tri
	osc[7] = function(x)
		x=x*2
		return (api.abs((x%2)-1)-0.5 + (api.abs(((x*127/128)%2)-1)-0.5)/2) - 1/4
	end
	-- saw from 0 to 1, used for arppregiator
	osc['saw_lfo'] = function(x)
		return x%1
	end

	__audio_channels = {
		[0]=QueueableSource:new(8),
		QueueableSource:new(8),
		QueueableSource:new(8),
		QueueableSource:new(8)
	}

	for i=0,3 do
		__audio_channels[i]:play()
	end

	for i=0,3 do
		pico8.audio_channels[i]={
			oscpos=0,
			noise=osc[6]()
		}
	end

	love.graphics.clear()
	love.graphics.setDefaultFilter('nearest','nearest')
	pico8.screen = love.graphics.newCanvas(pico8.resolution[1],pico8.resolution[2])
	pico8.screen:setFilter('linear','nearest')

	local font = love.graphics.newImageFont('font.png', fontchars, 1)
	love.graphics.setFont(font)
	font:setFilter('nearest','nearest')

	love.mouse.setVisible(false)
	love.keyboard.setKeyRepeat(true)
	love.graphics.setLineStyle('rough')
	love.graphics.setPointSize(1)
	love.graphics.setLineWidth(1)

	love.graphics.origin()
	love.graphics.setCanvas(pico8.screen)
	restore_clip()

	pico8.draw_palette = {}
	pico8.display_palette = {}
	pico8.pal_transparent = {}
	for i=1,16 do
		pico8.draw_palette[i] = i
		pico8.pal_transparent[i] = i == 1 and 0 or 1
		pico8.display_palette[i] = pico8.palette[i]
	end


	pico8.draw_shader = love.graphics.newShader([[
extern float palette[16];

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
	int index = int(color.r*16.0);
	return vec4(vec3(palette[index]/16.0),1.0);
}]])
	pico8.draw_shader:send('palette',shdr_unpack(pico8.draw_palette))

	__sprite_shader = love.graphics.newShader([[
extern float palette[16];
extern float transparent[16];

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
	int index = int(floor(Texel(texture, texture_coords).r*16.0));
	float alpha = transparent[index];
	return vec4(vec3(palette[index]/16.0),alpha);
}]])
	__sprite_shader:send('palette',shdr_unpack(pico8.draw_palette))
	__sprite_shader:send('transparent',shdr_unpack(pico8.pal_transparent))

	__text_shader = love.graphics.newShader([[
extern float palette[16];

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
	vec4 texcolor = Texel(texture, texture_coords);
	if(texcolor.a == 0.0) {
		return vec4(0.0,0.0,0.0,0.0);
	}
	int index = int(color.r*16.0);
	// lookup the colour in the palette by index
	return vec4(vec3(palette[index]/16.0),1.0);
}]])
	__text_shader:send('palette',shdr_unpack(pico8.draw_palette))

	__display_shader = love.graphics.newShader([[

extern vec4 palette[16];

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
	int index = int(Texel(texture, texture_coords).r*15.0);
	// lookup the colour in the palette by index
	return palette[index]/256.0;
}]])
	__display_shader:send('palette',shdr_unpack(pico8.display_palette))

	-- load the cart
	api.clip()
	api.camera()
	api.pal()
	api.color(6)

	_load(argv[2] or 'nocart.p8')
	api.run()
end

function new_sandbox()
	return {
		-- extra functions provided by picolove
		assert=assert,
		error=error,
		log=log,
		pairs=pairs,
		ipairs=ipairs,
		warning=warning,
		setfps=setfps,
		_call=_call,
		_keydown=nil,
		_keyup=nil,
		_textinput=nil,
		_getcursorx=_getcursorx,
		_getcursory=_getcursory,
		-- pico8 api functions go here
		clip=api.clip,
		pget=api.pget,
		pset=api.pset,
		sget=api.sget,
		sset=api.sset,
		fget=api.fget,
		fset=api.fset,
		flip=api.flip,
		folder=api.folder,
		print=api.print,
		printh=log,
		cd=api.cd,
		cursor=api.cursor,
		color=api.color,
		cls=api.cls,
		camera=api.camera,
		circ=api.circ,
		circfill=api.circfill,
		help=help,
		dir=api.dir,
		line=api.line,
		load=_load,
		ls=api.ls,
		mkdir=api.mkdir,
		rect=api.rect,
		rectfill=api.rectfill,
		run=api.run,
		reload=api.reload,
		reboot=api.reboot,
		pal=api.pal,
		palt=api.palt,
		spr=api.spr,
		sspr=api.sspr,
		add=api.add,
		del=api.del,
		foreach=api.foreach,
		count=api.count,
		all=api.all,
		btn=api.btn,
		btnp=api.btnp,
		sfx=api.sfx,
		music=api.music,
		mget=api.mget,
		mset=api.mset,
		map=api.map,
		memcpy=api.memcpy,
		memset=api.memset,
		peek=api.peek,
		poke=api.poke,
		max=api.max,
		min=api.min,
		mid=api.mid,
		flr=api.flr,
		ceil=api.ceil,
		cos=api.cos,
		sin=api.sin,
		atan2=api.atan2,
		sqrt=api.sqrt,
		abs=api.abs,
		rnd=api.rnd,
		srand=api.srand,
		sgn=api.sgn,
		band=api.band,
		bor=api.bor,
		bxor=api.bxor,
		bnot=api.bnot,
		shl=api.shl,
		shr=api.shr,
		exit=api.shutdown,
		shutdown=api.shutdown,
		sub=api.sub,
		stat=api.stat,
		time=function() return host_time end,
		-- deprecated pico-8 function aliases
		mapdraw=api.map
	}
end

local __compression_map = {}
for entry in ('\n 0123456789abcdefghijklmnopqrstuvwxyz!#%(){}[]<>+=/*:;.,~_'):gmatch('.') do
	table.insert(__compression_map,entry)
end

function load_p8(filename)
	log('Loading',filename)

	local lua = ''
	pico8.map = {}
	__pico_quads = {}
	for y=0,63 do
		pico8.map[y] = {}
		for x=0,127 do
			pico8.map[y][x] = 0
		end
	end
	__pico_spritesheet_data = love.image.newImageData(128,128)
	pico8.spriteflags = {}

	pico8.sfx = {}
	for i=0,63 do
		pico8.sfx[i] = {
			speed=16,
			loop_start=0,
			loop_end=0
		}
		for j=0,31 do
			pico8.sfx[i][j] = {0,0,0,0}
		end
	end
	pico8.music = {}
	for i=0,63 do
		pico8.music[i] = {
			loop = 0,
			[0] = 1,
			[1] = 2,
			[2] = 3,
			[3] = 4
		}
	end

	if filename:sub(#filename-3,#filename) == '.png' then
		local img = love.graphics.newImage(filename)
		if img:getWidth() ~= 160 or img:getHeight() ~= 205 then
			error('Image is the wrong size')
		end
		local data = img:getData()

		local outX = 0
		local outY = 0
		local inbyte = 0
		local lastbyte = nil
		local mapY = 32
		local mapX = 0
		local version = nil
		local codelen = nil
		local code = ''
		local compressed = false
		local sprite = 0
		for y=0,204 do
			for x=0,159 do
				local r,g,b,a = data:getPixel(x,y)
				-- extract lowest bits
				r = bit.band(r,0x0003)
				g = bit.band(g,0x0003)
				b = bit.band(b,0x0003)
				a = bit.band(a,0x0003)
				data:setPixel(x,y,bit.lshift(r,6),bit.lshift(g,6),bit.lshift(b,6),255)
				local byte = b + bit.lshift(g,2) + bit.lshift(r,4) + bit.lshift(a,6)
				local lo = bit.band(byte,0x0f)
				local hi = bit.rshift(byte,4)
				if inbyte < 0x2000 then
					if outY >= 64 then
						pico8.map[mapY][mapX] = byte
						mapX = mapX + 1
						if mapX == 128 then
							mapX = 0
							mapY = mapY + 1
						end
					end
					__pico_spritesheet_data:setPixel(outX,outY,lo*16,lo*16,lo*16)
					outX = outX + 1
					__pico_spritesheet_data:setPixel(outX,outY,hi*16,hi*16,hi*16)
					outX = outX + 1
					if outX == 128 then
						outY = outY + 1
						outX = 0
						if outY == 128 then
							-- end of spritesheet, generate quads
							__pico_spritesheet = love.graphics.newImage(__pico_spritesheet_data)
							local sprite = 0
							for yy=0,15 do
								for xx=0,15 do
									__pico_quads[sprite] = love.graphics.newQuad(xx*8,yy*8,8,8,__pico_spritesheet:getDimensions())
									sprite = sprite + 1
								end
							end
							mapY = 0
							mapX = 0
						end
					end
				elseif inbyte < 0x3000 then
					pico8.map[mapY][mapX] = byte
					mapX = mapX + 1
					if mapX == 128 then
						mapX = 0
						mapY = mapY + 1
					end
				elseif inbyte < 0x3100 then
					pico8.spriteflags[sprite] = byte
					sprite = sprite + 1
				elseif inbyte < 0x3200 then
					-- music
					local _music = math.floor((inbyte-0x3100)/4)
					pico8.music[_music][inbyte%4] = bit.band(byte,0x7F)
					pico8.music[_music].loop = bit.bor(bit.rshift(bit.band(byte,0x80),7-inbyte%4),pico8.music[_music].loop)
				elseif inbyte < 0x4300 then
					-- sfx
					local _sfx = math.floor((inbyte-0x3200)/68)
					local step = (inbyte-0x3200)%68
					if step < 64 and inbyte%2 == 1 then
						local note = bit.lshift(byte,8)+lastbyte
						pico8.sfx[_sfx][(step-1)/2] = {bit.band(note,0x3f),bit.rshift(bit.band(note,0x1c0),6),bit.rshift(bit.band(note, 0xe00),9),bit.rshift(bit.band(note,0x7000),12)}
					elseif step == 65 then
						pico8.sfx[_sfx].speed = byte
					elseif step == 66 then
						pico8.sfx[_sfx].loop_start = byte
					elseif step == 67 then
						pico8.sfx[_sfx].loop_end = byte
					end
				elseif inbyte < 0x8000 then
					-- code, possibly compressed
					if inbyte == 0x4300 then
						compressed = (byte == 58)
					end
					code = code .. string.char(byte)
				elseif inbyte == 0x8000 then
					version = byte
				end
				lastbyte = byte
				inbyte = inbyte + 1
			end
		end

		-- decompress code
		log('version',version)
		if version>8 then
			error(string.format('unknown file version %d',version))
		end

		if not compressed then
			lua = code:match("(.-)%f[%z]")
		else
			-- decompress code
			local mode = 0
			local copy = nil
			local i = 8
			local codelen = bit.lshift(code:byte(5,5),8) + code:byte(6,6)
			log('codelen',codelen)
			while #lua < codelen do
				i = i + 1
				local byte = string.byte(code,i,i)
				if byte == nil then
					error('reached end of code')
				else
					if mode == 1 then
						lua = lua .. code:sub(i,i)
						mode = 0
					elseif mode == 2 then
						-- copy from buffer
						local offset = (copy - 0x3c) * 16 + bit.band(byte,0xf)
						local length = bit.rshift(byte,4) + 2

						local offset = #lua - offset
						local buffer = lua:sub(offset+1,offset+1+length-1)
						lua = lua .. buffer
						mode = 0
					elseif byte == 0x00 then
						-- output next byte
						mode = 1
					elseif byte >= 0x01 and byte <= 0x3b then
						-- output this byte from map
						lua = lua .. __compression_map[byte]
					elseif byte >= 0x3c then
						-- copy previous bytes
						mode = 2
						copy = byte
					end
				end
			end
		end

	else
		local data,size = love.filesystem.read(filename)
		if not data or size == 0 then
			error(string.format('Unable to open %s',filename))
		end
		local header = 'pico-8 cartridge // http://www.pico-8.com\nversion '
		local start = data:find('pico%-8 cartridge // http://www.pico%-8.com\nversion ')
		if start == nil then
			header = 'pico-8 cartridge // http://www.pico-8.com\r\nversion '
			start = data:find('pico%-8 cartridge // http://www.pico%-8.com\r\nversion ')
			if start == nil then
				error('invalid cart')
			end
			eol_chars = '\r\n'
		else
			eol_chars = '\n'
		end
		local next_line = data:find(eol_chars,start+#header)
		local version_str = data:sub(start+#header,next_line-1)
		local version = tonumber(version_str)
		log('version',version)
		-- extract the lua
		local lua_start = data:find('__lua__') + 7 + #eol_chars
		local lua_end = data:find('__gfx__') - 1

		lua = data:sub(lua_start,lua_end)

		-- load the sprites into an imagedata
		-- generate a quad for each sprite index
		local gfx_start = data:find('__gfx__') + 7 + #eol_chars
		local gfx_end = data:find('__gff__') - 1
		local gfxdata = data:sub(gfx_start,gfx_end)

		local row = 0
		local tile_row = 32
		local tile_col = 0
		local col = 0
		local sprite = 0
		local tiles = 0
		local shared = 0

		local next_line = 1
		while next_line do
			local end_of_line = gfxdata:find(eol_chars,next_line)
			if end_of_line == nil then break end
			end_of_line = end_of_line - 1
			local line = gfxdata:sub(next_line,end_of_line)
			for i=1,#line do
				local v = line:sub(i,i)
				v = tonumber(v,16)
				__pico_spritesheet_data:setPixel(col,row,v*16,v*16,v*16,255)

				col = col + 1
				if col == 128 then
					col = 0
					row = row + 1
				end
			end
			next_line = gfxdata:find(eol_chars,end_of_line)+#eol_chars
		end

		if version > 3 then
			local tx,ty = 0,32
			for sy=64,127 do
				for sx=0,127,2 do
					-- get the two pixel values and merge them
					local lo = api.flr(__pico_spritesheet_data:getPixel(sx,sy)/16)
					local hi = api.flr(__pico_spritesheet_data:getPixel(sx+1,sy)/16)
					local v = api.bor(api.shl(hi,4),lo)
					pico8.map[ty][tx] = v
					shared = shared + 1
					tx = tx + 1
					if tx == 128 then
						tx = 0
						ty = ty + 1
					end
				end
			end
			assert(shared == 128 * 32,shared)
		end

		for y=0,15 do
			for x=0,15 do
				__pico_quads[sprite] = love.graphics.newQuad(8*x,8*y,8,8,128,128)
				sprite = sprite + 1
			end
		end

		assert(sprite == 256,sprite)

		__pico_spritesheet = love.graphics.newImage(__pico_spritesheet_data)

		-- load the sprite flags

		local gff_start = data:find('__gff__') + 7 + #eol_chars
		local gff_end = data:find('__map__') - 1
		local gffdata = data:sub(gff_start,gff_end)

		local sprite = 0

		local next_line = 1
		while next_line do
			local end_of_line = gffdata:find(eol_chars,next_line)
			if end_of_line == nil then break end
			end_of_line = end_of_line - 1
			local line = gffdata:sub(next_line,end_of_line)
			if version <= 2 then
				for i=1,#line do
					local v = line:sub(i)
					v = tonumber(v,16)
					pico8.spriteflags[sprite] = v
					sprite = sprite + 1
				end
			else
				for i=1,#line,2 do
					local v = line:sub(i,i+1)
					v = tonumber(v,16)
					pico8.spriteflags[sprite] = v
					sprite = sprite + 1
				end
			end
			next_line = gffdata:find(eol_chars,end_of_line)+#eol_chars
		end

		assert(sprite == 256,'wrong number of spriteflags:'..sprite)

		-- convert the tile data to a table

		local map_start = data:find('__map__') + 7 + #eol_chars
		local map_end = data:find('__sfx__') - 1
		local mapdata = data:sub(map_start,map_end)

		local row = 0
		local col = 0

		local next_line = 1
		while next_line do
			local end_of_line = mapdata:find(eol_chars,next_line)
			if end_of_line == nil then
				break
			end
			end_of_line = end_of_line - 1
			local line = mapdata:sub(next_line,end_of_line)
			for i=1,#line,2 do
				local v = line:sub(i,i+1)
				v = tonumber(v,16)
				if col == 0 then
				end
				pico8.map[row][col] = v
				col = col + 1
				tiles = tiles + 1
				if col == 128 then
					col = 0
					row = row + 1
				end
			end
			next_line = mapdata:find(eol_chars,end_of_line)+#eol_chars
		end
		assert(tiles + shared == 128 * 64,string.format('%d + %d != %d',tiles,shared,128*64))

		-- load sfx
		local sfx_start = data:find('__sfx__') + 7 + #eol_chars
		local sfx_end = data:find('__music__') - 1
		local sfxdata = data:sub(sfx_start,sfx_end)

		local _sfx = 0
		local step = 0

		local next_line = 1
		while next_line do
			local end_of_line = sfxdata:find(eol_chars,next_line)
			if end_of_line == nil then break end
			end_of_line = end_of_line - 1
			local line = sfxdata:sub(next_line,end_of_line)
			local editor_mode = tonumber(line:sub(1,2),16)
			pico8.sfx[_sfx].speed = tonumber(line:sub(3,4),16)
			pico8.sfx[_sfx].loop_start = tonumber(line:sub(5,6),16)
			pico8.sfx[_sfx].loop_end = tonumber(line:sub(7,8),16)
			for i=9,#line,5 do
				local v = line:sub(i,i+4)
				assert(#v == 5)
				local note  = tonumber(line:sub(i,i+1),16)
				local instr = tonumber(line:sub(i+2,i+2),16)
				local vol   = tonumber(line:sub(i+3,i+3),16)
				local fx    = tonumber(line:sub(i+4,i+4),16)
				pico8.sfx[_sfx][step] = {note,instr,vol,fx}
				step = step + 1
			end
			_sfx = _sfx + 1
			step = 0
			next_line = sfxdata:find(eol_chars,end_of_line)+#eol_chars
		end

		assert(_sfx == 64)

		-- load music
		local music_start = data:find('__music__') + 9 + #eol_chars
		local music_end = #data-#eol_chars
		local musicdata = data:sub(music_start,music_end)

		local _music = 0

		local next_line = 1
		while next_line do
			local end_of_line = musicdata:find('\n',next_line)
			if end_of_line == nil then break end
			end_of_line = end_of_line - 1
			local line = musicdata:sub(next_line,end_of_line)

			pico8.music[_music] = {
				loop = tonumber(line:sub(1,2),16),
				[0] = tonumber(line:sub(4,5),16),
				[1] = tonumber(line:sub(6,7),16),
				[2] = tonumber(line:sub(8,9),16),
				[3] = tonumber(line:sub(10,11),16)
			}
			_music = _music + 1
			next_line = musicdata:find('\n',end_of_line)+1
		end
	end

	-- patch the lua
	lua = lua:gsub('!=','~=')
	-- rewrite shorthand if statements eg. if (not b) i=1 j=2
	lua = lua:gsub('if%s*(%b())%s*([^\n]*)\n',function(a,b)
		local nl = a:find('\n',nil,true)
		local th = b:find('%f[%w]then%f[%W]')
		local an = b:find('%f[%w]and%f[%W]')
		local o = b:find('%f[%w]or%f[%W]')
		local ce = b:find('--',nil,true)
		if not (nl or th or an or o) then
			if ce then
				local c,t = b:match("(.-)(%s-%-%-.*)")
				return 'if '..a:sub(2,-2)..' then '..c..' end'..t..'\n'
			else
				return 'if '..a:sub(2,-2)..' then '..b..' end\n'
			end
		end
	end)
	-- rewrite assignment operators
	lua = lua:gsub('(%S+)%s*([%+-%*/%%])=','%1 = %1 %2 ')

	log('finished loading cart',filename)

	loaded_code = lua

	return true
end

function love.update(dt)
	for p=0,1 do
		for i=0,#pico8.keymap[p] do
			for _,key in pairs(pico8.keymap[p][i]) do
				local v = pico8.keypressed[p][i]
				if v then
					v = v + 1
					pico8.keypressed[p][i] = v
					break
				end
			end
		end
	end
	if cart._update then cart._update() end
end

function love.resize(w,h)
	love.graphics.clear()
	-- adjust stuff to fit the screen
	if w > h then
		scale = h/(pico8.resolution[2]+ypadding*2)
	else
		scale = w/(pico8.resolution[1]+xpadding*2)
	end
end

function love.run()
	if love.math then
		love.math.setRandomSeed(os.time())
		for i=1,3 do love.math.random() end
	end

	if love.event then
		love.event.pump()
	end

	if love.load then love.load(arg) end

	-- We don't want the first frame's dt to include time taken by love.load.
	if love.timer then love.timer.step() end

	local dt = 0

	-- Main loop time.
	while true do
		-- Process events.
		if love.event then
			love.event.pump()
			for e,a,b,c,d in love.event.poll() do
				if e == 'quit' then
					if not love.quit or not love.quit() then
						if love.audio then
							love.audio.stop()
						end
						return
					end
				end
				love.handlers[e](a,b,c,d)
			end
		end

		-- Update dt, as we'll be passing it to update
		if love.timer then
			love.timer.step()
			dt = dt + love.timer.getDelta()
		end

		-- Call update and draw
		local render = false
		while dt > frametime do
			host_time = host_time + dt
			if host_time > 65536 then host_time = host_time - 65536 end
			if paused or not focus then
			else
				if love.update then love.update(frametime) end -- will pass 0 if love.timer is disabled
				update_audio(frametime)
			end
			dt = dt - frametime
			render = true
		end

		if render and love.window and love.graphics and love.window.isCreated() then
			love.graphics.origin()
			if not paused and focus then
				if love.draw then love.draw() end
			end
		end

		if love.timer then love.timer.sleep(0.001) end
	end
end

function love.focus(f)
	focus = f
end

note_map = {
	[0] = 'C-',
	'C#',
	'D-',
	'D#',
	'E-',
	'F-',
	'F#',
	'G-',
	'G#',
	'A-',
	'A#',
	'B-',
}

function note_to_string(note)
	local octave = api.flr(note/12)
	local note = api.flr(note%12)
	return string.format('%s%d',note_map[note],octave)
end

local function oldosc(osc)
	local x=0
	return function(freq)
		x=x+freq/__sample_rate
		return osc(x)
	end
end

function update_audio(time)
	-- check what sfx should be playing
	local samples = api.flr(time*__sample_rate)

	for i=0,samples-1 do
		if pico8.current_music then
			pico8.current_music.offset = pico8.current_music.offset + 7350/(61*pico8.current_music.speed*__sample_rate)
			if pico8.current_music.offset >= 32 then
				local next_track = pico8.current_music.music
				if pico8.music[next_track].loop == 2 then
					-- go back until we find the loop start
					while true do
						if pico8.music[next_track].loop == 1 or next_track == 0 then
							break
						end
						next_track = next_track - 1
					end
				elseif pico8.music[pico8.current_music.music].loop == 4 then
					next_track = nil
				elseif pico8.music[pico8.current_music.music].loop <= 1 then
					next_track = next_track + 1
				end
				if next_track then
					api.music(next_track)
				end
			end
		end
		local music = pico8.current_music and pico8.music[pico8.current_music.music] or nil

		for channel=0,3 do
			local ch = pico8.audio_channels[channel]
			local tick = 0
			local tickrate = 60*16
			local note,instr,vol,fx
			local freq

			if ch.bufferpos == 0 or ch.bufferpos == nil then
				ch.buffer = love.sound.newSoundData(__audio_buffer_size,__sample_rate,bits,channels)
				ch.bufferpos = 0
			end
			if ch.sfx and pico8.sfx[ch.sfx] then
				local sfx = pico8.sfx[ch.sfx]
				ch.offset = ch.offset + 7350/(61*sfx.speed*__sample_rate)
				if sfx.loop_end ~= 0 and ch.offset >= sfx.loop_end then
					if ch.loop then
						ch.last_step = -1
						ch.offset = sfx.loop_start
					else
						pico8.audio_channels[channel].sfx = nil
					end
				elseif ch.offset >= 32 then
					pico8.audio_channels[channel].sfx = nil
				end
			end
			if ch.sfx and pico8.sfx[ch.sfx] then
				local sfx = pico8.sfx[ch.sfx]
				-- when we pass a new step
				if api.flr(ch.offset) > ch.last_step then
					ch.lastnote = ch.note
					ch.note,ch.instr,ch.vol,ch.fx = unpack(sfx[api.flr(ch.offset)])
					if ch.instr ~= 6 then
						ch.osc = osc[ch.instr]
					else
						ch.osc = ch.noise
					end
					if ch.fx == 2 then
						ch.lfo = oldosc(osc[0])
					elseif ch.fx >= 6 then
						ch.lfo = oldosc(osc['saw_lfo'])
					end
					if ch.vol > 0 then
						ch.freq = note_to_hz(ch.note)
					end
					ch.last_step = api.flr(ch.offset)
				end
				if ch.vol and ch.vol > 0 then
					local vol = ch.vol
					if ch.fx == 1 then
						-- slide from previous note over the length of a step
						ch.freq = lerp(note_to_hz(ch.lastnote or 0),note_to_hz(ch.note),ch.offset%1)
					elseif ch.fx == 2 then
						-- vibrato one semitone?
						ch.freq = lerp(note_to_hz(ch.note),note_to_hz(ch.note+0.5),ch.lfo(4))
					elseif ch.fx == 3 then
						-- drop/bomb slide from note to c-0
						local off = ch.offset%1
						--local freq = lerp(note_to_hz(ch.note),note_to_hz(0),off)
						local freq = lerp(note_to_hz(ch.note),0,off)
						ch.freq = freq
					elseif ch.fx == 4 then
						-- fade in
						vol = lerp(0,ch.vol,ch.offset%1)
					elseif ch.fx == 5 then
						-- fade out
						vol = lerp(ch.vol,0,ch.offset%1)
					elseif ch.fx == 6 then
						-- fast appreggio over 4 steps
						local off = bit.band(api.flr(ch.offset),0xfc)
						local lfo = api.flr(ch.lfo(8)*4)
						off = off + lfo
						local note = sfx[api.flr(off)][1]
						ch.freq = note_to_hz(note)
					elseif ch.fx == 7 then
						-- slow appreggio over 4 steps
						local off = bit.band(api.flr(ch.offset),0xfc)
						local lfo = api.flr(ch.lfo(4)*4)
						off = off + lfo
						local note = sfx[api.flr(off)][1]
						ch.freq = note_to_hz(note)
					end
					ch.sample = ch.osc(ch.oscpos) * vol/7
					ch.oscpos = ch.oscpos + ch.freq/__sample_rate
					ch.buffer:setSample(ch.bufferpos,ch.sample)
				else
					ch.buffer:setSample(ch.bufferpos,lerp(ch.sample or 0,0,0.1))
					ch.sample = 0
				end
			else
				ch.buffer:setSample(ch.bufferpos,lerp(ch.sample or 0,0,0.1))
				ch.sample = 0
			end
			ch.bufferpos = ch.bufferpos + 1
			if ch.bufferpos == __audio_buffer_size then
				-- queue buffer and reset
				__audio_channels[channel]:queue(ch.buffer)
				__audio_channels[channel]:play()
				ch.bufferpos = 0
			end
		end
	end
end

function flip_screen()
	love.graphics.setShader(__display_shader)
	__display_shader:send('palette',shdr_unpack(pico8.display_palette))
	love.graphics.setCanvas()
	love.graphics.origin()

	-- love.graphics.setColor(255,255,255,255)
	love.graphics.setScissor()

	love.graphics.setBackgroundColor(3, 5, 10)
	love.graphics.clear()

	local screen_w,screen_h = love.graphics.getDimensions()
	if screen_w > screen_h then
		love.graphics.draw(pico8.screen,screen_w/2-64*scale,ypadding*scale,0,scale,scale)
	else
		love.graphics.draw(pico8.screen,xpadding*scale,screen_h/2-64*scale,0,scale,scale)
	end

	love.graphics.present()

	if video_frames then
		local tmp = love.graphics.newCanvas(pico8.resolution[1],pico8.resolution[2])
		love.graphics.setCanvas(tmp)
		love.graphics.draw(pico8.screen,0,0)
		table.insert(video_frames,tmp:getImageData())
	end
	-- get ready for next time
	love.graphics.setShader(pico8.draw_shader)
	love.graphics.setCanvas(pico8.screen)
	restore_clip()
	restore_camera()
end

function love.draw()
	love.graphics.setCanvas(pico8.screen)
	restore_clip()
	restore_camera()

	love.graphics.setShader(pico8.draw_shader)

	-- run the cart's draw function
	if cart._draw then cart._draw() end

	-- draw the contents of pico screen to our screen
	flip_screen()
end

function love.keypressed(key)
	if key == 'r' and (love.keyboard.isDown('lctrl') or love.keyboard.isDown('lgui')) then
		api.reload()
		api.run()
	elseif key == 'q' and (love.keyboard.isDown('lctrl') or love.keyboard.isDown('lgui')) then
		love.event.quit()
	elseif key == 'pause' then
		paused = not paused
	elseif key == 'f6' then
		-- screenshot
		local screenshot = love.graphics.newScreenshot(false)
		local filename = cartname..'-'..os.time()..'.png'
		screenshot:encode(filename)
		log('saved screenshot to',filename)
	elseif key == 'f8' then
		-- start recording
		video_frames = {}
	elseif key == 'f9' then
		-- stop recording and save
		local basename = cartname..'-'..os.time()..'-'
		for i,v in ipairs(video_frames) do
			v:encode(string.format('%s%04d.png',basename,i))
		end
		video_frames = nil
		log('saved video to',basename)
	elseif key == 'return' and (love.keyboard.isDown('lalt') or love.keyboard.isDown('ralt')) then
		love.window.setFullscreen(not love.window.getFullscreen(), 'desktop')
	else
		for p=0,1 do
			for i=0,#pico8.keymap[p] do
				for _,testkey in pairs(pico8.keymap[p][i]) do
					if key == testkey then
						pico8.keypressed[p][i] = -1 -- becomes 0 on the next frame
						break
					end
				end
			end
		end
	end
	if cart and cart._keydown then
		return cart._keydown(key)
	end
end

function love.keyreleased(key)
	for p=0,1 do
		for i=0,#pico8.keymap[p] do
			for _,testkey in pairs(pico8.keymap[p][i]) do
				if key == testkey then
					pico8.keypressed[p][i] = nil
					break
				end
			end
		end
	end
	if cart and cart._keyup then
		return cart._keyup(key)
	end
end

function love.textinput(text)
	text = text:lower()
	local validchar = false
	for i = 1,#fontchars do
		if fontchars:sub(i,i) == text then
			validchar = true
			break
		end
	end
	if validchar and cart and cart._textinput then
		return cart._textinput(text)
	end
end

function restore_clip()
	if pico8.clip then
		love.graphics.setScissor(unpack(pico8.clip))
	else
		love.graphics.setScissor(0,0,pico8.resolution[1],pico8.resolution[2])
	end
end

assert(bit.band(0x01,bit.lshift(1,0)) ~= 0)
assert(bit.band(0x02,bit.lshift(1,1)) ~= 0)
assert(bit.band(0x04,bit.lshift(1,2)) ~= 0)

assert(bit.band(0x05,bit.lshift(1,2)) ~= 0)
assert(bit.band(0x05,bit.lshift(1,0)) ~= 0)
assert(bit.band(0x05,bit.lshift(1,3)) == 0)

function scroll(pixels)
	local base = 0x6000
	local delta = base + pixels*0x40
	local basehigh = 0x8000
	api.memcpy(base, delta, basehigh-delta)
end

log = print

function _getcursorx()
	return pico8.cursor[1]
end

function _getcursory()
	return pico8.cursor[2]
end

function api.color(c)
	c = c and api.flr(c) or 0
	assert(c >= 0 and c <= 16,string.format('c is %s',c))
	pico8.color = c
	love.graphics.setColor(c*16,0,0,255)
end

pico8.camera_x = 0
pico8.camera_y = 0

function api.camera(x,y)
	if type(x) == 'number' then
		pico8.camera_x = api.flr(x)
		pico8.camera_y = api.flr(y)
	else
		pico8.camera_x = 0
		pico8.camera_y = 0
	end
	restore_camera()
end

function restore_camera()
	love.graphics.origin()
	love.graphics.translate(-pico8.camera_x,-pico8.camera_y)
end

function _plot4points(points,cx,cy,x,y)
	_horizontal_line(points, cx - x, cy + y, cx + x)
	if y ~= 0 then
		_horizontal_line(points, cx - x, cy - y, cx + x)
	end
end

function _horizontal_line(points,x0,y,x1)
	for x=x0,x1 do
		table.insert(points,{x,y})
	end
end

function help()
	api.print('')
	api.color(12)
	api.print('commands')
	api.print('')
	api.color(6)
	api.print('load <filename>  save <filename>')
	api.print('run              resume')
	api.print('shutdown         reboot')
	api.print('install_demos    dir')
	api.print('cd <dirname>     mkdir <dirname>')
	api.print('cd ..   go up a directory')
	api.print('')
	api.print('alt+enter to toggle fullscreen')
	api.print('alt+f4 or command+q to fastquit')
	api.print('')
	api.color(12)
	api.print('see readme.md for more info')
	api.print('or visit: github.com/picolove')
	api.print('')
end

function _call(code)
	local ok,f,e = pcall(load,code,'repl')
	if not ok or f==nil then
		api.print('syntax error', nil, nil, 14)
		api.print(api.sub(e,20), nil, nil, 6)
		return false
	else
		local result
		setfenv(f,cart)
		ok,e = pcall(f)
		if not ok then
			api.print('runtime error', nil, nil, 14)
			api.print(api.sub(e,20), nil, nil, 6)
		end
	end
	return true
end

function _load(_cartname)
	local ext = {'','.p8','.p8.png','.png'}
	local cart_no_ext = _cartname

	if _cartname:sub(-3) == '.p8' then
		ext = {'.p8','.p8.png'}
		cart_no_ext = _cartname:sub(1,-4)
	elseif _cartname:sub(-7) == '.p8.png' then
		ext = {'.p8.png'}
		cart_no_ext = _cartname:sub(1,-8)
	elseif _cartname:sub(-4) == '.png' then
		ext = {'.png', '.p8.png'}
		cart_no_ext = _cartname:sub(1,-5)
	end

	local file_found = false
	for i=1,#ext do
		if love.filesystem.isFile(currentDirectory..cart_no_ext..ext[i]) then
			file_found = true
			_cartname = cart_no_ext..ext[i]
			break
		end
	end

	if not file_found then
		api.print('could not load', nil, nil, 6)
		return
	end

	love.graphics.setShader(pico8.draw_shader)
	love.graphics.setCanvas(pico8.screen)
	love.graphics.origin()
	api.camera()
	restore_clip()
	cartname = _cartname
	if load_p8(currentDirectory.._cartname) then
		api.print('loaded '.._cartname, nil, nil, 6)
	end
end

function api.run()
	love.graphics.setCanvas(pico8.screen)
	love.graphics.setShader(pico8.draw_shader)
	restore_clip()
	love.graphics.origin()

	cart = new_sandbox()

	local ok,f,e = pcall(load,loaded_code,cartname)
	if not ok or f==nil then
		log('=======8<========')
		log(loaded_code)
		log('=======>8========')
		error('Error loading lua: '..tostring(e))
	else
		local result
		setfenv(f,cart)
		love.graphics.setShader(pico8.draw_shader)
		love.graphics.setCanvas(pico8.screen)
		love.graphics.origin()
		restore_clip()
		ok,result = pcall(f)
		if not ok then
			error('Error running lua: '..tostring(result))
		else
			log('lua completed')
		end
	end

	if cart._init then cart._init() end
end

function api.reboot()
	_load('nocart.p8')
	api.run()
end

function warning(msg)
	log(debug.traceback('WARNING: '..msg,3))
end

assert(api.min(1, 2) == 1)
assert(api.min(2, 1) == 1)

assert(api.max(1, 2) == 2)
assert(api.max(2, 1) == 2)

assert(api.mid(1, 2, 3) == 2)
assert(api.mid(1, 3, 2) == 2)
assert(api.mid(2, 1, 3) == 2)
assert(api.mid(2, 3, 1) == 2)
assert(api.mid(3, 1, 2) == 2)
assert(api.mid(3, 2, 1) == 2)

assert(api.atan2(1, 0) == 0)
assert(api.atan2(0,-1) == 0.25)
assert(api.atan2(-1,0) == 0.5)
assert(api.atan2(0, 1) == 0.75)

function api.shutdown()
	love.event.quit()
end

love.graphics.point = function(x,y)
	love.graphics.rectangle('fill',x,y,1,1)
end

function setfps(fps)
	pico8.fps = api.flr(fps)
	if pico8.fps <= 0 then
		pico8.fps = 30
	end
	frametime = 1 / pico8.fps
end

function lerp(a,b,t)
	return (1-t)*a+t*b
end
