local piblib = require('piblib')
local client = piblib()

client:registerCommand({
    name = 'ping',
    handler = function()
        return 'Pong!'
    end
}, {
    pong = {
        handler = function()
            return 'Pong ping'
        end
    }
})

-- O espaço após o "Bot" é obrigatório!
client:run('Bot SEU_TOKEN')