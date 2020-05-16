local Object = require "kong.vendor.classic"
local BasePlugin = Object:extend()

local ngx_log = ngx.log
local DEBUG = ngx.DEBUG
local subsystem = ngx.config.subsystem

function BasePlugin:new(name)
  self._name = name
end

-- 每个 Nginx Worker启动时执行
function BasePlugin:init_worker()
  ngx_log(DEBUG, "executing plugin \"", self._name, "\": init_worker")
end

if subsystem == "http" then
  -- 在ssl握手的ssl证书服务阶段执行
  function BasePlugin:certificate()
    ngx_log(DEBUG, "executing plugin \"", self._name, "\": certificate")
  end

  -- 每个请求中的rewrite阶段执行
  function BasePlugin:rewrite()
    ngx_log(DEBUG, "executing plugin \"", self._name, "\": rewrite")
  end

  -- 在被代理至上游服务前执行
  function BasePlugin:access()
    ngx_log(DEBUG, "executing plugin \"", self._name, "\": access")
  end

  -- 从上游服务器接收所有Response headers后执行
  function BasePlugin:header_filter()
    ngx_log(DEBUG, "executing plugin \"", self._name, "\": header_filter")
  end

  -- 从上游服务接收的响应主体的每个块执行。由于响应被流回客户端，因此它可以超过缓冲区大小并按块进行流式传输。
  -- 因此如果响应很大，则会多次调用此方法
  function BasePlugin:body_filter()
    ngx_log(DEBUG, "executing plugin \"", self._name, "\": body_filter")
  end
elseif subsystem == "stream" then
  function BasePlugin:preread()
    ngx_log(DEBUG, "executing plugin \"", self._name, "\": preread")
  end
end

-- 当最后一个响应字节输出完毕时执行
function BasePlugin:log()
  ngx_log(DEBUG, "executing plugin \"", self._name, "\": log")
end

return BasePlugin
