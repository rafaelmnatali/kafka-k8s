# Kafka on K8s

Resources for a tutorial that covers running KRaft mode [Kafka v3.5.x](https://docs.confluent.io/platform/current/installation/versions-interoperability.html) on a Minikube-based Kubernetes cluster.

## Environment

| Technology | Version |
| --- | --- |
| Minikube | v1.29.0 |
| Kubernetes | v1.26.1 |
| [Confluent Kafka](https://hub.docker.com/r/confluentinc/confluent-local) | 7.5.0 |
| [Kafka-UI](https://github.com/provectus/kafka-ui) | v0.7.1 |

## Namespace

This [yaml file](./00-namespace.yaml) defines a namespace for running Kafka in a Kubernetes cluster.
It isolates Kafka resources within a dedicated namespace for better organization and management.

## Confluent Kafka

This [yaml file](01-kafka-local.yaml) deploys a Kafka cluster within a Kubernetes namespace named `kafka`. It defines various Kubernetes resources required for setting up Kafka in a distributed manner.

Here's a breakdown of what this file does:

### Service Account (kind: ServiceAccount)

A service account named `kafka` is created in the `kafka` namespace. Service accounts are used to control permissions and access to resources within the cluster.

### Headless Service (kind: Service)

A [headless Service](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services) named `kafka-headless` is defined in the `kafka` namespace.

It exposes ports `9092` (for Kafka clients) and `29093` (for Kafka Controller). 

### StatefulSet (kind: StatefulSet)

A [StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) named `kafka` is configured in the `kafka` namespace with three replicas.

It manages Kafka pods and ensures they have stable hostnames and storage (`PersistentVolumes`).

Each pod is associated with the headless service `kafka-headless` and the service account `kafka.` The pods use the Confluent Kafka Docker image (version 7.5.0). At the time of writing, this is the latest Confluent release. 

Interesting to notice that this version uses the [Apache Kafka Raft (KRaft)](https://developer.confluent.io/learn/kraft/) as the consensus protocol removing Apache Kafka’s dependency on ZooKeeper for metadata management. 

## Usage

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

# Contributing
Feel free to contribute by opening issues or pull requests.

# License
This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.
