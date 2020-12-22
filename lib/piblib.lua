-- Modulos --
local discordia = require('discordia')
local pathjoin = require('pathjoin')
local fs = require('fs')
local timer = require('timer')
local uv = require('uv')
local constants = require('./constants')

discordia.extensions()

-- Localização das globais/funções --
local class = discordia.class
local Client = discordia.Client

local gsub = string.gsub
local find = string.find
local len = string.len
local sub = string.sub
local trim = string.trim
local split = string.split
local lower = string.lower
local format = string.format

local remove = table.remove
local insert = table.insert
local wrap = coroutine.wrap

local splitPath = pathjoin.splitPath
local readFileSync = fs.readFileSync
local setTimeout = timer.setTimeout
local isInstance = class.isInstance
local hrtime = uv.hrtime
local readdirRecursive

local Message = class.classes.Message

-- Constants --
local DEFAULT_SETTINGS = constants.DEFAULT_SETTINGS
local SPLIT_PATTERN = constants.SPLIT_PATTERN
local OBRIGATORY_PROPERTIES = constants.OBRIGATORY_PROPERTIES
local NANO_IN_MS = 1000000

---@class Piblib
local Piblib, get = class('piblib', Client)

---@param str string @A string que vai ser separada
---@return table @A string dividida
local function getArguments(str)
	return split(trim(str), SPLIT_PATTERN)
end

---@param commandOptions table | nil
---@param clientOptions table | nil
---@return Piblib
function Piblib:__init(commandOptions, clientOptions)
	-- Inicializando o Client.
	Client.__init(self, clientOptions)

	if commandOptions then
		for name, value in pairs(DEFAULT_SETTINGS) do
			if not commandOptions[name] then
				commandOptions[name] = value
			end
		end
	else
		commandOptions = DEFAULT_SETTINGS
	end

	self._commands = {}
	self._cooldowns = {}
	self._prefixes = {}

	self._ignoreSelf = commandOptions.ignoreSelf
	self._ignoreBots = commandOptions.ignoreBots
	self._needPrefixInDm = commandOptions.needPrefixInDm
	self._defaultOptions = commandOptions.defaultOptions
	self._env = commandOptions.env
	self._timeRemainingFormat = commandOptions.timeRemainingFormat

	local commandsPath = commandOptions.commandsPath
	self._commandsPath = commandsPath

	if commandsPath and not readdirRecursive then
		readdirRecursive = require('./luvitWalk')
	end

	-- Primeiro Start
	self:once('ready', function()
		self._mentionString = self._user.mentionString
		self._defaultPrefix = self:fixPrefixes(commandOptions.prefix)
	end)

	self:on('ready', function()
		self._uptime = os.time()
	end)

	self:on('messageCreate', function(message)
		self:_messageCreate(message)
	end)
end

---@param prefixes table | string
function Piblib:fixPrefixes(prefixes)
	prefixes = type(prefixes) ~= 'table' and {prefixes} or prefixes

	local mentionString = self._mentionString
	for i, prefix in ipairs(prefixes) do
		prefixes[i] = gsub(prefix, '@mention', mentionString)
	end

	return prefixes
end

---@param guildId string @O id da guild
---@param prefixes table @As prefixes que essa guild irá ter
---@param insertDefaultPrefixes boolean | nil @Se devemos inserir as prefixes padrões às prefixes do servidor ou não
function Piblib:updateGuildPrefix(guildId, prefixes, insertDefaultPrefixes)
	prefixes = type(prefixes) ~= 'table' and {prefixes} or prefixes
	
	if insertDefaultPrefixes then
		for _, defaultPrefix in ipairs(self._defaultPrefix) do
			insert(prefixes, defaultPrefix)
		end
	end

	self._prefixes[guildId] = prefixes
end

