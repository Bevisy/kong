local typedefs = require "kong.db.schema.typedefs"

local ORDERED_PERIODS = { "second", "minute", "hour", "day", "month", "year" }

local function validate_periods_order(config)
  for i, lower_period in ipairs(ORDERED_PERIODS) do
    local v1 = config[lower_period]
    if type(v1) == "number" then
      for j = i + 1, #ORDERED_PERIODS do
        local upper_period = ORDERED_PERIODS[j]
        local v2 = config[upper_period]
        if type(v2) == "number" and v2 < v1 then
          return nil, string.format("The limit for %s(%.1f) cannot be lower than the limit for %s(%.1f)",
            upper_period, v2, lower_period, v1)
        end
      end
    end
  end

  if not config.apis then
    return nil, "apis cannot be null"
  end

  if not config.items_body and not config.items_header then
    return nil, "items_body and items_header cannot be null at the same time"
  end

  return true
end

local colon_strings_array = {
  type = "array",
  default = {},
  elements = { type = "string", match = "^[^:]+:.*$" },
}

local api = {
  type = "record",
  fields = {
    { path = { type = "string", }, },
    { method = { type = "string", }, },
  },
}

return {
  name = "h3c-rate-limiting",
  fields = {
    { run_on = typedefs.run_on { one_of = { "first", "second" } } },
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
        { second = { type = "number", gt = 0 }, },
        { minute = { type = "number", gt = 0 }, },
        { hour = { type = "number", gt = 0 }, },
        { day = { type = "number", gt = 0 }, },
        { month = { type = "number", gt = 0 }, },
        { year = { type = "number", gt = 0 }, },
        { limit_by = {
          type = "string",
          default = "consumer",
          one_of = { "consumer", "credential", "ip", "service" },
        }, },
        { policy = {
          type = "string",
          default = "cluster",
          len_min = 0,
          one_of = { "local", "cluster", "redis" },
        }, },
        { fault_tolerant = { type = "boolean", default = true }, },
        { redis_host = typedefs.host },
        { redis_port = typedefs.port({ default = 6379 }), },
        { redis_password = { type = "string", len_min = 0 }, },
        { redis_timeout = { type = "number", default = 2000, }, },
        { redis_database = { type = "integer", default = 0 }, },
        { hide_client_headers = { type = "boolean", default = false }, },
        { apis = { type = "array", elements = api, }, },
        { items_body = {
          type = "array", elements = colon_strings_array,
        }, },
        { items_header = {
          type = "array", elements = colon_strings_array,
        }, },
        { status_code = {
          type = "integer",
          default = 409,
          between = { 100, 599 },
        }, },
        { content_type = { type = "string" }, },
        { body = { type = "string" }, },
      },
      custom_validator = validate_periods_order,
    },
    },
  },
  entity_checks = {
    { at_least_one_of = { "config.second", "config.minute", "config.hour", "config.day", "config.month", "config.year" } },
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis_host", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis_port", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis_timeout", then_match = { required = true },
    } },
  },
}
