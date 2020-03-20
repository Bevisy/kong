local singletons = require "kong.singletons"
local constants = require "kong.constants"
local meta = require "kong.meta"

local kong = kong
local server_header = meta._SERVER_TOKENS

local DEFAULT_RESPONSE = {
  [401] = "Unauthorized",
  [404] = "Not found",
  [405] = "Method not allowed",
  [500] = "An unexpected error occurred",
  [502] = "Bad Gateway",
  [503] = "Service unavailable",
}

local H3cRequestTerminationHandler = {}

H3cRequestTerminationHandler.PRIORITY = 3
H3cRequestTerminationHandler.VERSION = "2.0.0"

local noop = function()
end

local function iter(config_array)
  if type(config_array) ~= "table" then
    return noop
  end

  return function(config_array, i)
    i = i + 1

    local current_pair = config_array[i]
    if current_pair == nil then
      -- n + 1
      return nil
    end

    local current_name, current_value = current_pair:match("^([^:]+):*(.-)$")
    if current_value == "" then
      current_value = nil
    end

    return i, current_name, current_value
  end, config_array, 0
end

local function filteringApiByHeaderOrBody(itemsBody, itemsHeader, currentBody, currentHeader)

  if not currentBody or not currentHeader then
    return false
  end

  if itemsBody then

    for _, v in pairs(itemsBody) do
      local flagBody = true

      for _, name, value in iter(v) do

        if type(currentBody[name]) == "number" then
          currentBody[name] = tostring(currentBody[name])
        end

        if currentBody[name] ~= value then
          flagBody = false
        end

      end

      if flagBody then
        return true
      end

    end

  end

  if itemsHeader then

    for _, v in pairs(itemsHeader) do
      local flagHeader = true

      for _, name, value in iter(v) do

        if type(currentHeader[name]) == "number" then
          currentHeader[name] = tostring(currentHeader[name])
        end

        if currentHeader[name] ~= value then
          flagHeader = false
        end

      end

      if flagHeader then
        return true
      end

    end

  end

  return false

end

local function filteringApi(conf)
  local apis = conf.apis
  local itemsBody = conf.items_body
  local itemsHeader = conf.items_header
  local currentPath = kong.request.get_path()
  local currentMethod = kong.request.get_method()
  local currentBody = kong.request.get_body()
  local currentHeader = kong.request.get_headers()

  if apis then
    for _, v in pairs(apis) do
      if string.match(currentPath, v.path) and currentMethod == v.method then
        return filteringApiByHeaderOrBody(itemsBody, itemsHeader, currentBody, currentHeader)
      end
    end
  end

  return false

end

local function execTermination(conf)
  local status = conf.status_code
  local content = conf.body

  if content then
    local headers = {
      ["Content-Type"] = conf.content_type
    }

    if singletons.configuration.enabled_headers[constants.HEADERS.SERVER] then
      headers[constants.HEADERS.SERVER] = server_header
    end

    return kong.response.exit(status, content, headers)
  end

  return kong.response.exit(status, { message = conf.message or DEFAULT_RESPONSE[status] })
end

function H3cRequestTerminationHandler:access(conf)

  if filteringApi(conf) then
    execTermination(conf)
  end

end

return H3cRequestTerminationHandler
