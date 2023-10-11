
-- Made by Xella
-- Based on the following repo:
-- https://github.com/rphsoftware/oc-nbs-player/blob/master/standalone/nbs_play.lua

local customInstrumentMapping = {}
local function setCustomInstrument(filename, soundId)
	customInstrumentMapping[filename] = soundId
end

local function parse(path)
	local file = fs.open(path, "rb")
	if not file then
		error("Could not find music file: " .. path)
	end

	local nbsRaw = file:readAll()
	nbsRaw = string.gsub(nbsRaw, "\r\n", "\n")
	file.close()

	local seekPos = 1

	local byte = string.byte
	local blshift = bit.blshift

	local function readInteger()
		local buffer = nbsRaw:sub(seekPos, seekPos+3)
		seekPos = seekPos + 4

		if not buffer or #buffer < 4 then return nil end

		local byte1 = byte(buffer, 1)
		local byte2 = byte(buffer, 2)
		local byte3 = byte(buffer, 3)
		local byte4 = byte(buffer, 4)

		return byte1 + blshift(byte2, 8) + blshift(byte3, 16) + blshift(byte4, 24)
	end

	local function readShort()
		local buffer = nbsRaw:sub(seekPos, seekPos+1)
		seekPos = seekPos + 2

		if not buffer or #buffer < 2 then return end

		local byte1 = byte(buffer, 1)
		local byte2 = byte(buffer, 2)

		return byte1 + blshift(byte2, 8)
	end

	local function readByte()
		local buffer = nbsRaw:sub(seekPos, seekPos)
		seekPos = seekPos + 1

		if not buffer then return end

		return byte(buffer, 1)
	end

	local function readString()
		local length = readInteger()
		if length then
			local txt = nbsRaw:sub(seekPos, seekPos + length - 1)
			seekPos = seekPos + length
			return txt
		end
	end

	-- Metadata
	local song = {}
	song.zeros = readShort() -- new in version 1
	local legacy = song.zeros ~= 0
	local version = 0

	if legacy then
		song.length = song.zeros -- zeros don't exist in v0, so use those bytes for length
		song.zeros = nil
	else
		version = readByte()
		song.nbs_version = version
		song.vanilla_instrument_count = readByte()

		if version >= 3 then -- zeros replaced song length, but was added back in in v3
			song.length = readShort()
		end
	end
	song.layer_count = readShort() --- called height in legacy
	song.name = readString()
	song.author = readString()
	song.ogauthor = readString()
	song.desc = readString()
	song.tempo = readShort() or 1000
	song.auto_save = readByte()
	song.auto_save_duration = readByte()
	song.time_signature = readByte()
	song.minutes_spent = readInteger()
	song.left_clicks = readInteger()
	song.right_clicks = readInteger()
	song.note_blocks_added = readInteger()
	song.note_blocks_removed = readInteger()
	song.import_name = readString()
	if version >= 4 then
		song.loop = readByte()
		song.max_loops = readByte()
		song.loop_start_tick = readShort()
	end

	-- song.tempo is 100 * the t/s, we compute the delay (or seconds per tick) to use when playing the audio
	local ticksPerSecond = song.tempo / 100
	local delay = 1 / ticksPerSecond

	local ticks = {}
	local currenttick = -1

	while true do
		-- We skip by step layers ahead
		local step = readShort()

		-- A zero step means we go to the next part (which we don't need so we just ignore that)
		if step == 0 then
			break
		end

		currenttick = currenttick + step

		-- lpos is the current layer (in the internal structure, we ignore NBS's editor layers for convenience)
		local lpos = 1
		ticks[currenttick] = {}

		local currentLayer = -1
		while true do
			-- Check how big the jump from this note to the next one is
			local jump = readShort()
			currentLayer = currentLayer + jump

			-- If its zero, we should go to the next tick
			if jump == 0 then
				break
			end

			-- But if its not, we read the instrument and note number
			local inst = readByte() + 1 -- +1 so it starts at 1
			local note = readByte()
			local velocity, panning, note_block_pitch
			if not legacy then
				if version >= 4 then -- note panning, velocity and note block fine pitch added in v4
					velocity = readByte() / 100
					panning = readByte() - 100
					note_block_pitch = readShort()
				end
			end

			-- And add them to the internal structure
			ticks[currenttick][lpos] = {
				inst = inst,
				note = note,
				velocity = velocity or 1,
				panning = panning or 0,
				fine_pitch = note_block_pitch,
				layer = currentLayer+1,
			}
			lpos = lpos + 1
		end
	end

	-- we now parse the headers
	local layers = {}
	for i = 1, song.layer_count do
		local name = readString()
		local locked, velocity, panning
		if version > 0 then
			locked = readByte()
			velocity = readByte() / 100
			panning = readByte() - 100
		end

		local layer = {
			name = name,
			locked = locked,
			velocity = velocity or 1,
			panning = panning or 0,
		}
		layers[i] = layer
	end

	for i = 0, currenttick do
		local tick = ticks[i]
		if tick then
			for j = 1, #tick do
				local sound = tick[j]
				local layerNr = sound.layer
				local layer = layers[layerNr]
				sound.velocity_layer = layer.velocity
				sound.panning_layer = layer.panning
			end
		end
	end

	-- parse custom instruments
	local customInstrumentCount = readByte()
	local customInstruments = {}
	if customInstrumentCount then
		for i = 1, customInstrumentCount do
			local name = readString()
			local file = readString()
			local pitch = readByte()
			local press_key = readByte()

			local instrument = {
				name = name,
				file = file,
				sound_id = customInstrumentMapping[file],
				pitch = pitch,
				press_key = press_key,
			}
			customInstruments[i] = instrument
		end
	end

	return {
		meta = song,
		delay = delay,
		ticks = ticks,
		finalTick = currenttick,
		layers = layers,
		customInstruments = customInstruments,
	}
end

local instruments = {
	"harp", --0 = Piano (Air)
	"bass", --1 = Double Bass (Wood)
	"basedrum", --2 = Bass Drum (Stone)
	"snare", --3 = Snare Drum (Sand)
	"hat", --4 = Click (Glass)
	"guitar", --5 = Guitar (Wool)
	"flute", --6 = Flute (Clay)
	"bell", --7 = Bell (Block of Gold)
	"chime", --8 = Chime (Packed Ice)
	"xylophone", --9 = Xylophone (Bone Block)
	"iron_xylophone", --10 = Iron Xylophone (Iron Block)
	"cow_bell", --11 = Cow Bell (Soul Sand)
	"didgeroo", --12 = Didgeridoo (Pumpkin)
	"bit", --13 = Bit (Block of Emerald)
	"banjo", --14 = Banjo (Hay)
	"pling", --15 = Pling (Glowstone)
}

local octavesOffset = {
	1, --0 = Piano (Air)
	1, --1 = Double Bass (Wood)
	0, --2 = Bass Drum (Stone)
	0, --3 = Snare Drum (Sand)
	0, --4 = Click (Glass)
	2, --5 = Guitar (Wool)
	4, --6 = Flute (Clay)
	5, --7 = Bell (Block of Gold)
	5, --8 = Chime (Packed Ice)
	5, --9 = Xylophone (Bone Block)
	3, --10 = Iron Xylophone (Iron Block)
	4, --11 = Cow Bell (Soul Sand)
	1, --12 = Didgeridoo (Pumpkin)
	3, --13 = Bit (Block of Emerald)
	3, --14 = Banjo (Hay)
	3, --15 = Pling (Glowstone)
}

local function loadMusic(path, speaker)
	if not speaker then
		speaker = peripheral.find("speaker")
		if not speaker and periphemu then
			periphemu.create("top", "speaker")
			speaker = peripheral.find("speaker")
		end
	end

	local rawData = parse(path)

	local music = {
		speaker = speaker,
		data = rawData,
		length = rawData.finalTick,
		playing = false,
	}

	local ticks = rawData.ticks
	local delay = rawData.delay

	local playingCheck = false -- used to access more quickly when checking if still playing
	local currentTick = 0
	local loopCounter = 0

	function music:play()
		self.playing = true
		playingCheck = true

		local function playTick(tick)
			for j = 1, #tick do
				local sound = tick[j]
				local inst = sound.inst
				local octOffset = octavesOffset[inst] or 4
				local velocity = sound.velocity * sound.velocity_layer

				local note = (sound.note - 9 - (octOffset-1)*12)
				if note > 24 then
					note = note % 12 + 12
				elseif note < 0 then
					note = note % 12
				end

				if inst <= 16 then
					local instrument = instruments[inst]
					speaker.playNote(instrument, velocity, note)
				else
					local instrument = rawData.customInstruments[inst - 16].sound_id
					speaker.playSound(instrument)
				end
			end
		end

		local length = self.length
		while playingCheck do
			local tick = ticks[currentTick]
			if tick then playTick(tick) end

			local found = false
			local waitTicks = 0
			for j = currentTick+1, length do
				if ticks[j] then
					found = true
					waitTicks = j - currentTick
					currentTick = j
					break
				end
			end
			if not found then
				-- music ends
				if rawData.meta.loop == 1 then
					-- figure out loop stuff
					if rawData.meta.max_loops > 0 and loopCounter >= rawData.meta.max_loops then
						-- looped enough, so stop
						loopCounter = 0
						currentTick = 0
						break
					else
						-- loop another time
						currentTick = rawData.meta.loop_start_tick
						loopCounter = loopCounter + 1
					end
				else
					break -- stop playing
				end
			end

			sleep(delay * waitTicks)
		end

		-- music finished playing
		playing = false
		playingCheck = false
	end

	function music:pause()
		self.playing = false
		playingCheck = false
	end

	function music:reset()
		currentTick = 0
		loopCounter = 0
	end

	function music:stop()
		self:pause()
		self:reset()
	end

	return music
end

return {
	parseRaw = parse,
	load = loadMusic,
	setCustomInstrument = setCustomInstrument,
}
