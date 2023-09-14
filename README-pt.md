# Kafka em K8s

Recursos para um [tutorial](https://rafaelnatali.wixsite.com/rmn-technology/pt/post/executando-o-kafka-no-kubernetes-com-o-modo-kraft) que aborda a execução do [Kafka v3.5.x](https://docs.confluent.io/platform/current/installation/versions-interoperability.html) usando o algoritmo KRaft em um cluster Kubernetes baseado no Minikube.

A imagem `Confluent-Local` implanta o Apache Kafka juntamente com o `Confluent Community RestProxy`. É uma imagem experimental, projetada para fluxos de trabalho de desenvolvimento local e não é oficialmente suportada para cargas de trabalho de produção.

## Ambiente

| Tecnlologia | Versāo |
| --- | --- |
| Minikube | v1.29.0 |
| Docker | v23.0.5 |
| Kubernetes | v1.26.1 |
| [Confluent Kafka](https://hub.docker.com/r/confluentinc/confluent-local) | 7.5.0 |

## Namespace

Este [arquivo yaml](./00-namespace.yaml) define um [namespace](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/) para executar o Kafka em um cluster Kubernetes.
Ele isola os recursos do Kafka dentro de um _namespace_ dedicado para uma melhor organização e gerenciamento.

## Confluent Kafka

Este [arquivo yaml](01-kafka-local.yaml) implanta um cluster Kafka dentro de um _namespace_ chamado `kafka`. Ele define vários recursos do Kubernetes necessários para configurar o Kafka de maneira distribuída.

Aqui está uma explicação do que este arquivo faz:

### Service Account (kind: ServiceAccount)

Uma [Service Account](https://kubernetes.io/docs/concepts/security/service-accounts/) chamada `kafka` é criada no _namespace_ `kafka`. Contas de serviço (Service Accounts) são usadas para controlar permissões e acesso a recursos dentro do cluster.

### Headless Service (kind: Service)

Um [headless Service](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services) chamado `kafka-headless` é criado no _namespace_ `kafka`.

Ele expõe as portas 9092 (para clientes do Kafka) e 29093 (para o Controlador do Kafka). 

### StatefulSet (kind: StatefulSet)

Um [StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) hamado `kafka-headless` é criado no _namespace_ `kafka` com três réplicas.

Ele gerencia os pods do Kafka e garante que eles tenham nomes de host e armazenamento estáveis.

Cada pod está associado ao serviço `kafka-headless` e à conta de serviço `kafka`. Os pods usam a imagem Docker do Confluent Kafka (versão 7.5.0). No momento da escrita, esta é a versão mais recente da Confluent.

## Uso

Implemente o Kafka usando os seguintes comandos:

```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-kafka-local.yaml
```

Verifique a comunicação entre os brokers

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

# Contributing
Feel free to contribute by opening issues or pull requests.

# License
This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.
