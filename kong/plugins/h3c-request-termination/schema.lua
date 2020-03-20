local typedefs = require "kong.db.schema.typedefs"

local is_present = function(v)
  return type(v) == "string" and #v > 0
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
  name = "h3c-request-termination",
  fields = {
    { run_on = typedefs.run_on_first },
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
        { status_code = {
          type = "integer",
          default = 503,
          between = { 100, 599 },
        }, },
        { message = { type = "string" }, },
        { content_type = { type = "string" }, },
        { body = { type = "string" }, },
        { apis = { type = "array", elements = api, }, },
        { items_body = {
          type = "array", elements = colon_strings_array,
        }, },
        { items_header = {
          type = "array", elements = colon_strings_array,
        }, },
      },
      custom_validator = function(config)
        if is_present(config.message)
          and (is_present(config.content_type)
          or is_present(config.body)) then
          return nil, "message cannot be used with content_type or body"
        end
        if is_present(config.content_type)
          and not is_present(config.body) then
          return nil, "content_type requires a body"
        end

        if not config.apis then
          return nil, "apis cannot be null"
        end

        if not config.items_body and not config.items_header then
          return nil, "items_body and items_header cannot be null at the same time"
        end

        return true
      end,
    },
    },
  },
}
