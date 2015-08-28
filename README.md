# Apache Ambari/IOP Cluster Silent Installer 

This is an utility script that helps with installation, deployment, and cleanup of an Apache Ambari Cluster. It uses the IBM IOP 4.1 stack definition and take advantage of Apache Ambari Blueprints to perform silent deployment of the cluster.

## Before you start

Clone the repository in the master node of the cluster
```
git clone https://github.com/lresende/ambari-cluster-install.git
cd ambari-cluster-install
```

Update information related to your cluster in iop-cluster.sh :

Repository: IOP Repository URL 
Hosts     : A list of FQDN for all cluster nodes

## Installing Ambary and deploying the cluster 

Now that we have the cluster information properly configured in the iop-cluster.sh, we can easily install the cluster issuing the following command :

```
sh iop-cluster --install
```

This installs Ambari server on the master node and then the Ambari Agent on each single node.

To deploy, we would issue the following command :

```
sh iop-cluster --deploy
```

Now the cluster is ready to use. Point your browser to the URL below and loggin using the default admin/admin account.

```
http://<master-node>:8081
```


## Troubleshooting

Comming soon.
