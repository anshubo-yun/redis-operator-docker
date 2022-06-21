#!/bin/bash
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

buildRedisConfig() {
  if [[ "${SETUP_MODE}" == "sentinel" ]]; then
    [ -f "$SENTINEL_CONF_FILE" ] && return
    echo "Setting up redis in sentinel mode"
    {
      echo 'port 26379'
      echo 'daemonize no'
      echo 'pidfile /var/run/redis-sentinel.pid'
      #echo "logfile \"$REDIS_LOGS_FILE\""
      echo "logfile \"\""
      echo 'dir /tmp'
      echo 'acllog-max-len 128'
      echo 'SENTINEL deny-scripts-reconfig yes'
      echo 'SENTINEL resolve-hostnames no'
      echo 'SENTINEL announce-hostnames no'
      echo "masterauth \"${REDIS_PASSWORD}\""
      echo "requirepass \"${REDIS_PASSWORD}\""
      echo "aclfile $ACL_FILE_CONF"
      [[ "$(uname -m)" == aarch64  ]] && echo "ignore-warnings ARM64-COW-BUG"
    } > $SENTINEL_CONF_FILE
  else
    {
      [[ -f "${EXTERNAL_CONFIG_FILE}"  ]] && echo "include ${EXTERNAL_CONFIG_FILE}"
      echo "bind 0.0.0.0"
      echo "port 6379"
      echo "aof-rewrite-incremental-fsync yes"
      echo "appendfilename \"appendonly.aof\""
      echo "appendonly yes"
      echo "auto-aof-rewrite-min-size 64mb"
      echo "auto-aof-rewrite-percentage 60"
      echo "daemonize no"
      echo "dir \"${DATA_DIR}\""
      echo "logfile \"\""
      echo "pidfile /var/run/redis/redis.pid"
      echo "save \"\""
      echo "masterauth \"${REDIS_PASSWORD}\""
      echo "requirepass \"${REDIS_PASSWORD}\""
      echo "aclfile $ACL_FILE_CONF"
      [[ "$(uname -m)" == aarch64  ]] && echo "ignore-warnings ARM64-COW-BUG"
    } >> $REDIS_CONF_FILE

    if [[ "${SETUP_MODE}" == "cluster" ]]; then
      {
        echo "cluster-enabled yes"
        echo "cluster-node-timeout 5000"
        echo "cluster-require-full-coverage no"
        echo "cluster-migration-barrier 5000"
        echo "cluster-allow-replica-migration no"
        echo "cluster-config-file \"$REDIS_NODES_CONF_FILE\""
      } >> $REDIS_CONF_FILE

      cat $REDIS_NODES_CONF_FILE
      if [ -e $REDIS_NODES_CONF_FILE ];then
        upateNodesConf
      else
        createNodesConf
      fi
      echo "============================================== END =============================================="
      cat $REDIS_NODES_CONF_FILE

    fi
  fi
}


confPasswdUpdate(){
  local configFile=$REDIS_CONF_FILE
  [[ "${SETUP_MODE}" == "sentinel" ]] && configFile="$SENTINEL_CONF_FILE"
  sed -i '/^\(requirepass\|masterauth\) /d' $configFile
  [[ -n "${REDIS_PASSWORD}" ]] && {
    echo "requirepass \"${REDIS_PASSWORD}\""
    echo "masterauth \"${REDIS_PASSWORD}\""
  } >> $configFile
}


aclfileUpdate(){
  if [ -z "${REDIS_PASSWORD}" ]; then
    echo "user default on nopass ~* &* +@all" > $ACL_FILE_CONF
  else
    echo "user default on >${REDIS_PASSWORD} ~* &* +@all" > $ACL_FILE_CONF
  fi
  [ -f "$EXTERNAL_ACL_FILE" ] && awk '$2!="default"' $EXTERNAL_ACL_FILE >> $ACL_FILE_CONF
}

