defmodule Orders do

  def increment_retry(order) do
    :ets.lookup(:order_lookup, "#{order.id}_retries")
    |> case do
      [] -> :ets.insert(:order_lookup, {"#{order.id}_retries", 1})
      [{_, retries}] -> :ets.insert(:order_lookup, {"#{order.id}_retries", retries + 1})
    end
  end

  def get_retry(order) do
    :ets.lookup(:order_lookup, "#{order.id}_retries")
    |> case do
      [] -> 0
      [{_, retries}] -> retries
    end
  end

  def authorize(order) do
    # Slow action.
    Process.sleep(10000)
    :ets.insert(:order_lookup, {order.id, "authorized"})
  end

  def capture(order) do
    # Fast action.
    remove_ets_info(order)
  end

  def can_capture?(order) do
    :ets.lookup(:order_lookup, order.id)
    |> case do
      [{id, "authorized"}] -> true
      _ -> false

    end
  end

  def save_failed_message(order) do
    IO.inspect("ORDER #{order.id}: Failed. Save in DB")
    :ets.insert(:order_lookup, {"#{order.id}_failed", order})
  end

  def get_failed_message(order) do
    :ets.lookup(:order_lookup, "#{order.id}_failed")
    |> case do
      [{id, order_failed}] -> order_failed
      _ -> nil

    end
  end

  def remove_ets_info(order) do
    :ets.delete(:order_lookup, order.id)
    :ets.delete(:order_lookup, "#{order.id}_retries")
    :ets.delete(:order_lookup, "#{order.id}_failed")
  end
end
