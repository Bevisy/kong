local BasePlugin = require "kong.plugins.base_plugin"
local iputils = require "resty.iputils"
local log = require "kong.cmd.utils.log"

local FORBIDDEN = 403


-- cache of parsed CIDR values
local cache = {}

local IpRestrictionHandler = BasePlugin:extend()

IpRestrictionHandler.PRIORITY = 990
IpRestrictionHandler.VERSION = "1.0.0"

local function cidr_cache(cidr_tab)
  local cidr_tab_len = #cidr_tab
  local parsed_cidrs = kong.table.new(cidr_tab_len, 0) -- table of parsed cidrs to return

  -- build a table of parsed cidr blocks based on configured
  -- cidrs, either from cache or via iputils parse
  -- TODO dont build a new table every time, just cache the final result
  -- best way to do this will require a migration (see PR details)
  for i = 1, cidr_tab_len do
    local cidr = cidr_tab[i]
    local parsed_cidr = cache[cidr]

    if parsed_cidr then
      parsed_cidrs[i] = parsed_cidr

    else
      -- if we dont have this cidr block cached,
      -- parse it and cache the results
      local lower, upper = iputils.parse_cidr(cidr)

      cache[cidr] = { lower, upper }
      parsed_cidrs[i] = cache[cidr]
    end
  end

  return parsed_cidrs
end

function IpRestrictionHandler:new()
  IpRestrictionHandler.super.new(self, "ip-restriction")
end

function IpRestrictionHandler:init_worker()
  IpRestrictionHandler.super.init_worker(self)
  local ok, err = iputils.enable_lrucache()
  if not ok then
    kong.log.err("could not enable lrucache: ", err)
  end
end

function IpRestrictionHandler:access(conf)
  IpRestrictionHandler.super.access(self)
  local block = false
  --local binary_remote_addr = ngx.var.binary_remote_addr
  local http_x_forwarded_for = ngx.var.http_x_forwarded_for
  -- localIp  default
  local localIp = "127.0.0.1";
  if http_x_forwarded_for then
    local index, _ = string.find(http_x_forwarded_for, ",")
    if not index then
      localIp = http_x_forwarded_for
    else
      localIp = string.sub(http_x_forwarded_for, 1, index - 1);
    end
    log("ip-restriction  =========================  localIp :%s", localIp)
  end

  --if not localIp then
  --    return kong.response.exit(FORBIDDEN, { message = "Cannot identify the client IP address, unix domain sockets are not supported." })
  --end

  if conf.blacklist and #conf.blacklist > 0 then
    block = iputils.ip_in_cidrs(localIp, cidr_cache(conf.blacklist))
  end

  if conf.whitelist and #conf.whitelist > 0 then
    block = not iputils.ip_in_cidrs(localIp, cidr_cache(conf.whitelist))
  end

  if block then
    return kong.response.exit(FORBIDDEN, { message = "Your IP address is not allowed" })
  end
end

return IpRestrictionHandler
