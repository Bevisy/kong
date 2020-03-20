return {
  postgres = {
    up = [[
      CREATE INDEX IF NOT EXISTS h3c_ratelimiting_metrics_idx ON h3c_ratelimiting_metrics (service_id, route_id, period_date, period);
    ]],
  },

  cassandra = {
    up = [[
    ]],
  },
}
