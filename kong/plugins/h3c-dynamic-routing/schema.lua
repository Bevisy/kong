local typedefs = require "kong.db.schema.typedefs"

local colon_strings_array = {
  type = "array",
  default = {},
  elements = { type = "string", match = "^[^:]+:.*$" },
}

local url = {
  type = "record",
  fields = {
    { protocol = { type = "string", }, },
    { host = { type = "string", }, },
    { port = { type = "number", }, },
    { path = { type = "string", }, },
  },
}

local api = {
  type = "record",
  fields = {
    { path = { type = "string", }, },
    { method = { type = "string", }, },
  },
}

local item = {
  type = "record",
  fields = {
    { url = url, },
    { rules = colon_strings_array, },
  },
}

return {
  name = "h3c-dynamic-routing",
  fields = {
    { consumer = typedefs.no_consumer },
    { run_on = typedefs.run_on_first },
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
        --{ url = { required = true, type = "string" }, },
        --{ method = { required = true, type = "string" }, },
        { apis = { type = "array", elements = api, }, },
        { items_body = {
          type = "array", elements = item,
        }, },
        { items_header = {
          type = "array", elements = item,
        }, },
      },
      custom_validator = function(config)

        if not config.apis then
          return nil, "apis cannot be null"
        end

        if not config.items_body and not config.items_header then
          return nil, "items_body and items_header cannot be null at the same time"
        end

        return true
      end,
    }, },
  }
}