---@return string @O conteúdo da mensagem
---@return table @As palavras da mensagem separadas por espaço
---@return string @A prefix utilizada
function Piblib:parseContent(message)
	local messageContent = gsub(message.content, '<@!', '<@')
	local guild = message.guild

	if not guild and not self._needPrefixInDm then
		return messageContent, getArguments(messageContent), ''
	end

	local prefixes = self._prefixes[guild.id] or self._defaultPrefix
	for _, prefix in ipairs(prefixes) do
		if find(messageContent, prefix, 1, true) == 1 then
			local prefixSize = len(prefix)

			messageContent = sub(messageContent, prefixSize + 1)

			return messageContent, getArguments(messageContent), prefix
		end
	end
end

---@param name string @Os comandos
---@param commands table
---@return table | nil @O comando achado
function Piblib:getCommand(commands, name)
	local command = commands[name]

	if command then
		return command
	else
		command = commands[lower(name)]

		if command and command.caseInsensitive then
			return command
		end
	end
end

---@param requirements table | nil
---@param message table
---@return boolean | nil
function Piblib:checkRequirements(requirements, message)
	if not requirements then
		return true
	end

	local user = message.author

	local isOwnerOnly = requirements.ownerOnly
	if isOwnerOnly and user ~= self.owner then
		return
	end

	local guildOnly = requirements.guildOnly
	local guild = message.guild
	if guildOnly and not guild then
		return
	end

	local customRequirement = requirements.custom
	if customRequirement and not customRequirement(message) then
		return
	end

	local usersRequirement = requirements.users
	if usersRequirement and not usersRequirement[user.id] then
		return
	end

	-- Abaixo disso apenas testes relacionados à guilds serão feitos,
	-- Então se não ouver uma guild retornaremos como permissões válidas.
	if not guild then
		return true
	end

	local guidlRequirements = requirements.guilds
	if guidlRequirements and not guidlRequirements[guild.id] then 
		return 
	end

	local member = guild:getMember(user.id)
	if not member then
		return true
	end

	local permissionsRequirement = requirements.permissions
	if permissionsRequirement then
		local permissions = member:getPermissions()
		for _, permission in ipairs(permissionsRequirement) do
			if not permissions:has(permission) then
				return
			end
		end
	end

	local rolesRequirement = requirements.roles
	if rolesRequirement then
		for _, roleId in ipairs(rolesRequirement) do
			if not member:hasRole(roleId) then
				return
			end
		end
	end

	return true
end

---@param command table
---@param message table
---@return boolean | nil
---@return number | nil
function Piblib:checkCooldown(command, message)
	local commandName = command.fullName
	local userId = message.author.id

	local cooldownExclusions = command.cooldownExclusions
	if cooldownExclusions then
		local guild = message.guild
		local usersExclusion = cooldownExclusions.users
		local guildExclusion = cooldownExclusions.guilds

		if (usersExclusion and usersExclusion[userId]) or (guild and guildExclusion and guildExclusion[guild.id]) then
			return
		end
	end

	local cooldownList = self._cooldowns[commandName]
	local onList = cooldownList[userId]
	local commandCooldown = command.cooldown	
	local now = hrtime()

	if onList then
		local timeRemaining = format(self._timeRemainingFormat, ((onList.endTime - now) / NANO_IN_MS) / 1000)

		return true, timeRemaining
	else
		cooldownList[userId] = {
			timer = setTimeout(commandCooldown, function()
				cooldownList[userId] = nil
			end),

			endTime = now + (commandCooldown * NANO_IN_MS)
		}
	end
end

---@param message table @O objeto da mensagem
---@param replyContent string @O conteúdo que será utilizado para responder
---@param deleteAfter number | nil @O quanto tempo depois a mensagem deve ser deletada
function Piblib:replyToMessage(message, replyContent, deleteAfter)
	local messageReply = message:reply(replyContent)
	if deleteAfter then
		setTimeout(deleteAfter, wrap(messageReply.delete), messageReply)
	end
end

