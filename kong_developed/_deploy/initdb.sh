#!/usr/bin/env bash

set -x
set -e

#创建用户
mysql -uroot -p${MYPASSWORD} -h127.0.0.1 -e "\
CREATE USER "kong"@"localhost" IDENTIFIED BY "${MYPASSWORD}";\
CREATE USER "kong"@"%" IDENTIFIED BY "${MYPASSWORD}";\
"
#创建数据库
mysql -uroot -p${MYPASSWORD} -h127.0.0.1 -e "\
CREATE DATABASE kong;\
grant all privileges on kong.* to “kong”@"localhost";\
grant all privileges on kong.* to “kong”@"%";\
flush privileges;\
"
#修改数据库配置，使其支持 timestamp 类型不填默认值
#否则报错：[MySQL error] failed to run migration '000_base' up: Invalid default value for 'nbf'
mysql -uroot -p${MYPASSWORD} -h127.0.0.1 -e "\
SET GLOBAL sql_mode='ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION';\
"
