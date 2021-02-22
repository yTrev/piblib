local piblib = require('piblib')
local client = piblib()

client:registerCommand({
	name = 'ping',
	caseInsensitive = true,
	requirements = {
		guildOnly = true, --> Define que o comando pode ser utilizado apenas em guildas
		users = { --> Lista de usuários que podem utilizar o comando
			247086379761139712
		},
	},
	handler = function()
		return 'Pong!'
	end
})

-- O espaço após o "Bot" é obrigatório!
client:run('Bot SEU_TOKEN')