---@param message table
---@param deleteAfter number | nil
function Piblib:deleteMessage(message, deleteAfter)
	if deleteAfter then
		setTimeout(deleteAfter, wrap(message.delete), message)
	else
		message:delete()
	end
end

---@param message table @A nova mensagem recebida
function Piblib:_messageCreate(message)
	local messageAuthor = message.author
	local isMe = messageAuthor == self._user
	local isABot = messageAuthor.bot

	if (self._ignoreSelf and isMe) or (self._ignoreBots and isABot) then
		return
	end

	local content, arguments, prefix = self:parseContent(message)
	if not content then
		return
	end

	local commandName = remove(arguments, 1)

	local command = self:getCommand(self._commands, commandName)
	if not command then
		return
	end

	local subcommands = command.subcommands
	local firstArg = arguments[1]

	local isSubcommand = subcommands and subcommands[firstArg] and self:getCommand(subcommands, firstArg)
	if isSubcommand then
		table.remove(arguments, 1)
		command = isSubcommand
	end

	local commandMessages = command.messages or {}

	local requireArguments = command.argumentsRequired
	if requireArguments and #arguments == 0 then
		local invalidUsageMessage = commandMessages.invalidUsage
		if invalidUsageMessage then
			local invalidUsageType = type(invalidUsageMessage)
			local reply = invalidUsageType == 'string' and gsub(invalidUsageMessage, '[prefix]', prefix) or 
				invalidUsageMessage(message)

			self:replyToMessage(message, reply)
		end

		return
	end

	local hasRequirements = self:checkRequirements(command.requirements, message) 
	if not hasRequirements then
		local invalidPermissionMessage = commandMessages.invalidPermissions
		if invalidPermissionMessage then
			local invalidPermissionType = type(invalidPermissionMessage)
			local reply = invalidPermissionType == 'string' and invalidPermissionMessage or 
				invalidPermissionType(message)

			self:replyToMessage(message, reply)
		end

		return
	end

	local deleteAfter = command.deleteAfter

	local commandCooldown = command.cooldown
	if commandCooldown then
		local isOnCooldown, timeRemaining = self:checkCooldown(command, message)

		if isOnCooldown then
			local cooldownMessage = commandMessages.cooldown
			if cooldownMessage then
				local cooldownMessageType = type(cooldownMessage)
				local reply = cooldownMessageType == 'string' and gsub(cooldownMessage, '[time]', timeRemaining) or 
					cooldownMessage(message, timeRemaining)
	
				self:replyToMessage(message, reply, deleteAfter)
			end

			return
		end
	end

	local handler = command.handler
	local success, response, deleteResponse = pcall(handler, message, arguments, {
		client = self,
		name = commandName,
		prefix = prefix
	})

	if success and response then
		local isAMessageObject = isInstance(response, Message)
		if isAMessageObject then
			self:deleteMessage(message, command.deleteReplyAfter)
		elseif not isAMessageObject then
			self:replyToMessage(message, response, deleteAfter)
		end
	elseif not success then
		self._logger:log(1, 'Command "%s" error: %s', commandName, response)
	end
end

