#!/bin/bash

set -a
CLUSTER_DIRECTORY=${CLUSTER_DIRECTORY:-"/opt/redis"}
REDIS_CONF_DIR=${REDIS_CONF_DIR:-"/etc/redis"}
PERSISTENCE_ENABLED=${PERSISTENCE_ENABLED:-"false"}
DATA_DIR=${DATA_DIR:-"/data/redis"}
EXTERNAL_CONFIG_FILE=${EXTERNAL_CONFIG_FILE:-"/etc/redis/external.conf.d/redis-external.conf"}
ACL_FILE_CONF=${REDIS_CONF_DIR}/aclfile.conf
EXTERNAL_ACL_FILE=${REDIS_CONF_DIR}/acl.conf.d/aclfile.conf
REDIS_CONF_FILE=${DATA_DIR}/redis.conf
REDIS_LOGS_FILE=${DATA_DIR}/logs/redis-server.log
REDIS_NODES_CONF_FILE=${DATA_DIR}/nodes.conf
SENTINEL_CONF_FILE=${DATA_DIR}/sentinel.conf

apply_permissions() {
    chgrp -R 0 /opt
    chmod -R g=u /opt
    chown -R redis.redis /etc/redis
    chown -R redis.redis /data
}

common_operation() {
    mkdir -p "${CLUSTER_DIRECTORY}"
    mkdir -p "${DATA_DIR}"
    mkdir -p "${DATA_DIR}/logs"
    mkdir -p "${REDIS_CONF_DIR}"
}



start_redis() {
    if [[ "${SETUP_MODE}" == "cluster" ]]; then
        echo "Starting redis service in cluster mode....."
        exec gosu redis redis-server /data/redis/redis.conf --cluster-announce-ip "${POD_IP}"
    elif [[ "${SETUP_MODE}" == "sentinel" ]]; then
        echo "Starting redis sentinel in standalone mode....."
        exec gosu redis redis-sentinel /data/redis/sentinel.conf
    else
        echo "Starting redis service in standalone mode....."
        exec gosu redis redis-server /data/redis/redis.conf
    fi
}

main_function() {
  common_operation
  appctl aclfileUpdate
  appctl buildRedisConfig
  apply_permissions
  start_redis
}

main_function
