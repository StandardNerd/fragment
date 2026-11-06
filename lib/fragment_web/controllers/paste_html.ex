defmodule FragmentWeb.PasteHTML do
  @moduledoc """
  Templates and helpers for rendering paste pages.
  """
  use FragmentWeb, :html

  embed_templates "paste_html/*"

  @doc """
  Formats a UTC DateTime into a concise human-readable string.
  """
  def format_datetime(nil), do: "Never"

  def format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end

  @doc """
  Returns a human-readable expiration badge label.
  """
  def format_expiration(nil), do: "Never expires"

  def format_expiration(%DateTime{} = expires_at) do
    diff_sec = DateTime.diff(expires_at, DateTime.utc_now(), :second)

    cond do
      diff_sec <= 0 ->
        "Expired"

      diff_sec < 60 ->
        "Expires in #{diff_sec}s"

      diff_sec < 3_600 ->
        "Expires in #{div(diff_sec, 60)}m"

      diff_sec < 86_400 ->
        hours = div(diff_sec, 3_600)
        mins = div(rem(diff_sec, 3_600), 60)
        if mins > 0, do: "Expires in #{hours}h #{mins}m", else: "Expires in #{hours}h"

      true ->
        days = div(diff_sec, 86_400)
        hours = div(rem(diff_sec, 86_400), 3_600)
        if hours > 0, do: "Expires in #{days}d #{hours}h", else: "Expires in #{days}d"
    end
  end

  @doc """
  Extracts human-readable error messages for a field on an Ecto.Changeset.
  """
  def field_errors(%Ecto.Changeset{action: nil}, _field), do: []

  def field_errors(%Ecto.Changeset{errors: errors}, field) do
    for {^field, {msg, opts}} <- errors do
      translate_error({msg, opts})
    end
  end

  @doc """
  Returns a `1..count` range of line numbers for initial textarea content.
  """
  def line_numbers_for(nil), do: 1..1
  def line_numbers_for(""), do: 1..1

  def line_numbers_for(content) when is_binary(content) do
    count =
      content
      |> String.split(~r/\r?\n/)
      |> length()
      |> max(1)

    1..count
  end
end
