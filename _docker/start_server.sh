#!/usr/bin/env bash

# 获取序号
ARGS=$1
SERIAL_NUM=${ARGS:-0}

function prepare() {
    docker pull bevisy/lottery:latest
}

function main() {
    docker run -d --name lottery-${SERIAL_NUM} bevisy/lottery:latest
}

main
