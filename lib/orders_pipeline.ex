defmodule OrdersPipeline do
  use Broadway

  @producer BroadwayRabbitMQ.Producer

  @producer_config [
    queue: "orders_queue",
    declare: [
      durable: true
    ], # Mantém a fila quando há reinicialização do broker.
    on_failure: :reject_and_requeue # Envia as mensagens com falha novamente para a fila.
  ]

  def start_link(_args) do
    options = [
      name: OrdersPipeline,
      producer: [
        module: {@producer, @producer_config}
      ],
      processors: [
        default: []
      ]
    ]

    Broadway.start_link(__MODULE__, options)
  end

  def prepare_messages(messages, _context) do
    # Parse data and convert to a map.
    messages =
      Enum.map(messages, fn message ->
        Broadway.Message.update_data(message, fn data ->
          [order_id, message_number, action] = String.split(data, ",")
          %{
            id: order_id,
            message_number: message_number,
            action: action
          }
        end)
      end)

    messages
  end

  def handle_message(_processor, message, _context) do

    order = message.data
    if (order.action == "auth") do
      IO.inspect("ORDER #{order.id}: MESSAGE TO AUTHORIZE")
    else
      IO.inspect("ORDER #{order.id}: MESSAGE TO CAPTURE")
    end

    cond do
      (order.action == "auth") ->
        authorize_order(order)
        check_and_capture_order(order)
        message

      Orders.can_capture?(order) ->
        capture_order(order)
        message

      true ->
        retries = Orders.get_retry(order)
        IO.inspect("ORDER #{order.id}: capture retries: #{retries}")

        if (retries >= 3) do
          Orders.save_failed_message(order)
          Broadway.Message.failed(message, "orders-failed")
        else
          Broadway.Message.failed(message, "orders-wait-auth")
        end
    end
  end

  def handle_failed(messages, _context) do
    Process.sleep(50)

    Enum.map(messages, fn
      %{status: {:failed, "orders-wait-auth"}} = message ->
        Orders.increment_retry(message.data)
        message

      %{status: {:failed, "orders-failed"}} = message ->
        Broadway.Message.configure_ack(message, on_failure: :reject)
    end)
  end

  defp authorize_order(order) do
    Orders.authorize(order)
    IO.inspect("ORDER #{order.id}: AUTHORIZED")
  end

  defp check_and_capture_order(order) do
    Orders.get_failed_message(order)
    |> case do
      nil -> IO.inspect("ORDER #{order.id}: no failed message")
      order -> capture_order(order)
    end
  end

  defp capture_order(order) do
    Orders.capture(order)
    IO.inspect("ORDER #{order.id} CAPTURED")
  end
end