---@param command table @A table contendo as informações do comando
---@param subcommands table | nil @Os subcomandos, caso o comando tenha
---@param mainCommand table | nil @O comando principal, apenas utilizado em subcomandos
---@return boolean @Se a criação do comando deu certo
---@return table | string @O novo comando ou o erro
function Piblib:registerCommand(command, subcommands, mainCommand, defaultOptions)
	-- Verificar se é um comando válido ou não.
	if not command then
		return false, self._logger:log(1, 'Invalid command!')
	else
		for name in pairs(OBRIGATORY_PROPERTIES) do
			if not command[name] then
				return false, self._logger:log(1, 'Invalid propertie: ' .. name)
			end
		end
	end

	local currentCommands = mainCommand and mainCommand.subcommands or self._commands
	local commandName = command.name
	local isCaseInsensitive = command.caseInsensitive

	commandName = isCaseInsensitive and lower(commandName) or commandName

	-- Caso o nome já esteja em uso não devemos reescrever ele
	local nameInUse = currentCommands[commandName]
	if nameInUse then
		return false, self._logger:log(1, 'The name "%s" is already in use!', commandName)
	else
		currentCommands[commandName] = command
	end

	defaultOptions = defaultOptions or self._defaultOptions
	if defaultOptions then
		for optionName, optionValue in pairs(defaultOptions) do
			if command[optionName] == nil then
				command[optionName] = optionValue
			end
		end
	end

	local aliases = command.aliases
	if aliases then
		local aliasesLocation = mainCommand and mainCommand.subAliases or aliases

		for _, aliase in ipairs(aliases) do
			aliase = isCaseInsensitive and lower(isCaseInsensitive) or aliase

			local alreadyInUse = aliasesLocation[aliase]
			if not alreadyInUse then
				aliasesLocation[aliase] = command
			else
				self._logger:log(1, 'Aliase "%s" already in use!', aliase)
			end
		end
	end

	if subcommands then
		command.subAliases = {}

		local subcommandsTable = {}
		command.subcommands = subcommandsTable

		for subcommandName, subcommandOptions in pairs(subcommands) do
			subcommandOptions.name = subcommandName

			local success, subcommand = self:registerCommand(subcommandOptions, nil, command, command.defaultOptions)
			if success then
				subcommandsTable[subcommand.name] = subcommand
			end
		end
	end

	if mainCommand then
		local parentName = mainCommand.name
		local fullName = string.format('%s %s', parentName, commandName)

		command.fullName = fullName
	else
		command.fullName = commandName
	end

	self._cooldowns[command.fullName] = {}

	return true, command
end

---@param path string @O caminho para o arquivo
---@return table
function Piblib:loadCommand(path)
	local splitedPath = splitPath(path)
	local code = assert(readFileSync(path))
	local commandFunction = assert(load(code, '@' .. splitedPath[#splitedPath], 't', self._env))

	return commandFunction()
end

---@param callback function
function Piblib:loadComands(callback)
	-- Verificar recursivamente entre as pastas que existem no diretório do caminho dos comandos.
	readdirRecursive(self._commandsPath, function(error, files)
		if error then
			return self._logger:log(1, 'Failed to read commands path: %s', error)
		end

		for _, commandPath in ipairs(files) do
			local commandOptions, subcommands = self:loadCommand(commandPath)
			commandOptions._path = commandPath
			self:registerCommand(commandOptions, subcommands)
		end

		if callback then
			callback()
		end
	end)
end

---@param commandName string
function Piblib:reloadCommand(commandName)
	local command = self._commands[commandName]
	local path = command and command._path

	-- Se o comando não tiver um path, é por que ele não foi gerado sendo carrego pelo
	-- readdir, logo não temos como recarrega-lo.
	if not command or not path then
		return
	end

	self._commands[commandName] = nil

	local aliases = command.aliases

	-- Caso o comando possua alguma aliase, elas serão removidas para que não impessam
	-- que o comando seja reescrito novamente.
	if aliases then
		for _, aliase in ipairs(aliases) do
			self._commands[aliase] = nil
		end
	end

	local commandOptions, subcommands = self:loadCommand(path)

	return self:registerCommand(commandOptions, subcommands)
end

function Piblib:reloadAllComands()
	local uniqueCommands = {}
	for commandName, command in pairs(self._commands) do
		local name = command.name

		if not uniqueCommands[name] then
			uniqueCommands[name] = true
		end
	end

	for command in pairs(uniqueCommands) do
		self:reloadCommand(command)
	end
end

---@return table @Os comandos que estão registrados.
function get:commands()
	return self._commands
end

---@return number @A hora em que o recebeu o evento 'ready' pela útlima vez
function get:uptime()
	return self._uptime
end

return Piblib