local kong = kong
local cjson = require("cjson")
local H3cDynamicRoutingHandler = {}

H3cDynamicRoutingHandler.PRIORITY = 701
H3cDynamicRoutingHandler.VERSION = "2.0.0"

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

local function filteringApiByBody(itemsBody, currentBody)
  if not currentBody then
    return false
  end

  if itemsBody then

    local flagBody = true

    for _, name, value in iter(itemsBody) do

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

  return false

end

local function filteringApiByHeader(itemsHeader, currentHeader)
  if not currentHeader then
    return false
  end

  if itemsHeader then

    local flagHeader = true

    for _, name, value in iter(itemsHeader) do

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

        if itemsBody then

          for _, itemBody in pairs(itemsBody) do

            if filteringApiByBody(itemBody.rules, currentBody) then

              ngx.ctx.balancer_data.scheme = itemBody.url.protocol

              ngx.ctx.balancer_data.host = itemBody.url.host

              ngx.ctx.balancer_data.port = itemBody.url.port

              ngx.var.upstream_uri = itemBody.url.path

              return

            end

          end

        end

        if itemsHeader then

          for _, itemHeader in pairs(itemsHeader) do

            if filteringApiByHeader(itemHeader.rules, currentHeader) then

              ngx.ctx.balancer_data.scheme = itemHeader.url.protocol

              ngx.ctx.balancer_data.host = itemHeader.url.host

              ngx.ctx.balancer_data.port = itemHeader.url.port

              ngx.var.upstream_uri = itemHeader.url.path

              return
            end

          end

        end


      end
    end
  end

end

function H3cDynamicRoutingHandler:access(conf)

  filteringApi(conf)

end

return H3cDynamicRoutingHandler
