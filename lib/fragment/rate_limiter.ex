defmodule Fragment.RateLimiter do
  @moduledoc """
  Lightweight ETS-based per-IP rate limiter with periodic cleanup.
  """

  use GenServer

  @table :fragment_rate_limiter
  @cleanup_interval_ms :timer.minutes(5)

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Checks and increments the rate limit counter for `bucket` and `key` (e.g. client IP).
  Returns:
  - `{:allow, %{limit: limit, remaining: remaining, reset_in: seconds}}`
  - `{:deny, %{limit: limit, remaining: 0, retry_after: seconds}}`
  """
  def check_rate(bucket, key, limit \\ nil, window_ms \\ nil) do
    config = Application.get_env(:fragment, __MODULE__, [])
    limit = limit || Keyword.get(config, :limit, 30)
    window_ms = window_ms || Keyword.get(config, :window_ms, 60_000)

    now_ms = System.system_time(:millisecond)
    window_id = div(now_ms, window_ms)
    reset_in = max(1, div((window_id + 1) * window_ms - now_ms + 999, 1000))
    ets_key = {bucket, key, window_id}

    count =
      :ets.update_counter(@table, ets_key, {2, 1}, {ets_key, 0, (window_id + 1) * window_ms})

    if count <= limit do
      {:allow, %{limit: limit, remaining: max(0, limit - count), reset_in: reset_in}}
    else
      {:deny, %{limit: limit, remaining: 0, retry_after: reset_in}}
    end
  end

  @doc """
  Clears all rate limit counters (useful in tests).
  """
  def reset do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  @impl true
  def init(_opts) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])
    end

    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now_ms = System.system_time(:millisecond)

    :ets.select_delete(@table, [
      {{:_, :_, :"$1"}, [{:<, :"$1", now_ms}], [true]}
    ])

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end
