#!/usr/bin/env bash

# @File    : deploy_kong.sh
# @Time    : 2019/11/18 18:01
# @Author  : bevisy

# prepare db
kubectl create -f yaml/o_postgres.yaml
# prepare database/kong

# create kong
kubectl create -f yaml/1_kong_migration.yaml
kubectl create -f yaml/2_kong.yaml
