defmodule Fragment.Pastes.ExpirationWorker do
  @moduledoc """
  Periodic GenServer that purges expired pastes from SQLite.
  """

  use GenServer
  require Logger

  alias Fragment.Pastes

  @default_interval_ms :timer.seconds(60)

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Triggers an immediate synchronous purge via the worker process.
  """
  def purge_now(server \\ __MODULE__) do
    GenServer.call(server, :purge_now)
  end

  @impl true
  def init(opts) do
    config = Application.get_env(:fragment, __MODULE__, [])
    interval = Keyword.get(opts, :interval, Keyword.get(config, :interval, @default_interval_ms))
    enabled = Keyword.get(opts, :enabled, Keyword.get(config, :enabled, true))

    state = %{interval: interval, enabled: enabled}

    if enabled do
      schedule_next(interval)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:purge_now, _from, state) do
    count = safe_purge()
    {:reply, {:ok, count}, state}
  end

  @impl true
  def handle_info(:purge, state) do
    _ = safe_purge()

    if state.enabled do
      schedule_next(state.interval)
    end

    {:noreply, state}
  end

  defp schedule_next(interval) when is_integer(interval) and interval > 0 do
    Process.send_after(self(), :purge, interval)
  end

  defp safe_purge do
    try do
      count = Pastes.purge_expired_pastes()

      if count > 0 do
        Logger.info("Purged #{count} expired paste(s)")
      end

      count
    rescue
      error ->
        Logger.warning("Failed to purge expired pastes: #{Exception.message(error)}")
        0
    end
  end
end
