# Kafka with SSL

- [Kafka with SSL](#kafka-with-ssl)
  - [Description](#description)
  - [Environment](#environment)
  - [Namespace](#namespace)
  - [Kafka Broker SSL Keys and Certificates](#kafka-broker-ssl-keys-and-certificates)
    - [Server keys and certificates](#server-keys-and-certificates)
    - [Create your own Certificate Authority (CA)](#create-your-own-certificate-authority-ca)
    - [Sign the certificate](#sign-the-certificate)
    - [ConfigMaps](#configmaps)
  - [Confluent Kafka](#confluent-kafka)
    - [Service Account (kind: ServiceAccount)](#service-account-kind-serviceaccount)
    - [Headless Service (kind: Service)](#headless-service-kind-service)
    - [StatefulSet (kind: StatefulSet)](#statefulset-kind-statefulset)
    - [Deploy](#deploy)
    - [Verify communication across brokers](#verify-communication-across-brokers)
    - [Create a topic using the SSL endpoint](#create-a-topic-using-the-ssl-endpoint)

## Description

Deploying and running the Community Version of Kafka packaged with the Confluent Community download and configured to use [SSL Encryption](https://docs.confluent.io/platform/current/kafka/encryption.html#kafka-ssl-encryption).

## Environment

| Technology | Version |
| --- | --- |
| Minikube | v1.29.0 |
| Docker | v23.0.5 |
| Kubernetes | v1.26.1 |
| [cp-kafka](https://hub.docker.com/r/confluentinc/cp-kafka) | 7.5.0 |

## Namespace

This [yaml file](./00-namespace.yaml) defines a [namespace](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/) for running Kafka in a Kubernetes cluster.
It isolates Kafka resources within a dedicated namespace for better organization and management.

## Kafka Broker SSL Keys and Certificates

The first step to enable [SSL encryption](https://docs.confluent.io/platform/current/kafka/encryption.html#encrypt-with-tls) is to create public/private key pair for every server.

> :warning: The commands in this section were executed in a Docker container running the image `openjdk:11.0.10-jre` because it's the same Java version (Java 11) that Confluent runs. With this approach, any possible Java version-related issue is prevented.

### Server keys and certificates

The next commands were executed following the [Confluent Security Tutorial](https://docs.confluent.io/platform/current/security/security_tutorial.html#security-tutorial):

```bash
docker run -it --rm \
  --name openjdk \
  --mount source=kafka-certs,target=/app \
  openjdk:11.0.10-jre
```

Once in the Docker container:

```bash
keytool -keystore kafka-0.server.keystore.jks -alias kafka-0 -keyalg RSA -genkey
```

Output:

```bash
Enter keystore password:  
Re-enter new password: 
What is your first and last name?
  [Unknown]:  kafka-0.kafka-headless.kafka.svc.cluster.local
What is the name of your organizational unit?
  [Unknown]:  test
What is the name of your organization?
  [Unknown]:  test
What is the name of your City or Locality?
  [Unknown]:  Liverpool
What is the name of your State or Province?
  [Unknown]:  Merseyside
What is the two-letter country code for this unit?
  [Unknown]:  UK
Is CN=kafka-0.kafka-headless.kafka.svc.cluster.local, OU=test, O=test, L=Liverpool, ST=Merseyside, C=UK correct?
  [no]:  yes
```

Repeating the command for each broker:

```bash
keytool -keystore kafka-1.server.keystore.jks -alias kafka-1 -keyalg RSA -genkey
```

```bash
keytool -keystore kafka-2.server.keystore.jks -alias kafka-2 -keyalg RSA -genkey
```

### Create your own Certificate Authority (CA)

1. Generate a CA that is simply a public-private key pair and certificate, and it is intended to sign other certificates.

    ```bash
    openssl req -new -x509 -keyout ca-key -out ca-cert -days 90
    ```

    Output:

    ```bash
    Generating a RSA private key
    ...+++++
    ........+++++
    writing new private key to 'ca-key'
    Enter PEM pass phrase:
    Verifying - Enter PEM pass phrase:
    -----
    You are about to be asked to enter information that will be incorporated
    into your certificate request.
    What you are about to enter is what is called a Distinguished Name or a DN.
    There are quite a few fields but you can leave some blank
    For some fields there will be a default value,
    If you enter '.', the field will be left blank.
    -----
    Country Name (2 letter code) [AU]:UK
    State or Province Name (full name) [Some-State]:Merseyside
    Locality Name (eg, city) []:Liverpool
    Organization Name (eg, company) [Internet Widgits Pty Ltd]:test
    Organizational Unit Name (eg, section) []:test
    Common Name (e.g. server FQDN or YOUR name) []:*.kafka-headless.kafka.svc.cluster.local
    Email Address []:
    ```

2. Add the generated CA to the **clients’ truststore** so that the clients can trust this CA:

    ```bash
    keytool -keystore kafka.client.truststore.jks -alias CARoot -importcert -file ca-cert
    ```

3. Add the generated CA to the **brokers’ truststore** so that the brokers can trust this CA.

    ```bash
    keytool -keystore kafka-0.server.truststore.jks -alias CARoot -importcert -file ca-cert
    keytool -keystore kafka-1.server.truststore.jks -alias CARoot -importcert -file ca-cert
    keytool -keystore kafka-2.server.truststore.jks -alias CARoot -importcert -file ca-cert
    ```

### Sign the certificate

To sign all certificates in the keystore with the CA that you generated:

1. Export the certificate from the keystore:

    ```bash
    keytool -keystore kafka-0.server.keystore.jks -alias kafka-0 -certreq -file cert-file-kafka-0
    keytool -keystore kafka-1.server.keystore.jks -alias kafka-1 -certreq -file cert-file-kafka-1
    keytool -keystore kafka-2.server.keystore.jks -alias kafka-2 -certreq -file cert-file-kafka-2
    ```

2. Sign it with the CA:

    ```bash
    openssl x509 -req -CA ca-cert -CAkey ca-key -in cert-file-kafka-0 -out cert-signed-kafka-0 -days 90 -CAcreateserial -passin pass:${ca-password}
    openssl x509 -req -CA ca-cert -CAkey ca-key -in cert-file-kafka-1 -out cert-signed-kafka-1 -days 90 -CAcreateserial -passin pass:${ca-password}
    openssl x509 -req -CA ca-cert -CAkey ca-key -in cert-file-kafka-2 -out cert-signed-kafka-2 -days 90 -CAcreateserial -passin pass:${ca-password}
    ```

    > :warning: Don't forget to substitute `${ca-password}`

3. Import both the certificate of the CA and the signed certificate into the broker keystore:

    ```bash
    keytool -keystore kafka-0.server.keystore.jks -alias CARoot -importcert -file ca-cert
    keytool -keystore kafka-0.server.keystore.jks -alias kafka-0 -importcert -file cert-signed-kafka-0
    
    keytool -keystore kafka-1.server.keystore.jks -alias CARoot -importcert -file ca-cert
    keytool -keystore kafka-1.server.keystore.jks -alias kafka-1 -importcert -file cert-signed-kafka-1
    
    keytool -keystore kafka-2.server.keystore.jks -alias CARoot -importcert -file ca-cert
    keytool -keystore kafka-2.server.keystore.jks -alias kafka-2 -importcert -file cert-signed-kafka-2
    ```

> :warning: The `keystore` and `truststore` files will be used to create the [ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/) for our deployment.

### ConfigMaps

Create two ConfigMaps, one for the Kafka Broker and another one for our Kafka Client.

- Kafka Broker

  Create a local folder `kafka-ssl` and copy the `keystore` and `truststore` files into the folder. In addition, create a file `broker_creds` with the `${ca-password}`.

  Your folder should look similar to this:

  ```bash
  ➜  kraft ls kafka-ssl   
  broker_creds                  kafka-0.server.truststore.jks kafka-1.server.truststore.jks kafka-2.server.truststore.jks
  kafka-0.server.keystore.jks   kafka-1.server.keystore.jks   kafka-2.server.keystore.jks
  ```

  Create the ConfigMap:

  ```bash
  kubectl create configmap kafka-ssl --from-file kafka-ssl -n kafka
  kubectl describe configmaps -n kafka kafka-ssl  
  ```

  Output:

  ```bash
  Name:         kafka-ssl
  Namespace:    kafka
  Labels:       <none>
  Annotations:  <none>
  
  Data
  ====
  broker_creds:
  ----
  <redacted>
  
  
  BinaryData
  ====
  kafka-0.server.keystore.jks: 5001 bytes
  kafka-0.server.truststore.jks: 1306 bytes
  kafka-1.server.keystore.jks: 5001 bytes
  kafka-1.server.truststore.jks: 1306 bytes
  kafka-2.server.keystore.jks: 5001 bytes
  kafka-2.server.truststore.jks: 1306 bytes
  
  Events:  <none>
  ```

- Kafka Client

  Create a local folder `kafka-client` and copy the `kafka.client.truststore.jks` file into the folder. In addition, create a file `broker_creds` with the `${ca-password}` and a file `client_security.properties`.

  ```bash
  #client_security.properties
  security.protocol=SSL
  ssl.truststore.location=/etc/kafka/secrets/kafka.client.truststore.jks
  ssl.truststore.password=<redacted>
  ```

  Your folder should look similar to this:

  ```bash
  ➜  kraft ls kafka-client 
  broker_creds                client_security.properties  kafka.client.truststore.jks
  ```

  Create the ConfigMap:

  ```bash
  kubectl create configmap kafka-client --from-file kafka-client -n kafka
  kubectl describe configmaps -n kafka kafka-client  
  ```

  Output:

  ```bash
  Name:         kafka-client
  Namespace:    kafka
  Labels:       <none>
  Annotations:  <none>
  
  Data
  ====
  broker_creds:
  ----
  <redacted>
  
  client_security.properties:
  ----
  security.protocol=SSL
  ssl.truststore.location=/etc/kafka/secrets/kafka.client.truststore.jks
  ssl.truststore.password=test1234
  ssl.endpoint.identification.algorithm=
  
  BinaryData
  ====
  kafka.client.truststore.jks: 1306 bytes
  
  Events:  <none>
  ```

## Confluent Kafka

This [yaml file](01-kafka.yaml) deploys a Kafka cluster within a Kubernetes namespace named `kafka`. It defines various Kubernetes resources required for setting up Kafka in a distributed manner.

Here's a breakdown of what this file does:

### Service Account (kind: ServiceAccount)

A [Service Account](https://kubernetes.io/docs/concepts/security/service-accounts/) named `kafka` is created in the `kafka` namespace. Service accounts are used to control permissions and access to resources within the cluster.

### Headless Service (kind: Service)

A [headless Service](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services) named `kafka-headless` is defined in the `kafka` namespace.

It exposes ports `9092` (for PLAINTEXT communication) and `9093` (for SSL traffic).

### StatefulSet (kind: StatefulSet)

A [StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) named `kafka` is configured in the `kafka` namespace with three replicas.

It manages Kafka pods and ensures they have stable hostnames and storage.

Each pod is associated with the headless service `kafka-headless` and the service account `kafka.` The pods use the Confluent Kafka Docker image (version 7.5.0). At the time of writing, this is the latest Confluent release.

### Deploy

You can deploy Kafka using the following commands:

```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-kafka.yaml
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

### Create a topic using the SSL endpoint

You can deploy Kafka Client using the following command:

```bash
kubectl apply -f 02-kafka-client.yaml
```

Check if the Pod is `Running`:

```bash
kubectl get pods 
```

Output:

```bash
NAME        READY   STATUS    RESTARTS   AGE
kafka-cli   1/1     Running   0          12m
```

Connect to the pod `kafka-cli`:

```bash
kubectl exec -it kafka-cli -- bash
```

Create a topic named `test-ssl` with three partitions and a replication factor of 3.

```bash
kafka-topics --create --topic test-ssl --partitions 3 --replication-factor 3 --bootstrap-server ${BOOTSTRAP_SERVER} --command-config /etc/kafka/secrets/client_security.properties 
Created topic test-ssl.
```

:warning: The environment variable `BOOTSTRAP_SERVER` contains the list of the brokers, therefore, we save time in typing.

List all the topics in Kafka:

```bash
kafka-topics --bootstrap-server kafka-0.kafka-headless.kafka.svc.cluster.local:9093 --list --command-config /etc/kafka/secrets/client_security.properties 
test
test-ssl
test-test
```
