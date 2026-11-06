defmodule FragmentWeb.Api.PasteController do
  @moduledoc """
  JSON & raw API controller for creating, reading, updating, and deleting pastes.
  """

  use FragmentWeb, :controller

  alias Fragment.Pastes
  alias Fragment.Pastes.Paste

  @doc """
  POST /api/pastes
  Creates a new paste from JSON body (`content`, optional `language`, optional `expires_in`).
  """
  def create(conn, params) do
    paste_params = extract_paste_params(params)

    case Pastes.create_paste(paste_params) do
      {:ok, %Paste{} = paste} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", url(~p"/api/pastes/#{paste.id}"))
        |> json(serialize_paste(paste, include_token?: true))

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "Validation failed",
          errors: format_changeset_errors(changeset)
        })
    end
  end

  @doc """
  GET /api/pastes/:id
  Returns JSON representation of an active paste.
  """
  def show(conn, %{"id" => id}) do
    case Pastes.get_paste(id) do
      %Paste{} = paste ->
        json(conn, serialize_paste(paste, include_token?: false))

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Paste not found or has expired"})
    end
  end

  @doc """
  GET /api/pastes/:id/raw
  Returns raw text/plain representation of an active paste without HTML escaping.
  """
  def raw(conn, %{"id" => id}) do
    case Pastes.get_paste(id) do
      %Paste{} = paste ->
        conn
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_content_type("text/plain", "utf-8")
        |> send_resp(:ok, paste.content)

      nil ->
        conn
        |> put_resp_content_type("text/plain", "utf-8")
        |> send_resp(:not_found, "404 Not Found")
    end
  end

  @doc """
  PUT/PATCH /api/pastes/:id
  Updates an existing paste using its secret edit token.
  """
  def update(conn, %{"id" => id} = params) do
    case Pastes.get_paste(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Paste not found or has expired"})

      %Paste{} = paste ->
        token = extract_token(conn, params)
        paste_params = extract_paste_params(params)

        case Pastes.update_paste(paste, token, paste_params) do
          {:ok, updated_paste} ->
            json(conn, serialize_paste(updated_paste, include_token?: false))

          {:error, :missing_token} ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "Edit token is required"})

          {:error, :invalid_token} ->
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Invalid edit token"})

          {:error, %Ecto.Changeset{} = changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: "Validation failed",
              errors: format_changeset_errors(changeset)
            })
        end
    end
  end

  @doc """
  DELETE /api/pastes/:id
  Deletes a paste when provided with a valid edit/delete token.
  """
  def delete(conn, %{"id" => id} = params) do
    case Pastes.get_paste(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Paste not found or has expired"})

      %Paste{} = paste ->
        token = extract_token(conn, params)

        case Pastes.delete_paste(paste, token) do
          {:ok, _deleted} ->
            json(conn, %{deleted: true, id: paste.id})

          {:error, :missing_token} ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "Edit token is required"})

          {:error, :invalid_token} ->
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Invalid edit token"})
        end
    end
  end

  defp extract_paste_params(%{"paste" => paste_params}) when is_map(paste_params),
    do: paste_params

  defp extract_paste_params(params) when is_map(params),
    do: Map.drop(params, ["id", "token", "edit_token", "delete_token"])

  defp extract_token(conn, params) do
    bearer_token(conn) ||
      List.first(get_req_header(conn, "x-edit-token")) ||
      List.first(get_req_header(conn, "x-delete-token")) ||
      params["edit_token"] ||
      params["delete_token"] ||
      params["token"] ||
      get_in(params, ["paste", "edit_token"]) ||
      get_in(params, ["paste", "delete_token"]) ||
      get_in(params, ["paste", "token"])
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> String.trim(token)
      ["bearer " <> token | _] -> String.trim(token)
      [token | _] when token != "" -> String.trim(token)
      _ -> nil
    end
  end

  defp serialize_paste(%Paste{} = paste, opts) do
    include_token? = Keyword.get(opts, :include_token?, false)

    base = %{
      id: paste.id,
      content: paste.content,
      language: paste.language,
      size_bytes: paste.size_bytes,
      expires_at: paste.expires_at,
      inserted_at: paste.inserted_at,
      updated_at: paste.updated_at,
      url: url(~p"/#{paste.id}"),
      raw_url: url(~p"/raw/#{paste.id}"),
      api_url: url(~p"/api/pastes/#{paste.id}")
    }

    if include_token? and is_binary(paste.edit_token) do
      Map.merge(base, %{
        edit_token: paste.edit_token,
        delete_token: paste.edit_token
      })
    else
      base
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
