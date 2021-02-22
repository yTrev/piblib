local piblib = require('piblib')
local client = piblib({
	prefix = {'@mention', '->', '>'}, --> Define as prefixes padrões
	defaultOptions = {
		caseInsensitive = true --> Todos os comandos que não tiverem essa opção, terão ela como true
	}
})

client:registerCommand({
	name = 'ping',
	handler = function()
		return 'Pong!'
	end
})

-- O espaço após o "Bot" é obrigatório!
client:run('Bot SEU_TOKEN')