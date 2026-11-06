defmodule FragmentWeb.PasteController do
  @moduledoc """
  Browser controller for creating, viewing, cloning, raw-viewing, editing,
  and deleting pastes, plus the API documentation page.
  """

  use FragmentWeb, :controller

  alias Fragment.Pastes
  alias Fragment.Pastes.Paste
  alias Fragment.Syntax.{Highlighter, Languages}

  def new(conn, params) do
    {initial_paste, cloned_from} = resolve_clone_source(params["clone"])
    changeset = Pastes.change_paste(initial_paste)

    conn =
      if params["clone"] && is_nil(cloned_from) do
        put_flash(conn, :error, "Source fragment to clone was not found or has expired.")
      else
        conn
      end

    render(conn, :new,
      page_title: if(cloned_from, do: "Clone ##{cloned_from.id}", else: "New paste"),
      changeset: changeset,
      cloned_from: cloned_from,
      language_options: Languages.select_options(),
      expiration_options: Paste.expiration_options(),
      max_paste_bytes: Paste.max_paste_bytes()
    )
  end

  def create(conn, params) do
    paste_params = Map.get(params, "paste", params)

    case Pastes.create_paste(paste_params) do
      {:ok, %Paste{} = paste} ->
        created_tokens = Map.get(get_session(conn), "created_tokens", %{})
        updated_tokens = Map.put(created_tokens, paste.id, paste.edit_token)

        conn
        |> put_session("created_tokens", updated_tokens)
        |> redirect(to: ~p"/#{paste.id}")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:new,
          page_title: "New paste",
          changeset: %{changeset | action: :insert},
          cloned_from: nil,
          language_options: Languages.select_options(),
          expiration_options: Paste.expiration_options(),
          max_paste_bytes: Paste.max_paste_bytes()
        )
    end
  end

  def show(conn, %{"id" => id}) do
    case Pastes.get_paste(id) do
      nil ->
        render_not_found(conn)

      %Paste{} = paste ->
        {one_time_token, conn} = pop_created_token(conn, paste.id)
        highlighted_lines = Highlighter.highlight_lines(paste.content, paste.language)

        render(conn, :show,
          page_title: "##{paste.id} · #{Languages.label(paste.language)}",
          paste: paste,
          language_label: Languages.label(paste.language),
          highlighted_lines: highlighted_lines,
          line_count: length(highlighted_lines),
          formatted_size: Paste.format_bytes(paste.size_bytes),
          one_time_edit_token: one_time_token
        )
    end
  end

  def raw(conn, %{"id" => id}) do
    case Pastes.get_paste(id) do
      nil ->
        conn
        |> put_resp_content_type("text/plain", "utf-8")
        |> send_resp(:not_found, "404 Not Found")

      %Paste{} = paste ->
        conn
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_content_type("text/plain", "utf-8")
        |> send_resp(:ok, paste.content)
    end
  end

  def edit(conn, %{"id" => id} = params) do
    case Pastes.get_paste(id) do
      nil ->
        render_not_found(conn)

      %Paste{} = paste ->
        changeset = Pastes.change_paste(paste)
        prefilled_token = params["token"] || ""

        render(conn, :edit,
          page_title: "Edit ##{paste.id}",
          paste: paste,
          changeset: changeset,
          edit_token: prefilled_token,
          language_options: Languages.concrete_select_options(),
          expiration_options: [{"Keep current expiration", ""}] ++ Paste.expiration_options(),
          max_paste_bytes: Paste.max_paste_bytes()
        )
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Pastes.get_paste(id) do
      nil ->
        render_not_found(conn)

      %Paste{} = paste ->
        paste_params = Map.get(params, "paste", %{})
        token = params["edit_token"] || paste_params["edit_token"] || ""

        clean_params =
          case Map.get(paste_params, "expires_in") do
            "" -> Map.delete(paste_params, "expires_in")
            nil -> Map.delete(paste_params, "expires_in")
            _ -> paste_params
          end

        case Pastes.update_paste(paste, token, clean_params) do
          {:ok, updated_paste} ->
            conn
            |> put_flash(:info, "Fragment updated.")
            |> redirect(to: ~p"/#{updated_paste.id}")

          {:error, reason} when reason in [:missing_token, :invalid_token] ->
            changeset = Pastes.change_paste(paste, clean_params)

            conn
            |> put_status(:forbidden)
            |> put_flash(:error, "Invalid or missing edit token.")
            |> render(:edit,
              page_title: "Edit ##{paste.id}",
              paste: paste,
              changeset: changeset,
              edit_token: token,
              language_options: Languages.concrete_select_options(),
              expiration_options: [{"Keep current expiration", ""}] ++ Paste.expiration_options(),
              max_paste_bytes: Paste.max_paste_bytes()
            )

          {:error, %Ecto.Changeset{} = changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> render(:edit,
              page_title: "Edit ##{paste.id}",
              paste: paste,
              changeset: %{changeset | action: :update},
              edit_token: token,
              language_options: Languages.concrete_select_options(),
              expiration_options: [{"Keep current expiration", ""}] ++ Paste.expiration_options(),
              max_paste_bytes: Paste.max_paste_bytes()
            )
        end
    end
  end

  def delete(conn, %{"id" => id} = params) do
    case Pastes.get_paste(id) do
      nil ->
        render_not_found(conn)

      %Paste{} = paste ->
        token =
          params["edit_token"] ||
            get_in(params, ["paste", "edit_token"]) ||
            params["token"] ||
            ""

        case Pastes.delete_paste(paste, token) do
          {:ok, _deleted} ->
            conn
            |> put_flash(:info, "Fragment ##{paste.id} has been deleted.")
            |> redirect(to: ~p"/")

          {:error, _reason} ->
            conn
            |> put_status(:forbidden)
            |> put_flash(:error, "Invalid or missing edit token. Fragment was not deleted.")
            |> render(:edit,
              page_title: "Edit ##{paste.id}",
              paste: paste,
              changeset: Pastes.change_paste(paste),
              edit_token: token,
              language_options: Languages.concrete_select_options(),
              expiration_options: [{"Keep current expiration", ""}] ++ Paste.expiration_options(),
              max_paste_bytes: Paste.max_paste_bytes()
            )
        end
    end
  end

  def api_docs(conn, _params) do
    render(conn, :api_docs,
      page_title: "API Documentation",
      base_url: FragmentWeb.Endpoint.url(),
      languages: Languages.canonical_ids(),
      max_paste_bytes: Paste.max_paste_bytes()
    )
  end

  defp resolve_clone_source(nil), do: {%Paste{language: "auto", expires_in: "never"}, nil}
  defp resolve_clone_source(""), do: {%Paste{language: "auto", expires_in: "never"}, nil}

  defp resolve_clone_source(clone_id) when is_binary(clone_id) do
    case Pastes.get_paste(String.trim(clone_id)) do
      %Paste{} = source ->
        {%Paste{
           content: source.content,
           language: source.language,
           expires_in: "never"
         }, source}

      nil ->
        {%Paste{language: "auto", expires_in: "never"}, nil}
    end
  end

  defp pop_created_token(conn, paste_id) do
    created_tokens = Map.get(get_session(conn), "created_tokens", %{})

    case Map.pop(created_tokens, paste_id) do
      {nil, _} ->
        {nil, conn}

      {token, remaining} ->
        {token, put_session(conn, "created_tokens", remaining)}
    end
  end

  defp render_not_found(conn) do
    conn
    |> put_status(:not_found)
    |> render(:not_found, page_title: "404 Not Found")
  end
end
