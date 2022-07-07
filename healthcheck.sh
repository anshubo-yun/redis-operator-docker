#!/bin/bash
check_redis_health() {
  local port=6379 redisPasswd authOpt;
    if [[ "${SETUP_MODE}" == "sentinel"  ]]; then
        port=26379
    fi

  redisPasswd="$(appctl getConfPassword)"

  [ -z "$redisPasswd" ] || authOpt="--no-auth-warning -a $redisPasswd"
  redis-cli $authOpt -p $port ping
  if [[ "$SETUP_MODE" == "cluster" ]] ; then
    uptime_in_seconds="$(redis-cli --no-auth-warning -a $redisPasswd info server | awk -F "[: \r]+" '$1=="uptime_in_seconds"{print $2}')"
    if [[ 120 -lt $uptime_in_seconds ]]; then
      redis-cli $authOpt cluster nodes | awk '/,fail/{a++}END{if(a > NR/2){exit 1}}'
    fi
  fi
}

check_redis_health

