# Processamento de mensagens dependentes

Nesta aplicação estamos analisando como se dá o processamento de mensagens que possuem ações dependentes.

- Problema: Mensagens chegam na ordem, mas por conta do paralelismo, as que chegam depois podem ser processadas antes.

Este projeto foi implementando utilizando o método de resolução 2 descrito adiante

## Biblioteca para ingestão de dados
Aqui estaremos utilizando a Broadway. Para outras bibliotecas o fluxo e configurações podem variar.

## Message Broker
Aqui estamos utilizando o RabbitMQ, mas a ideia se aplica a qualquer outra ferramenta.

## Mecanismos de persistência
Para persistir os dados estamos utilizando o ETS.

## Mensagens teste
Estaremos utilizando mensagens referentes a pedidos com o seguinte formato: `"#{order_id},#{message_number},#{action}"`

As mensagens com ação de autorização sempre serão geradas antes das mensagens com ação de captura. Por exemplo, se executarmos o comando para o envio de 6 mensagens, teremos os seguintes envios pelo Message Broker:

`0,1,auth`  
`0,2,capture`  
`1,3,auth`  
`1,4,capture`  
`2,5,auth`  
`2,6,capture`


## Métodos de resolução
### Método 1: Remover paralelismo (não indicado)
Uma forma de elimitar este problema (dados que as mensagens chegam em ordem) é removendo o paralelismo. Tendo só uma linha de fluxo forçamos nosso pipeline a processar as mensagens uma por vez.

#### Como remover o paralelismo
Na função que inicia o processo do pipeline definimos o valor do atributo `concurrency` para 1:
```elixir
  def start_link(_args) do
    options = [
      name: OrdersPipeline,
      producer: [
        module: {@producer, @producer_config}
      ],
      processors: [
        default: [
          concurrency: 1 # Eliminando paralelismo.
        ]
      ]
    ]

    Broadway.start_link(__MODULE__, options)
  end
```

Execute a função de envio de mensagens:
- entre no terminal  
`iex -S mix`

- envie as mensagens
`send_message.(6)`

Ao enviarmos as mensagens teremos os seguintes logs:

```sh
"ORDER 0: MESSAGE TO AUTHORIZE" - mensagem com ação de autorização
"ORDER 0: AUTHORIZED" - processamento de autorização finalizado
"ORDER 0: no failed message" - verificando se há pedido com id 0 com falha (mais sobre falha no próximo método)
"ORDER 0: MESSAGE TO CAPTURE" - mensagem com ação de captura
"ORDER 0 CAPTURED" - captura feita e fim de fluxo para o pedido 0.
"ORDER 1: MESSAGE TO AUTHORIZE"
"ORDER 1: AUTHORIZED"
"ORDER 1: no failed message"
"ORDER 1: MESSAGE TO CAPTURE"
"ORDER 1 CAPTURED"
"ORDER 2: MESSAGE TO AUTHORIZE"
"ORDER 2: AUTHORIZED"
"ORDER 2: no failed message"
"ORDER 2: MESSAGE TO CAPTURE"
"ORDER 2 CAPTURED"
```

### Método 2: Tratando mensagens que falharam
Aqui mantemos o poder do paralelismo e definimos fluxos alternativos para mensagens que ainda não podem ser processadas.

Caso a mensagem de captura de um pedido chegue antes de sua mensagem de autorização, a reenviamos para a fila. Isso é feito marcando a mensagem como falha:

`Broadway.Message.failed(message, "orders-wait-auth")`

Caso a mensagem já tenha sido reenviada acima do limite estipulado, salvamos ela no mecanismo de persistência como mensagem que falhou. Assim que a mensagem de autorização chegar e a autorização for realizada, o mecanismo de persistência é consultado para pegar a mensagem de captura que falhou e, caso exista, a captura é então feita.

__Obs.:__ Podemos utilizar outras formas para considerar que uma mensagem falhou além da quantidade de retentativas, como por exemplo, o tempo em que ela está nesse ciclo de reenvios.

Execute a função de envio de mensagens:
- entre no terminal  
`iex -S mix`

- envie as mensagens
`send_message.(6)`

Ao enviarmos as mensagens teremos os seguintes logs:

