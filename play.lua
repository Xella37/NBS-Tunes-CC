
local nbsTunes = require("nbsTunes")

-- To use custom instruments, you need to map the filename in the .nbs file to a Minecraft sound id for
-- The example with custom instruments has an exploding creeper sound
-- nbsTunes.setCustomInstrument("explode1.ogg", "entity.generic.explode")
-- local music = nbsTunes.load("custom_instruments.nbs")

-- Load Doritos and Fritos, 100 gecs (converted to .nbs by Michiel)
local music = nbsTunes.load("100_gecs_Doritos_Fritos.nbs")

-- Show the parsed metadata
print(textutils.serialise(music.data.meta))

-- Play the music
music:play()
