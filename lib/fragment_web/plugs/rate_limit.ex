defmodule FragmentWeb.Plugs.RateLimit do
  @moduledoc """
  Plug for enforcing per-IP rate limits on paste creation and mutation endpoints.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Fragment.RateLimiter

  def init(opts), do: opts

  def call(conn, opts) do
    bucket = Keyword.get(opts, :bucket, :general)
    limit = Keyword.get(opts, :limit)
    window_ms = Keyword.get(opts, :window_ms)
    format = Keyword.get(opts, :format, :auto)
    ip = client_ip(conn)

    case RateLimiter.check_rate(bucket, ip, limit, window_ms) do
      {:allow, info} ->
        conn
        |> put_resp_header("x-ratelimit-limit", Integer.to_string(info.limit))
        |> put_resp_header("x-ratelimit-remaining", Integer.to_string(info.remaining))

      {:deny, info} ->
        conn
        |> put_resp_header("x-ratelimit-limit", Integer.to_string(info.limit))
        |> put_resp_header("x-ratelimit-remaining", "0")
        |> put_resp_header("retry-after", Integer.to_string(info.retry_after))
        |> send_rate_limited(format, info.retry_after)
        |> halt()
    end
  end

  def client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] ->
        forwarded
        |> String.split(",")
        |> List.first()
        |> String.trim()

      [] ->
        conn.remote_ip
        |> :inet.ntoa()
        |> to_string()
    end
  end

  defp send_rate_limited(conn, format, retry_after) do
    is_json? =
      format == :json or
        String.starts_with?(conn.request_path, "/api") or
        Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "application/json"))

    if is_json? do
      conn
      |> put_status(:too_many_requests)
      |> json(%{
        error: "Rate limit exceeded. Please try again in #{retry_after} seconds.",
        retry_after: retry_after
      })
    else
      conn
      |> put_status(:too_many_requests)
      |> put_resp_content_type("text/plain")
      |> send_resp(
        :too_many_requests,
        "Rate limit exceeded. Please wait #{retry_after} seconds before trying again."
      )
    end
  end
end
