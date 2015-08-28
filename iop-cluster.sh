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

REPOSITORY=http://birepo-build.svl.ibm.com/repos/Ambari/RHEL7/x86_64/2.1.0/4.1.0.0_IOP_GM

HOSTS=(bdvs268.svl.ibm.com bdvs269.svl.ibm.com bdvs270.svl.ibm.com bdvs271.svl.ibm.com)
CLUSTER_MASTER=bdvs268.svl.ibm.com
CLUSTER_DATA_1=bdvs269.svl.ibm.com
CLUSTER_DATA_2=bdvs270.svl.ibm.com
CLUSTER_DATA_3=bdvs271.svl.ibm.com

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
    ssh root@${i} "rm -rf /var/log/knox"
    ssh root@${i} "yum -y remove ambari-agent"
  done
  yum -y remove ambari-server
  su - postgres -c "dropdb ambari"
  su - postgres -c "dropdb ambarirca"
  yum -y remove postgresql
fi

## Install ambari
if [ "$1" = "--all"  -o  "$1" = "--install"  ]
then
  # setup ambari repository
  yum clean all
  cd /etc/yum.repos.d && curl -O curl -O $REPOSITORY/ambari.repo > ambari.repo
  #cp etc/yum.repos.d/ambari.repo /etc/yum.repos.d/ambari.repo

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
    ssh root@${i} "cd /etc/yum.repos.d && curl -O curl -O $REPOSITORY/ambari.repo > ambari.repo"
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
  sed -i.bak "s@#DATA_1@$CLUSTER_DATA_1@g" hostmapping.json
  sed -i.bak "s@#DATA_2@$CLUSTER_DATA_2@g" hostmapping.json
  sed -i.bak "s@#DATA_3@$CLUSTER_DATA_3@g" hostmapping.json

  curl -H "X-Requested-By: ambari" -X GET -u admin:admin http://localhost:8081/api/v1/hosts
  sleep 3s
  curl -H "X-Requested-By: ambari" -X GET -u admin:admin http://localhost:8081/api/v1/blueprints
  sleep 3s
  curl -H "X-Requested-By: ambari" -X POST -u admin:admin -d @blueprint_multi_node.json http://localhost:8081/api/v1/blueprints/iop?validate_topology=false
  sleep 3s
  curl -H "X-Requested-By: ambari" -X GET -u admin:admin http://localhost:8081/api/v1/blueprints
  sleep 3s
  curl -H "X-Requested-By: ambari" -X GET -u admin:admin http://localhost:8081/api/v1/clusters
  sleep 3s
  curl -H "X-Requested-By: ambari" -X POST -u admin:admin -d @clustermapping.json http://localhost:8081/api/v1/clusters/iop

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
