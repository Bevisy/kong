local singletons = require "kong.singletons"
local constants = require "kong.constants"
local meta = require "kong.meta"
--local logger = require "kong.cmd.utils.log
local ngx_log   = ngx.log
local DEBUG     = ngx.DEBUG


local kong = kong
local server_header = meta._SERVER_TOKENS -- kong/1.4.3

local function log(lvl, ...)
  return ngx_log(lvl, "[zbb_request_termination] ", ...)
end

-- 定义返回码对应的返回消息
local DEFAULT_RESPONSE = {
  [401] = "Unauthorized",
  [404] = "Not found",
  [405] = "Method not allowed",
  [500] = "An unexpected error occurred",
  [502] = "Bad Gateway",
  [503] = "Service unavailable",
}


local RequestTerminationHandler = {}


RequestTerminationHandler.PRIORITY = 2
RequestTerminationHandler.VERSION = "2.0.0"


function RequestTerminationHandler:access(conf)
  -- 读取配置参数
  local status  = conf.status_code
  local content = conf.body

  -- 判断body信息的有无，确认返回的消息类型
  if content then
    -- body设置，则读取内容类型
    local headers = {
      ["Content-Type"] = conf.content_type
    }

    -- 设置返回的消息头部中的 Server 信息
    if singletons.configuration.enabled_headers[constants.HEADERS.SERVER] then
      headers[constants.HEADERS.SERVER] = server_header
      --logger.debug("ZBB: Set Reponse Header: '%s' .", server_header)
      log(DEBUG, "set reponse header: server_header is "..server_header)
    end

    return kong.response.exit(status, content, headers)
  end

  return kong.response.exit(status, { message = conf.message or DEFAULT_RESPONSE[status] })
end


return RequestTerminationHandler
