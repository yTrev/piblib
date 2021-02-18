--[[
	https://github.com/kaustavha/luvit-read-directory-recursive

	Copyright Kaustav Haldar
	Licensed under the Apache License, Version 2.0 (the "License");
	you may not use this file except in compliance with the License.
	You may obtain a copy of the License at
		http://www.apache.org/licenses/LICENSE-2.0
	Unless required by applicable law or agreed to in writing, software
	distributed under the License is distributed on an "AS-IS" BASIS,
	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
	See the License for the specific language governing permissions and
	limitations under the License.
--]]

local path = require('path')
local scandir = require('fs').scandir
local timer = require('timer')

local gsub = string.gsub

return function(baseDir, callback)
	baseDir = gsub(baseDir, '%/$', '') -- strip trailing slash

	local filesList = {}
	local waitCount = 0

	local function readdirRecursive(curDir)
		scandir(curDir, function(err, func)
			if err then
				return callback(err)
			end

			local function recurser(fn)
				local name, type = fn()

				if name and type then
					local dir = path.join(curDir, fname)

					if type == 'directory' then
						waitCount = waitCount + 1
						timer.setImmediate(readdirRecursive, dir) -- prevent potential buffer overflows
					elseif type == 'file' then
						table.insert(filesList, dir)
					end

					recurser(fn)
				else
					waitCount = waitCount - 1

					if waitCount == 0 then
						return callback(nil, filesList)
					end
				end
			end

			recurser(func)
		end)
	end

	waitCount = waitCount + 1
	readdirRecursive(baseDir)
end