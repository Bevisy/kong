#!/usr/bin/env bash

docker run -d --name kong-dbless \
#     -v "/root/kong.yml:/usr/local/kong/declarative/kong.yml" \
     --mount type=bind,source=/root/kong.yml,target=/usr/local/kong/declarative/kong.yml,readonly \
     -e "KONG_DATABASE=off" \
     -e "KONG_DECLARATIVE_CONFIG=/usr/local/kong/declarative/kong.yml" \
     -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" \
     -e "KONG_ADMIN_ACCESS_LOG=/dev/stdout" \
     -e "KONG_PROXY_ERROR_LOG=/dev/stderr" \
     -e "KONG_ADMIN_ERROR_LOG=/dev/stderr" \
     -e "KONG_ADMIN_LISTEN=0.0.0.0:8001" \
     -e "KONG_ANONYMOUS_REPORTS=off" \
     -e "KONG_NGINX_WORKER_PROCESSES=2" \
     -p 18000:8000 \
     -p 18443:8443 \
     -p 18001:8001 \
     kong:1.4
