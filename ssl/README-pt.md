# Kafka com SSL

- [Kafka com SSL](#kafka-com-ssl)
  - [Descriçāo](#descriçāo)
  - [Ambiente](#ambiente)
  - [Namespace](#namespace)
  - [Chaves e Certificados SSL para Kafka Broker](#chaves-e-certificados-ssl-para-kafka-broker)
    - [Chaves e Certificados](#chaves-e-certificados)
    - [Crie sua própria Autoridade Certificadora (AC)](#crie-sua-própria-autoridade-certificadora-ac)
    - [Assine o Certificado](#assine-o-certificado)
    - [ConfigMaps](#configmaps)
  - [Confluent Kafka](#confluent-kafka)
    - [Service Account (kind: ServiceAccount)](#service-account-kind-serviceaccount)
    - [Headless Service (kind: Service)](#headless-service-kind-service)
    - [StatefulSet (kind: StatefulSet)](#statefulset-kind-statefulset)
    - [Implantaçāo](#implantaçāo)
    - [Verifique a comunicação entre os brokers](#verifique-a-comunicação-entre-os-brokers)
    - [Crie um tópico usando SSL](#crie-um-tópico-usando-ssl)

## Descriçāo

Implantando e executando a Versão Comunitária do Kafka empacotada com o download da Comunidade Confluent e configurada para usar [encriptaçāo SSL](https://docs.confluent.io/platform/current/kafka/encryption.html#kafka-ssl-encryption).

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

## Chaves e Certificados SSL para Kafka Broker

O primeiro passo para habilitar a [criptografia SSL](https://docs.confluent.io/platform/current/kafka/encryption.html#encrypt-with-tls) é criar um par de chaves público/privado para cada servidor.

> :warning: Os comandos nesta seção foram executados em um contêiner Docker que estava rodando a imagem `openjdk:11.0.10-jre``, pois é a mesma versão do Java (Java 11) que o Confluent utiliza. Com essa abordagem, quaisquer possíveis problemas relacionados à versão do Java são evitados.

### Chaves e Certificados

Os comandos a seguir foram executados seguindo o [Confluent Security Tutorial](https://docs.confluent.io/platform/current/security/security_tutorial.html#security-tutorial):

```bash
docker run -it --rm \
  --name openjdk \
  --mount source=kafka-certs,target=/app \
  openjdk:11.0.10-jre
```

Dentro do contêiner Docker:

```bash
keytool -keystore kafka-0.server.keystore.jks -alias kafka-0 -keyalg RSA -genkey
```

Saída:

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

Repita o comando para os outros nós:

```bash
keytool -keystore kafka-1.server.keystore.jks -alias kafka-1 -keyalg RSA -genkey
```

```bash
keytool -keystore kafka-2.server.keystore.jks -alias kafka-2 -keyalg RSA -genkey
```

### Crie sua própria Autoridade Certificadora (AC)

1. Gere uma Autoridade Certificadora (AC) que consiste simplesmente em um par de chaves público/privado e um certificado, destinado a assinar outros certificados.

    ```bash
    openssl req -new -x509 -keyout ca-key -out ca-cert -days 90
    ```

    Saída:

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

2. Adicione a CA gerada ao **truststore dos clientes** para que os clientes confiem nesta AC:

    ```bash
    keytool -keystore kafka.client.truststore.jks -alias CARoot -importcert -file ca-cert
    ```

3. Adicione a CA gerada ao **truststore dos brokers** para que os brokers confiem nesta AC:

    ```bash
    keytool -keystore kafka-0.server.truststore.jks -alias CARoot -importcert -file ca-cert
    keytool -keystore kafka-1.server.truststore.jks -alias CARoot -importcert -file ca-cert
    keytool -keystore kafka-2.server.truststore.jks -alias CARoot -importcert -file ca-cert
    ```

### Assine o Certificado

Para assinar digitalmente todos os certificados na keystore com a AC que foi gerada:

1. Exporte o certificado do keystore:

    ```bash
    keytool -keystore kafka-0.server.keystore.jks -alias kafka-0 -certreq -file cert-file-kafka-0
    keytool -keystore kafka-1.server.keystore.jks -alias kafka-1 -certreq -file cert-file-kafka-1
    keytool -keystore kafka-2.server.keystore.jks -alias kafka-2 -certreq -file cert-file-kafka-2
    ```

2. Assine com a AC:

    ```bash
    openssl x509 -req -CA ca-cert -CAkey ca-key -in cert-file-kafka-0 -out cert-signed-kafka-0 -days 90 -CAcreateserial -passin pass:${ca-password}
    openssl x509 -req -CA ca-cert -CAkey ca-key -in cert-file-kafka-1 -out cert-signed-kafka-1 -days 90 -CAcreateserial -passin pass:${ca-password}
    openssl x509 -req -CA ca-cert -CAkey ca-key -in cert-file-kafka-2 -out cert-signed-kafka-2 -days 90 -CAcreateserial -passin pass:${ca-password}
    ```

    > :warning: Nāo esqueça de substituir a variável `${ca-password}`

3. Importe tanto o certificado da AC quanto o certificado assinado no keystore do broker:

    ```bash
    keytool -keystore kafka-0.server.keystore.jks -alias CARoot -importcert -file ca-cert
    keytool -keystore kafka-0.server.keystore.jks -alias kafka-0 -importcert -file cert-signed-kafka-0
    
    keytool -keystore kafka-1.server.keystore.jks -alias CARoot -importcert -file ca-cert
    keytool -keystore kafka-1.server.keystore.jks -alias kafka-1 -importcert -file cert-signed-kafka-1
    
    keytool -keystore kafka-2.server.keystore.jks -alias CARoot -importcert -file ca-cert
    keytool -keystore kafka-2.server.keystore.jks -alias kafka-2 -importcert -file cert-signed-kafka-2
    ```

> :warning: Os arquivos `keystore` e `truststore` serāo utilizados para criar os [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) para a nossa implantaçāo.

### ConfigMaps

Crie dois ConfigMaps, um para o Kafka Broker e outro para o Kafka Client.

- Kafka Broker

  Crie uma pasta local chamada `kafka-ssl` e copie os arquivos `keystore` e `truststore` para dentro da pasta. Além disso, crie um arquivo chamado `broker_creds` com a senha `${ca-password}`.

  Sua pasta deve se parecer com esta:

  ```bash
  ➜  kraft ls kafka-ssl   
  broker_creds                  kafka-0.server.truststore.jks kafka-1.server.truststore.jks kafka-2.server.truststore.jks
  kafka-0.server.keystore.jks   kafka-1.server.keystore.jks   kafka-2.server.keystore.jks
  ```

  Crie o ConfigMap:

  ```bash
  kubectl create configmap kafka-ssl --from-file kafka-ssl -n kafka
  kubectl describe configmaps -n kafka kafka-ssl  
  ```

  Saída:

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

  Crie uma pasta local chamada `kafka-client` e copie o arquivo `kafka.client.truststore.jks` para a pasta. Ademais, crie o arquivo `broker_creds` com o `${ca-password}` e um arquivo chamado `client_security.properties`.

  ```bash
  #client_security.properties
  security.protocol=SSL
  ssl.truststore.location=/etc/kafka/secrets/kafka.client.truststore.jks
  ssl.truststore.password=<redacted>
  ```

  Sua pasta deve se parecer com esta:

  ```bash
  ➜  kraft ls kafka-client 
  broker_creds                client_security.properties  kafka.client.truststore.jks
  ```

  Crie o ConfigMap:

  ```bash
  kubectl create configmap kafka-client --from-file kafka-client -n kafka
  kubectl describe configmaps -n kafka kafka-client  
  ```

  Saída:

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

Este [arquivo yaml](01-kafka-local.yaml) implanta um cluster Kafka dentro de um _namespace_ chamado `kafka`. Ele define vários recursos do Kubernetes necessários para configurar o Kafka de maneira distribuída.

Aqui está uma explicação do que este arquivo faz:

### Service Account (kind: ServiceAccount)

Uma [Service Account](https://kubernetes.io/docs/concepts/security/service-accounts/) chamada `kafka` é criada no _namespace_ `kafka`. Contas de serviço (Service Accounts) são usadas para controlar permissões e acesso a recursos dentro do cluster.

### Headless Service (kind: Service)

Um [headless Service](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services) chamado `kafka-headless` é criado no _namespace_ `kafka`.

Ele expõe as portas `9092` (para comunicação PLAINTEXT) e `9093` (para tráfego SSL).

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

### Crie um tópico usando SSL

Implemente o cliente Kafka com o seguinte comando:

```bash
kubectl apply -f 02-kafka-client.yaml
```

Verifique se o pod está em  `Running`:

```bash
kubectl get pods kafka-cli
```

Saída:

```bash
NAME        READY   STATUS    RESTARTS   AGE
kafka-cli   1/1     Running   0          12m
```

Conecte-se ao Pod `kafka-cli`:

```bash
kubectl exec -it kafka-cli -- bash
```

Crie um tópico chamado `test-ssl` com três partições e fator de replicaçāo três.

```bash
kafka-topics --create --topic test-ssl --partitions 3 --replication-factor 3 --bootstrap-server ${BOOTSTRAP_SERVER} --command-config /etc/kafka/secrets/client_security.properties 
Created topic test-ssl.
```

:warning: A variável de ambiente `BOOTSTRAP_SERVER` contém a lista dos brokers, economizando tempo ao digitar.

Liste todos os tópicos do Kafka:

```bash
kafka-topics --bootstrap-server kafka-0.kafka-headless.kafka.svc.cluster.local:9093 --list --command-config /etc/kafka/secrets/client_security.properties 
test
test-ssl
test-test
```
