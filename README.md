# Kafka on K8s

Resources for a [tutorial](https://rafaelnatali.wixsite.com/rmn-technology/post/running-kafka-in-kubernetes-with-kraft-mode) that covers running [Kafka v3.5.x](https://docs.confluent.io/platform/current/installation/versions-interoperability.html) using the consensus protocol [Apache Kafka Raft (KRaft)](https://developer.confluent.io/learn/kraft/) on a Minikube-based Kubernetes cluster.

`Confluent-Local` image deploys Apache Kafka along with Confluent Community RestProxy. It is experimental, built for local development workflows and is not officially supported for production workloads.


<!-- @import "[TOC]" {cmd="toc" depthFrom=1 depthTo=6 orderedList=false} -->


## Environment

| Technology | Version |
| --- | --- |
| Minikube | v1.29.0 |
| Docker | v23.0.5 |
| Kubernetes | v1.26.1 |
| [Confluent Kafka](https://hub.docker.com/r/confluentinc/confluent-local) | 7.5.0 |

## Namespace

This [yaml file](./00-namespace.yaml) defines a [namespace](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/) for running Kafka in a Kubernetes cluster.
It isolates Kafka resources within a dedicated namespace for better organization and management.

## Confluent Kafka

This [yaml file](01-kafka-local.yaml) deploys a Kafka cluster within a Kubernetes namespace named `kafka`. It defines various Kubernetes resources required for setting up Kafka in a distributed manner.

Here's a breakdown of what this file does:

### Service Account (kind: ServiceAccount)

A [Service Account](https://kubernetes.io/docs/concepts/security/service-accounts/) named `kafka` is created in the `kafka` namespace. Service accounts are used to control permissions and access to resources within the cluster.

### Headless Service (kind: Service)

A [headless Service](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services) named `kafka-headless` is defined in the `kafka` namespace.

It exposes ports `9092` (for Kafka clients) and `29093` (for Kafka Controller). 

### StatefulSet (kind: StatefulSet)

A [StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) named `kafka` is configured in the `kafka` namespace with three replicas.

It manages Kafka pods and ensures they have stable hostnames and storage.

Each pod is associated with the headless service `kafka-headless` and the service account `kafka.` The pods use the Confluent Kafka Docker image (version 7.5.0). At the time of writing, this is the latest Confluent release. 

## Usage

### Deploy 

You can deploy Kafka using the following commands:

```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-kafka-local.yaml
```

Check if the Pods are `Running`:

```bash
kubectl get pods
```

Output:

```bash
NAME      READY   STATUS    RESTARTS   AGE
kafka-0   1/1     Running   0          61s
kafka-1   1/1     Running   0          92s
kafka-2   1/1     Running   0          2m33s
```

### Verify communication across brokers

There should now be three Kafka brokers each running on separate pods within your cluster. Name resolution for the headless service and the three pods within the StatefulSet is automatically configured by Kubernetes as they are created, allowing for communication across brokers. See the related documentation for more details on this feature.

You can check the first pod's logs with the following command:

```bash
kubectl logs kafka-0
```

The name resolution of the three pods can take more time to work than it takes the pods to start, so you may see `UnknownHostException warnings`` in the pod logs initially:

```bash
WARN [RaftManager nodeId=2] Error connecting to node kafka-1.kafka-headless.kafka.svc.cluster.local:29093 (id: 1 rack: null) (org.apache.kafka.clients.NetworkClient) java.net.UnknownHostException: kafka-1.kafka-headless.kafka.svc.cluster.local         ...
```

But eventually each pod will successfully resolve pod hostnames and end with a message stating the broker has been unfenced:

```bash
INFO [Controller 0] Unfenced broker: UnfenceBrokerRecord(id=1, epoch=176) (org.apache.kafka.controller.ClusterControlManager)
```

### Create a topic and recovery

The Kafka StatefulSet should now be up and running successfully. Now we can create a topic, verify the replication of this topic, and then see how the system recovers when a pod is deleted.

Open terminal on pod `kafka-0``:

```bash
kubectl exec -it kafka-0 -- bash
```

Create a topic named `test` with three partitions and a replication factor of 3. 

```bash
kafka-topics --create --topic test --partitions 3 --replication-factor 3 --bootstrap-server kafka-0.kafka-headless.kafka.svc.cluster.local:9092
```

Verify the topic partitions are replicated across all three brokers:

```bash
kafka-topics --describe --topic test --bootstrap-server kafka-0.kafka-headless.kafka.svc.cluster.local:9092
```

The output of the above command will be similar to the following:

```bash
Topic: test     TopicId: WmMXgsr2RcyZU9ohfoTUWQ PartitionCount: 3       ReplicationFactor: 3    Configs: 
        Topic: test     Partition: 0    Leader: 0       Replicas: 0,1,2 Isr: 0,1,2
        Topic: test     Partition: 1    Leader: 1       Replicas: 1,2,0 Isr: 1,2,0
        Topic: test     Partition: 2    Leader: 2       Replicas: 2,0,1 Isr: 2,0,1
The output above shows there are 3 in-sync replicas.
```

Now we will simulate a loss of one of the brokers by deleting the associated pod. Open a new local terminal for the following command:

```bash
kubectl scale sts kafka --replicas 2
```

In the remote `kafka-0` terminal, check topic replication to see that only 2 replicas exist:

```bash
kafka-topics --describe --topic test --bootstrap-server kafka-0.kafka-headless.kafka.svc.cluster.local:9092
Topic: test     TopicId: WmMXgsr2RcyZU9ohfoTUWQ PartitionCount: 3 ReplicationFactor: 3     Configs: 
        Topic: test     Partition: 0    Leader: 0       Replicas: 0,1,2    Isr: 0,1
        Topic: test     Partition: 1    Leader: 1       Replicas: 1,2,0    Isr: 0,1
        Topic: test     Partition: 2    Leader: 0       Replicas: 2,0,1    Isr: 0,1
```

Notice that there are only two in-sync replicas for each partition (brokers 0 and 1).

# Contributing
Feel free to contribute by opening issues or pull requests.

# License
This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.
