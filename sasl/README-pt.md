# Kafka com SASL

- [Kafka com SASL](#kafka-with-sasl)
  - [Descriçāo](#descriçāo)
  - [Ambiente](#ambiente)
  - [Namespace](#namespace)
  - [Autenticaçāo SASL](#autenticaçāo-sasl)
    - [Broker](#broker)
    - [Cliente](#cliente)
  - [Confluent Kafka](#confluent-kafka)
    - [Service Account (kind: ServiceAccount)](#service-account-kind-serviceaccount)
    - [Headless Service (kind: Service)](#headless-service-kind-service)
    - [StatefulSet (kind: StatefulSet)](#statefulset-kind-statefulset)
    - [Implantaçāo](#implantaçāo)
    - [Verifique a comunicação entre os brokers](#verifique-a-comunicação-entre-os-brokers)
    - [Criar um tópico usando o endpoint SASL\_PLAINTEXT](#criar-um-tópico-usando-o-endpoint-sasl_plaintext)

## Descriçāo

Implantando e executando a Versão Comunitária do Kafka empacotada com o download da Comunidade Confluent e configurada para usar [autenticaçāo SASL/PLAIN](https://docs.confluent.io/platform/current/kafka/authentication_sasl/authentication_sasl_plain.html).

:warning: **PLAIN** versus **PLAINTEXT**: Não confunda o mecanismo SASL_PLAIN com a opção de criptografia sem TLS/SSL, chamada PLAINTEXT. Parâmetros de configuração, como `sasl.enabled.mechanisms` ou `sasl.mechanism.inter.broker.protocol`, podem ser configurados para usar o mecanismo SASL_PLAIN, enquanto `security.inter.broker.protocol` ou `listeners` podem ser configurados para usar a opção sem criptografia TLS/SSL, SASL_PLAINTEXT.

## Ambiente

| Technology | Version |
| --- | --- |
| Minikube | v1.29.0 |
| Docker | v23.0.5 |
| Kubernetes | v1.26.1 |
| [cp-kafka](https://hub.docker.com/r/confluentinc/cp-kafka) | 7.5.0 |

## Namespace

Este [arquivo yaml](./00-namespace.yaml) define um [namespace](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/) para executar o Kafka em um cluster Kubernetes.
Ele isola os recursos do Kafka dentro de um _namespace_ dedicado para uma melhor organização e gerenciamento.

## Autenticaçāo SASL

Precisamos configurar os brokers e clientes para utilizar a autenticaçāo `SASL`. Acesse a página [Kafka Broker and Controller Configurations for Confluent Platform](https://docs.confluent.io/platform/current/installation/configuration/broker-configs.html) para uma explicaçāo detalhadas das configurações.

### Broker

1. Habilite o mecanismos SASL/PLAIN no arquivo `server.properties` de cada broker.

    ```yaml
    # List of enabled mechanisms, can be more than one
    - name: KAFKA_SASL_ENABLED_MECHANISMS
      value: PLAIN
    
    # Specify one of of the SASL mechanisms
    - name: KAFKA_SASL_MECHANISM_INTER_BROKER_PROTOCOL
      value: PLAIN
    ```

2. Informe aos brokers do Kafka em quais portas devem ouvir as conexões SASL de clientes e interbroker. Configure as propriedades `listeners` e `advertised.listeners` da seguinte forma:

    ```yaml
    - command:
    ...
    export KAFKA_ADVERTISED_LISTENERS=SASL://${POD_NAME}.kafka-headless.kafka.svc.cluster.local:9092
    ...
    
    env:
    ...
    - name: KAFKA_LISTENER_SECURITY_PROTOCOL_MAP
      value: "CONTROLLER:PLAINTEXT,SASL:SASL_PLAINTEXT"
    - name: KAFKA_LISTENERS
      value: SASL://0.0.0.0:9092,CONTROLLER://0.0.0.0:29093
    ```

3. Configure o JAAS (Serviço de Autenticação e Autorização Java) no Kafka broker como a seguir:

    ```yaml
    - name: KAFKA_LISTENER_NAME_SASL_PLAIN_SASL_JAAS_CONFIG
      value: org.apache.kafka.common.security.plain.PlainLoginModule required username="admin" password="admin-secret" user_admin="admin-secret" user_kafkaclient1="kafkaclient1-secret"; 
    ```

### Cliente

1. Crie um [ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/) baseado no arquivo `sasl_client.properties`:

    ```bash
    kubectl create configmap kafka-client --from-file sasl_client.properties -n kafka
    kubectl describe configmaps -n kafka kafka-client 
    ```

    Saída:

    ```bash
    configmap/kafka-client created
    Name:         kafka-client
    Namespace:    kafka
    Labels:       <none>
    Annotations:  <none>

    Data
    ====
    sasl_client.properties:
    ----
    sasl.mechanism=PLAIN
    security.protocol=SASL_PLAINTEXT
    sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \
      username="kafkaclient1" \
      password="kafkaclient1-secret";

    BinaryData
    ====

    Events:  <none>
    ```

2. Monte o ConfigMap como um `volume`:

    ```yaml
    ...
    volumeMounts:
        - mountPath: /etc/kafka/secrets/
          name: kafka-client
    ...
    volumes:
    - name: kafka-client
      configMap: 
        name: kafka-client
    ```

## Confluent Kafka

Este [arquivo yaml](01-kafka-local.yaml) implanta um cluster Kafka dentro de um _namespace_ chamado `kafka`. Ele define vários recursos do Kubernetes necessários para configurar o Kafka de maneira distribuída.

Aqui está uma explicação do que este arquivo faz:

### Service Account (kind: ServiceAccount)

Uma [Service Account](https://kubernetes.io/docs/concepts/security/service-accounts/) chamada `kafka` é criada no _namespace_ `kafka`. Contas de serviço (Service Accounts) são usadas para controlar permissões e acesso a recursos dentro do cluster.

### Headless Service (kind: Service)

Um [headless Service](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services) chamado `kafka-headless` é criado no _namespace_ `kafka`.

Ele expõe as portas `9092` (para comunicação SASL_PLAINTEXT) e `9093`.

### StatefulSet (kind: StatefulSet)

Um [StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) hamado `kafka-headless` é criado no _namespace_ `kafka` com três réplicas.

Ele gerencia os pods do Kafka e garante que eles tenham nomes de host e armazenamento estáveis.

Cada pod está associado ao serviço `kafka-headless` e à conta de serviço `kafka`. Os pods usam a imagem Docker do Confluent Kafka (versão 7.5.0). No momento da escrita, esta é a versão mais recente da Confluent.

### Implantaçāo

Implemente o Kafka usando os seguintes comandos:

```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-kafka.yaml
```

### Verifique a comunicação entre os brokers

Agora deve haver três nós (brokers) Kafka, cada um em execução em pods separados dentro do seu cluster. A resolução de nomes para o headless Service e os três pods dentro do StatefulSet é configurada automaticamente pelo Kubernetes conforme são criados, permitindo a comunicação entre os brokers. Consulte a documentação relacionada para obter mais detalhes sobre esse recurso.

Você pode verificar os logs do primeiro pod com o seguinte comando:

```bash
kubectl logs kafka-0
```

A resoluçāo de nomes para os três pods pode demorar mais tempo do que o pod a iniciar, entāo, você pode ver erros `UnknownHostException`` nos logs durante a inicializaçāo:

```bash
WARN [RaftManager nodeId=2] Error connecting to node kafka-1.kafka-headless.kafka.svc.cluster.local:29093 (id: 1 rack: null) (org.apache.kafka.clients.NetworkClient) java.net.UnknownHostException: kafka-1.kafka-headless.kafka.svc.cluster.local         ... 
```

Eventualmente, cada pod irá resolver os nomes e iniciar com uma mensagem afirmando que o broker foi `unfenced`:

```bash
INFO [Controller 0] Unfenced broker: UnfenceBrokerRecord(id=1, epoch=176) (org.apache.kafka.controller.ClusterControlManager)
```

### Criar um tópico usando o endpoint SASL_PLAINTEXT

Você pode implantar o Cliente Kafka usando o seguinte comando:

```bash
kubectl apply -f 02-kafka-client.yaml
```

Verifique se o Pod está `Running`:

```bash
kubectl get pods 
```

Saída:

```bash
NAME        READY   STATUS    RESTARTS   AGE
kafka-cli   1/1     Running   0          12m
```

Conecte-se ao pod `kafka-cli`:

```bash
kubectl exec -it kafka-cli -- bash
```

Crie um tópico chamado `test-sasl` com três partições e um fator de replicação de 3.

```bash
kafka-topics --create --topic test-sasl --partitions 3 --replication-factor 3 --bootstrap-server ${BOOTSTRAP_SERVER} --command-config /etc/kafka/secrets/sasl_client.properties 
Created topic test-sasl.
```

:warning: A variável de ambiente BOOTSTRAP_SERVER contém a lista dos brokers, portanto, economizamos tempo digitando.

Liste todos os tópicos no Kafka:

```bash
kafka-topics --bootstrap-server ${BOOTSTRAP_SERVER} -list --command-config /etc/kafka/secrets/sasl_client.properties 
test
test-sasl
test-ssl
test-test
```
