local piblib = require('piblib')
local client = piblib({
	prefix = {'@mention', '->'}
})

client:registerCommand({
	name = 'ping',
	handler = function()
		return 'pong!'
	end
})

client:run('Bot SEU_TOKEN')