getConfPassword() {
  if [[ "${SETUP_MODE}" == "sentinel" ]] ;then
    sed -n 's/^masterauth\s\+"\(.*\)"/\1/p' $SENTINEL_CONF_FILE | tail -1
  else
    sed -n 's/^masterauth\s\+"\(.*\)"/\1/p' $REDIS_CONF_FILE | tail -1
  fi
}


runRedisCmd() {
  local redisIp=$ maxTime=5 redisIp redisPort=6379 retCode=0 passwd="${REDIS_PASSWORD}" authOpt="" result
  redisIp=$(hostname -i)
  [[ "${SETUP_MODE}" == "sentinel" ]] && redisPort=26379
  while :
    do
    if [[ "$1" == "--timeout" ]]; then
      maxTime=$2 && shift 2
    elif [[ "$1" == "--ip" || "$1" == "-h" ]]; then
      redisIp=$2 && shift 2
    elif [[ "$1" == "--port" || "$1" == "-p" ]]; then
      redisPort=$2 && shift 2
    elif [[ "$1" == "--password" || "$1" == "-a" ]]; then
      passwd=$2 && shift 2
    else
      break
    fi
  done
  [ -n "$passwd" ] && authOpt="--no-auth-warning -a $passwd"
  result="$(timeout --preserve-status ${maxTime}s redis-cli $authOpt -h $redisIp -p $redisPort $@ 2>&1)" || retCode=$?
  if [ "$retCode" != 0 ] || [[ " $not_error " != *" $cmd "* && "$result" == *ERR* ]]; then
    echo "ERROR failed to run redis command '$@' ($retCode): $result." && retCode=$REDIS_COMMAND_EXECUTE_FAIL_ERR
  else
    echo "$result"
  fi
  return $retCode
}


aclLoad(){
  local redispasswd
  redispasswd=$(getConfPassword)
  if [[ "$1" == "--requirepass" ]] ; then
    export REDIS_PASSWORD=$2
    shift 2
  fi
  aclfileUpdate
  confPasswdUpdate
  runRedisCmd -a "$redispasswd" acl load
  if [[ "${SETUP_MODE}" != "sentinel" ]]; then
    runRedisCmd config set masterauth "${REDIS_PASSWORD}"
    runRedisCmd config set requirepass "${REDIS_PASSWORD}"
  fi
}

getRunId() {
  echo -n "${1-$(hostname --fqdn).}"|sha1sum|cut -f 1 -d " "
}

createNodesConf() {
  local runId
  if [[ -z "${POD_IP}" ]]; then
    POD_IP=$(hostname -i)
  fi
  runId=$(getRunId)
  {
    echo "$runId $POD_IP:6379@16379 myself,master - 0 0 0 connected"
    echo "vars currentEpoch 0 lastVoteEpoch 0"
  } > $REDIS_NODES_CONF_FILE
}

upateNodesConf() {
  local runId replaceCmd node cluster_list nodeIp nsDns
  mydns="$(hostname --fqdn)."
  nsDns=$(hostname --fqdn | sed "s/^$HOSTNAME.$STATEFULSET.//g")
  cluster_list=$(for i in  $STATEFULSET_LIST ; do dig srv *.$i.$nsDns +short | awk -v port=$REDIS_PORT '$3==port{print $NF}' ; done)
  for node in $cluster_list; do runId=$(getRunId $node)
    if [[ "$myDns" == "$node" ]] ;then
      [[ -z "${POD_IP}" ]] && POD_IP=$(hostname -i)
      replaceCmd="$replaceCmd; s/$runId [0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}:6379@16379/$runId $POD_IP:6379@16379/"
    else
      nodeIp="$(dig $node +short | awk '{print $1}')"
      if [[ -n "$nodeIp" ]]; then
        replaceCmd="$replaceCmd; s/$runId [0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}:6379@16379/$runId $nodeIp:6379@16379/"
      fi
    fi
  done
  sed -i "$replaceCmd" $REDIS_NODES_CONF_FILE
}

cmd=$1
shift 1
$cmd $@

