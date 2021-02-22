local piblib = require('../init')
local client = piblib({
	commandsPath = './commandsFolder'
})

client:on('ready', function()
	client:loadCommands() --> Carrega todos os comandos
end)

-- O espaço após o "Bot" é obrigatório!
client:run('Bot SEU_TOKEN')