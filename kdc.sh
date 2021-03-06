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

HOSTS=(lresende-iop-2.fyre.ibm.com lresende-iop-3.fyre.ibm.com lresende-iop-4.fyre.ibm.com lresende-iop-5.fyre.ibm.com)
LOCALHOST="$(/bin/hostname -f)"

CLUSTER_MASTER=${HOSTS[0]}
CLUSTER_NODES=${HOSTS[@]:1}
CLUSTER_SIZE=${#HOSTS[@]}
NODES=("${HOSTS[@]:1}") ##Workaround to get node size
CLUSTER_NODE_SIZE=${#NODES[@]}

echo ">>> Cluster Configuration "
echo "Cluster Nodes.: ${HOSTS[@]}"
echo "Master Node...: $CLUSTER_MASTER"
echo "Data Nodes....: $CLUSTER_NODES"
echo "Cluster size..: $CLUSTER_NODE_SIZE"
echo ">>> "

REALM="IBM.COM"

echo -e "\n Installing kerberos RPMs"
yum -y install krb5-server krb5-libs krb5-workstation

echo -e "\n Configuring Kerberos"
if [ ! -f /etc/krb5.conf.backup ]; then
    cp /etc/krb5.conf /etc/krb5.conf.backup
fi
cp etc/krb5.conf /etc/krb5.conf
sed -i.bak "s/kerberos.example.com/$LOCALHOST/g" /etc/krb5.conf

if [ ! -f /var/kerberos/krb5kdc/kdc.conf.backup ]; then
    cp /var/kerberos/krb5kdc/kdc.conf /var/kerberos/krb5kdc/kdc.conf.backup
fi
cp var/kerberos/krb5kdc/kdc.conf /var/kerberos/krb5kdc/kdc.conf

if [ ! -f /var/kerberos/krb5kdc/kadm5.acl.backup ]; then
    cp /var/kerberos/krb5kdc/kadm5.acl /var/kerberos/krb5kdc/kadm5.acl.backup
fi
cp var/kerberos/krb5kdc/kadm5.acl /var/kerberos/krb5kdc/kadm5.acl

kdb5_util create -s

echo -e "\n Starting KDC services"
service krb5kdc start
service kadmin start
chkconfig krb5kdc on
chkconfig kadmin on

echo -e "\n Creating admin principal"
kadmin.local -q "addprinc admin/admin"

echo -e "\n Restarting kadmin"
service kadmin restart


for i in ${CLUSTER_NODES[@]}; do
  echo -e "\n Configuring Kerberos client at ${i}"
  yum -y install krb5-libs krb5-workstation

  ssh -o StrictHostKeyChecking=no root@${i} "if [ ! -f /etc/krb5.conf.backup ]; then cp /etc/krb5.conf /etc/krb5.conf.backup; fi"
  cat etc/krb5.conf | ssh -o StrictHostKeyChecking=no root@${i} "cat > /etc/krb5.conf"
  ssh -o StrictHostKeyChecking=no root@${i} "sed -i.bak \"s/kerberos.example.com/$CLUSTER_MASTER/g\" /etc/krb5.conf"
done