```sh
"ORDER 0: MESSAGE TO CAPTURE"
"ORDER 2: MESSAGE TO CAPTURE"
"ORDER 1: MESSAGE TO CAPTURE"
"ORDER 0: capture retries: 0"
"ORDER 2: capture retries: 0"
"ORDER 1: capture retries: 0"
"ORDER 0: MESSAGE TO CAPTURE"
"ORDER 0: capture retries: 1"
"ORDER 0: MESSAGE TO CAPTURE"
"ORDER 0: capture retries: 2"
"ORDER 0: MESSAGE TO AUTHORIZE"
"ORDER 0: MESSAGE TO CAPTURE"
"ORDER 2: MESSAGE TO AUTHORIZE"
"ORDER 1: MESSAGE TO AUTHORIZE"
"ORDER 1: MESSAGE TO CAPTURE"
"ORDER 2: MESSAGE TO CAPTURE"
"ORDER 0: capture retries: 3"
"ORDER 1: capture retries: 1"
"ORDER 2: capture retries: 1"
"ORDER 0: Failed. Save in DB"
"ORDER 2: MESSAGE TO CAPTURE"
"ORDER 2: capture retries: 2"
"ORDER 2: AUTHORIZED"
"ORDER 1: AUTHORIZED"
"ORDER 0: AUTHORIZED"
"ORDER 2: no failed message"
"ORDER 1: no failed message"
"ORDER 0 CAPTURED"
"ORDER 2: MESSAGE TO CAPTURE"
"ORDER 2 CAPTURED"
"ORDER 1: MESSAGE TO CAPTURE"
"ORDER 1 CAPTURED"
```

Para melhor entendimento vamos agrupar os logs pelo id dos pedidos.  

__Pedidos 0__  
```sh
"ORDER 0: MESSAGE TO CAPTURE" - mensagem de captura (reenviada para a fila porque ainda não foi autorizado)
"ORDER 0: capture retries: 0" - 0 retentativas de captura
"ORDER 0: MESSAGE TO CAPTURE" - mensagem de captura (reenviada para a fila porque ainda não foi autorizado)
"ORDER 0: capture retries: 1" - 1 retentativa de captura
"ORDER 0: MESSAGE TO CAPTURE" - mensagem de captura (reenviada para a fila porque ainda não foi autorizado)
"ORDER 0: capture retries: 2" - 2 retentativas de captura
"ORDER 0: MESSAGE TO AUTHORIZE" - mensagem de autorização (o processo de autorização é demorado)
"ORDER 0: MESSAGE TO CAPTURE" - mensagem de captura (reenviada para a fila porque ainda não foi autorizado)
"ORDER 0: capture retries: 3" - 3 retentativas de captura (chegou ao limite)
"ORDER 0: Failed. Save in DB" - salvar mensagem como falha.
"ORDER 0: AUTHORIZED" - fim do processo de autorização (após isso é checado se há algum dado de falha do pedido 0)
"ORDER 0 CAPTURED" - dado é resgatado e captura é feita
```


__Pedido 1__  
```sh
"ORDER 1: MESSAGE TO CAPTURE" - mensagem de captura (reenviada para a fila porque ainda não foi autorizado)
"ORDER 1: capture retries: 0" - 0 retentativas de captura
"ORDER 1: MESSAGE TO AUTHORIZE" - mensagem de autorização
"ORDER 1: MESSAGE TO CAPTURE" - mensagem de captura (reenviada para a fila porque ainda não foi autorizado)
"ORDER 1: capture retries: 1" - 1 retentativa de captura
"ORDER 1: AUTHORIZED" - fim do processo de autorização (após isso é checado se há algum dado de falha do pedido 1)
"ORDER 1: no failed message" - não há dado de falha (tentativa de captura não excedeu o limite)
"ORDER 1: MESSAGE TO CAPTURE" - mensagem de captura (agora pode ser capturado, pois já está autorizado)
"ORDER 1 CAPTURED" - captura feita
```

Os demais logs dos outros pedidos seguem a mesma lógica. Desta forma as mensagens podem chegar fora de ordem que o processamento ocorre como deveria. Não abrimos mão do paralelismo e atingimos nosso objetivo.