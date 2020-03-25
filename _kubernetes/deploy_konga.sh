#!/usr/bin/env bash

# @File    : deploy_kong.sh
# @Time    : 2019/11/18 18:01
# @Author  : bevisy

# prepare db
# postgres 或者 mysql 均可，创建数据库 konga，并配置 3_konga.yaml

# create database/konga
kubectl create -f yaml/3_konga.yaml
