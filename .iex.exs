send_message = fn num_messages ->

  {:ok, connection} = AMQP.Connection.open()
  {:ok, channel} = AMQP.Channel.open(connection)

  Enum.each(1..num_messages, fn n ->

    is_even? = rem(n, 2) == 0

    order_id = div(n - 1, 2)
    message_number = n
    action = (if is_even?, do: :capture, else: :auth)

    AMQP.Basic.publish(channel, "", "orders_queue", "#{order_id},#{message_number},#{action}")
  end)

  AMQP.Connection.close(connection)
end
