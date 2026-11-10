defmodule Fragment.Pastes do
  @moduledoc """
  The Pastes context: handles creating, retrieving, updating, deleting,
  and expiring code fragments.
  """

  import Ecto.Query, warn: false

  alias Fragment.Pastes.Paste
  alias Fragment.Repo

  @max_id_retries 5

  @doc """
  Returns a form changeset for tracking paste changes in the UI.
  """
  def change_paste(%Paste{} = paste, attrs \\ %{}) do
    Paste.form_changeset(paste, attrs)
  end

  @doc """
  Creates a new paste.
  Returns `{:ok, %Paste{edit_token: token}}` or `{:error, %Ecto.Changeset{}}`.
  """
  def create_paste(attrs \\ %{}) do
    do_create_paste(attrs, @max_id_retries)
  end

  defp do_create_paste(attrs, retries_left) do
    changeset = Paste.create_changeset(%Paste{}, attrs)

    case Repo.insert(changeset) do
      {:ok, paste} ->
        {:ok, paste}

      {:error, %Ecto.Changeset{errors: errors} = cs} ->
        if Keyword.has_key?(errors, :id) and retries_left > 0 and not has_explicit_id?(attrs) do
          do_create_paste(attrs, retries_left - 1)
        else
          {:error, cs}
        end
    end
  end

  defp has_explicit_id?(attrs) when is_map(attrs) do
    Map.has_key?(attrs, :id) or Map.has_key?(attrs, "id")
  end

  @doc """
  Gets an active (non-expired) paste by ID.
  Returns `%Paste{}` or `nil` if not found or expired.
  If an expired paste is encountered in the database, it is purged immediately.
  """
  def get_paste(id) when is_binary(id) do
    case Repo.get(Paste, id) do
      nil ->
        nil

      %Paste{} = paste ->
        if Paste.expired?(paste) do
          _ = Repo.delete(paste)
          nil
        else
          paste
        end
    end
  end

  def get_paste(_), do: nil

  @doc """
  Gets an active (non-expired) paste by ID.
  Raises `Ecto.NoResultsError` if the paste does not exist or has expired.
  """
  def get_paste!(id) when is_binary(id) do
    case get_paste(id) do
      nil -> raise Ecto.NoResultsError, queryable: Paste
      %Paste{} = paste -> paste
    end
  end

  @doc """
  Updates a paste if the provided `edit_token` is valid.
  Returns:
  - `{:ok, %Paste{}}` on success
  - `{:error, :missing_token}` if token is nil or blank
  - `{:error, :invalid_token}` if token does not match `edit_token_hash`
  - `{:error, %Ecto.Changeset{}}` on validation failure
  """
  def update_paste(%Paste{} = paste, token, attrs) do
    cond do
      is_nil(token) or (is_binary(token) and String.trim(token) == "") ->
        {:error, :missing_token}

      not Paste.valid_edit_token?(paste, token) ->
        {:error, :invalid_token}

      true ->
        paste
        |> Paste.update_changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Deletes a paste if the provided `edit_token` is valid.
  Returns:
  - `{:ok, %Paste{}}` on success
  - `{:error, :missing_token}` if token is nil or blank
  - `{:error, :invalid_token}` if token does not match `edit_token_hash`
  """
  def delete_paste(%Paste{} = paste, token) do
    cond do
      is_nil(token) or (is_binary(token) and String.trim(token) == "") ->
        {:error, :missing_token}

      not Paste.valid_edit_token?(paste, token) ->
        {:error, :invalid_token}

      true ->
        Repo.delete(paste)
    end
  end

  @doc """
  Purges all expired pastes from the database.
  Returns the count of deleted pastes.
  """
  def purge_expired_pastes(now \\ DateTime.utc_now()) do
    {count, _} =
      from(p in Paste,
        where: not is_nil(p.expires_at) and p.expires_at <= ^now
      )
      |> Repo.delete_all()

    count
  end
end
