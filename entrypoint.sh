#!/bin/bash

set -a
CLUSTER_DIRECTORY=${CLUSTER_DIRECTORY:-"/opt/redis"}
REDIS_CONF_DIR=${REDIS_CONF_DIR:-"/etc/redis"}
PERSISTENCE_ENABLED=${PERSISTENCE_ENABLED:-"false"}
DATA_DIR=${DATA_DIR:-"/data/redis"}
EXTERNAL_CONFIG_FILE=${EXTERNAL_CONFIG_FILE:-"/etc/redis/external.conf.d/redis-external.conf"}



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
  appctl retry 120 1 0 appctl checkMyIp || {
    echo "------- ERROR: Get My IP FALT -------"
    return 1
  }
  common_operation
  appctl aclfileUpdate
  appctl buildRedisConfig
  apply_permissions
  start_redis
}

main_function
