local DEFAULT_ENV = setmetatable({
	require = require,
}, {__index = _G})

return {
	DEFAULT_ENV = DEFAULT_ENV,
	SPLIT_PATTERN = '%s',
	NANO_IN_MS = 1000000,

	DEFAULT_SETTINGS = {
		prefix = {'@mention'},
		ignoreBots = true,
		ignoreSelf = true,
		needPrefixInDm = false,
		env = DEFAULT_ENV,
		timeRemainingFormat = '%ds'
	},

	OBRIGATORY_PROPERTIES = {
		name = true,
		handler = true
	}
}