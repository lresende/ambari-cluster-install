#!/bin/bash
#
# Copyright 2015 Luciano Resende
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ROOT=`dirname $0`
ROOT=`cd $ROOT; pwd`

if [ -z "$1" ]
then
  echo "Usage:"
  echo "  iop-cluster.sh [option]"
  echo " "
  echo "    -uninstall : uninstall an IOP cluster"
  echo "    -install   : install Ambari Server and Agents on an IOP cluster"
  echo "    -deploy    : Silent deploy services to an IOP Cluster"
  echo "    -resetdb   : Reset the Ambari database (usefull to start fresh when install fails)"
  echo " "
  exit 1
fi

#HOSTS=(bdavm317.svl.ibm.com bdavm318.svl.ibm.com bdavm319.svl.ibm.com bdavm280.svl.ibm.com bdavm281.svl.ibm.com bdavm509.svl.ibm.com)
LOCALHOST="$(/bin/hostname -f)"
HOSTS=("$LOCALHOST")

CLUSTER_MASTER=${HOSTS[0]}
CLUSTER_NODES=${HOSTS[@]:1}
CLUSTER_SIZE=${#HOSTS[@]}
NODES=("${HOSTS[@]:1}") ##Workaround to get node size
CLUSTER_NODE_SIZE=${#NODES[@]}

echo ">>> Cluster Configuration "
echo "Cluster Nodes.: ${HOSTS[@]}"
echo "Master Node...: $CLUSTER_MASTER"
echo "Data Nodes....: $CLUSTER_NODES"
echo ">>> "

## Cleanup
if [ "$1" = "--all"  -o  "$1" = "--uninstall"  ]
then
  ambari-server stop
  for i in ${HOSTS[@]}; do
    ssh root@${i} "ambari-agent stop"
    ssh -t root@${i} "python /usr/lib/python2.6/site-packages/ambari_commons/host_uninstall.py"
    ssh root@${i} "rm -rf /etc/yum.repos.d/IOP.repo"
    ssh root@${i} "rm -rf /etc/yum.repos.d/IOP-UTILS.repo"
    ssh root@${i} "rm -rf /etc/yum.repos.d/ambari.repo"
    ssh root@${i} "rm -rf /var/log/ambari-agent"
    ssh root@${i} "rm -rf /var/log/knox"
    ssh root@${i} "yum -y remove ambari-agent"
    ssh root@${i} "rm -rf /etc/ambari-agent"
    ssh root@${i} "rpm -e ambari-agent"
  done
  yum -y remove ambari-server
  rm -rf /etc/ambari-server
  rm -rf /var/log/ambari-server/
  su - postgres -c "dropdb ambari"
  su - postgres -c "dropdb ambarirca"
  yum -y remove postgresql
  rpm -e ambari-server
fi

## Install ambari
if [ "$1" = "--all"  -o  "$1" = "--install"  ]
then
  # setup ambari repository
  yum clean all
  #cd /etc/yum.repos.d && curl -O curl -O $REPOSITORY/ambari.repo > ambari.repo
  cp etc/yum.repos.d/ambari.repo /etc/yum.repos.d/ambari.repo

  # ambari server setup
  yum -y install ambari-server
  ambari-server setup --silent
  # use port 8081 to avoid issues when using vpn
  echo "client.api.port=8081" >> /etc/ambari-server/conf/ambari.properties
  # start ambari server
  /usr/sbin/ambari-server start

  # ambari agent setup
  for i in ${HOSTS[@]}; do
    # setup ambari repository
    ssh root@${i} "yum clean all"
    cat etc/yum.repos.d/ambari.repo | ssh root@${i} "cat > /etc/yum.repos.d/ambari.repo"
    # ambari agent setup
    ssh root@${i} "yum -y install ambari-agent"
    ssh root@${i} "sed -i.bak \"s@hostname=localhost@hostname=$CLUSTER_MASTER@g\" /etc/ambari-agent/conf/ambari-agent.ini"
    # start ambari agent
    ssh root@${i} "/usr/sbin/ambari-agent start"
  done

fi

## Deploy
if [ "$1" = "--all"  -o  "$1" = "--deploy"  ]
then
  sed -i.bak "s@#MASTER@$CLUSTER_MASTER@g" hostmapping.json

  if [ "$CLUSTER_SIZE" -gt 1 ]
  then
      # This is a CLUSTER
      echo "Processing Cluster Host Mappings "
      HOST_MAPPING=", {\"name\": \"slave\", \"hosts\": [ "
      COUNTER=1
      for i in ${CLUSTER_NODES[@]}; do
        HOST_MAPPING="$HOST_MAPPING {\"fqdn\":\"${i}\"}"
        if [ $COUNTER -lt $CLUSTER_NODE_SIZE ]
          then
            HOST_MAPPING="$HOST_MAPPING,"
            let COUNTER=COUNTER+1
          fi
      done
      HOST_MAPPING="$HOST_MAPPING ] }"
      #echo ">>>" $HOST_MAPPING
      sed -i.bak "s@#NODES@$HOST_MAPPING@g" hostmapping.json
  else
      # This is a SINGLE NODE
      echo "Processing Single Node Host Mappings"
      sed -i.bak "s@#NODES@@g" hostmapping.json
  fi

  curl -H "X-Requested-By: ambari" -X GET -u admin:admin http://localhost:8081/api/v1/hosts
  sleep 3s
  curl -H "X-Requested-By: ambari" -X GET -u admin:admin http://localhost:8081/api/v1/blueprints
  sleep 3s
  if [ "$CLUSTER_SIZE" = 1 ]
  then
    echo "Using single node blueprint"
    curl -H "X-Requested-By: ambari" -X POST -u admin:admin -d @blueprint_single_node.json http://localhost:8081/api/v1/blueprints/iop?validate_topology=false
  else
    echo "Using multi node blueprint"
    curl -H "X-Requested-By: ambari" -X POST -u admin:admin -d @blueprint_multi_node.json http://localhost:8081/api/v1/blueprints/iop?validate_topology=false
  fi
  sleep 3s
  curl -H "X-Requested-By: ambari" -X GET -u admin:admin http://localhost:8081/api/v1/blueprints
  sleep 3s
  curl -H "X-Requested-By: ambari" -X GET -u admin:admin http://localhost:8081/api/v1/clusters
  sleep 3s
  curl -H "X-Requested-By: ambari" -X POST -u admin:admin -d @hostmapping.json http://localhost:8081/api/v1/clusters/iop

  ## wait for finishing deploying
  while true;
     STATUS="$(curl --silent -H 'X-Requested-By: ambari' -X GET -u admin:admin http://localhost:8081/api/v1/clusters/iop/requests/1 | grep request_status)"
     if [[ $STATUS == *"COMPLETED"* ]]
     then
        printf "Deployment $STATUS";
        break;
     elif [[ $STATUS == *"FAILED"* ]]
     then
        printf "Deployment $STATUS";
        break;
     elif [[ $STATUS == *"ABORTED"* ]]
     then
        printf "Deployment $STATUS";
        break;
     else
        echo "Deployment $STATUS"
     fi
     do sleep 60s;
  done
fi

## Reset the database
if [ "$1" = "--resetdb"  ]
then
  ambari-server stop
  for i in ${HOSTS[@]}; do
    ssh root@${i} "ambari-agent stop"
  done
  ambari-server reset --silent
  ambari-server start
  for i in ${HOSTS[@]}; do
    ssh root@${i} "ambari-agent start"
  done
  sleep 3s
  curl -H "X-Requested-By: ambari" -X GET -u admin:admin http://localhost:8081/api/v1/hosts
fi
