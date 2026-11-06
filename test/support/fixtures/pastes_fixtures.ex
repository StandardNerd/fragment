defmodule Fragment.PastesFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Fragment.Pastes` context.
  """

  alias Fragment.Pastes

  def paste_fixture(attrs \\ %{}) do
    {:ok, paste} =
      attrs
      |> Enum.into(%{
        content: "defmodule Sample do\n  def run, do: :ok\nend",
        language: "elixir",
        expires_in: "never"
      })
      |> Pastes.create_paste()

    paste
  end

  def expired_paste_fixture(attrs \\ %{}) do
    past_time =
      DateTime.utc_now()
      |> DateTime.add(-300, :second)
      |> DateTime.truncate(:second)

    {:ok, paste} =
      attrs
      |> Enum.into(%{
        content: "expired content",
        language: "plaintext",
        expires_at: past_time
      })
      |> Pastes.create_paste()

    paste
  end
end
