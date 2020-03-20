-- Copyright (C) Kong Inc.
local policies = require "kong.plugins.h3c-rate-limiting.policies"

local kong = kong
local ngx = ngx
local max = math.max
local time = ngx.time
local pairs = pairs
local tostring = tostring
local timer_at = ngx.timer.at
local singletons = require "kong.singletons"
local constants = require "kong.constants"
local meta = require "kong.meta"
local server_header = meta._SERVER_TOKENS

local EMPTY = {}
local RATELIMIT_LIMIT = "X-RateLimit-Limit"
local RATELIMIT_REMAINING = "X-RateLimit-Remaining"

local H3cRateLimitingHandler = {}

H3cRateLimitingHandler.PRIORITY = 902
H3cRateLimitingHandler.VERSION = "2.0.0"

local function get_identifier(conf)
  local identifier

  if conf.limit_by == "service" then
    identifier = ""
  elseif conf.limit_by == "consumer" then
    identifier = (kong.client.get_consumer() or
      kong.client.get_credential() or
      EMPTY).id

  elseif conf.limit_by == "credential" then
    identifier = (kong.client.get_credential() or
      EMPTY).id
  end

  return identifier or kong.client.get_forwarded_ip()
end

local function get_usage(conf, identifier, current_timestamp, limits)
  local usage = {}
  local stop

  for period, limit in pairs(limits) do
    local current_usage, err = policies[conf.policy].usage(conf, identifier, period, current_timestamp)
    if err then
      return nil, nil, err
    end

    -- What is the current usage for the configured limit name?
    local remaining = limit - current_usage

    -- Recording usage
    usage[period] = {
      limit = limit,
      remaining = remaining,
    }

    if remaining <= 0 then
      stop = period
    end
  end

  return usage, stop
end

local function increment(premature, conf, ...)
  if premature then
    return
  end

  policies[conf.policy].increment(conf, ...)
end

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

local function rateLimiting(conf)

  local current_timestamp = time() * 1000

  -- Consumer is identified by ip address or authenticated_credential id
  local identifier = get_identifier(conf)
  local fault_tolerant = conf.fault_tolerant

  -- Load current metric for configured period
  local limits = {
    second = conf.second,
    minute = conf.minute,
    hour = conf.hour,
    day = conf.day,
    month = conf.month,
    year = conf.year,
  }

  local usage, stop, err = get_usage(conf, identifier, current_timestamp, limits)
  if err then
    if fault_tolerant then
      kong.log.err("failed to get usage: ", tostring(err))
    else
      kong.log.err(err)
      return kong.response.exit(500, { message = "An unexpected error occurred" })
    end
  end

  if usage then
    -- Adding headers
    if not conf.hide_client_headers then
      local headers = {}
      for k, v in pairs(usage) do
        if stop == nil or stop == k then
          v.remaining = v.remaining - 1
        end

        headers[RATELIMIT_LIMIT .. "-" .. k] = v.limit
        headers[RATELIMIT_REMAINING .. "-" .. k] = max(0, v.remaining)
      end

      kong.ctx.plugin.headers = headers
    end

    -- If limit is exceeded, terminate the request
    if stop then

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

      return kong.response.exit(429, { message = "API rate limit exceeded" })
    end
  end

  kong.ctx.plugin.timer = function()
    local ok, err = timer_at(0, increment, conf, limits, identifier, current_timestamp, 1)
    if not ok then
      kong.log.err("failed to create timer: ", err)
    end
  end

end

function H3cRateLimitingHandler:access(conf)

  if not filteringApi(conf) then
    rateLimiting(conf)
  end

end

function H3cRateLimitingHandler:header_filter(_)
  local headers = kong.ctx.plugin.headers
  if headers then
    kong.response.set_headers(headers)
  end
end

function H3cRateLimitingHandler:log(_)
  if kong.ctx.plugin.timer then
    kong.ctx.plugin.timer()
  end
end

return H3cRateLimitingHandler
