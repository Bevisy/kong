#!/usr/bin/env bash

set -ex

KONG_VERSION=1.4.0
POSTGRES_VERSION=9.6
POSTGRES_C_NAME=kong-database
POSTGRES_PORT=5432
POSTGRES_PASSWORD=cloudos
POSTGRES_DATA_PATH=pgdata

# prepare container images
function prepare() {
    docker pull kong:${KONG_VERSION} postgres:${POSTGRES_VERSION}
}

# install postgres
function start_potgres() {
    mkdir -p ${POSTGRES_DATA_PATH}

    docker run -d --name ${POSTGRES_C_NAME} \
        -p ${POSTGRES_PORT}:5432 \
        -e "POSTGRES_USER=kong" \
        -e "POSTGRES_DB=kong" \
        -e "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" \
        -v ${POSTGRES_DATA_PATH}:/var/lib/postgresql/data \
        postgres:${POSTGRES_VERSION}
}

# prepare tables
function start_migration() {
    docker run -it --name migration \
        -e "KONG_DATABASE=postgres" \
        -e "KONG_PG_HOST=${POSTGRES_C_NAME}" \
        -e "KONG_PG_USER=kong" \
        -e "KONG_PG_PASSWORD=${POSTGRES_PASSWORD}" \
        kong:${KONG_VERSION} kong migrations bootstrap --vv
}

# install kong
function start_kong() {
    docker run -d --name kong \
     -e "KONG_DATABASE=postgres" \
     -e "KONG_PG_HOST=${POSTGRES_C_NAME}" \
     -e "KONG_PG_USER=kong" \
     -e "KONG_PG_PASSWORD=${POSTGRES_PASSWORD}" \
     -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" \
     -e "KONG_ADMIN_ACCESS_LOG=/dev/stdout" \
     -e "KONG_PROXY_ERROR_LOG=/dev/stderr" \
     -e "KONG_ADMIN_ERROR_LOG=/dev/stderr" \
     -e "KONG_ADMIN_LISTEN=0.0.0.0:8001, 0.0.0.0:8444 ssl" \
     -p 8000:8000 \
     -p 8443:8443 \
     -p 8001:8001 \
     -p 8444:8444 \
     kong:${KONG_VERSION}

}

# check functions
#function health_test() {
#
#}


function main() {
    prepare

    start_potgres

    start_migration

    start_kong
}

# starting install
main
