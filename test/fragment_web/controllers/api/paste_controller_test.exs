defmodule FragmentWeb.Api.PasteControllerTest do
  use FragmentWeb.ConnCase, async: false

  import Fragment.PastesFixtures

  alias Fragment.RateLimiter

  setup do
    RateLimiter.reset()
    :ok
  end

  describe "POST /api/pastes" do
    test "creates paste and returns url, raw_url, edit_token, and delete_token", %{conn: conn} do
      conn =
        post(conn, ~p"/api/pastes", %{
          content: "package main\n\nfunc main() {\n\tfmt.Println(\"hello\")\n}",
          language: "auto",
          expires_in: "10m"
        })

      body = json_response(conn, 201)
      assert is_binary(body["id"])
      assert body["language"] == "go"
      assert body["content"] =~ "package main"
      assert body["url"] =~ "/#{body["id"]}"
      assert body["raw_url"] =~ "/raw/#{body["id"]}"
      assert is_binary(body["edit_token"])
      assert body["delete_token"] == body["edit_token"]
      assert is_binary(body["expires_at"])
    end

    test "returns 422 with validation errors when content is invalid", %{conn: conn} do
      conn = post(conn, ~p"/api/pastes", %{content: "", expires_in: "invalid"})
      body = json_response(conn, 422)
      assert body["error"] == "Validation failed"
      assert "can't be blank" in body["errors"]["content"]
      assert is_list(body["errors"]["expires_in"])
    end
  end

  describe "GET /api/pastes/:id and GET /api/pastes/:id/raw" do
    test "returns paste metadata without exposing edit token", %{conn: conn} do
      paste = paste_fixture(%{content: "SELECT * FROM pastes;", language: "sql"})

      conn = get(conn, ~p"/api/pastes/#{paste.id}")
      body = json_response(conn, 200)
      assert body["id"] == paste.id
      assert body["content"] == "SELECT * FROM pastes;"
      assert body["language"] == "sql"
      assert body["url"] =~ "/#{paste.id}"
      assert body["raw_url"] =~ "/raw/#{paste.id}"
      refute Map.has_key?(body, "edit_token")
      refute Map.has_key?(body, "delete_token")
      refute Map.has_key?(body, "edit_token_hash")
    end

    test "GET /api/pastes/:id/raw returns unescaped plain text", %{conn: conn} do
      raw_code = "if (a < b && c > d) { return \"<ok>\"; }"
      paste = paste_fixture(%{content: raw_code, language: "javascript"})

      conn = get(conn, ~p"/api/pastes/#{paste.id}/raw")
      assert response(conn, 200) == raw_code
      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    end

    test "returns 404 when paste is expired or missing", %{conn: conn} do
      expired = expired_paste_fixture()

      conn1 = get(conn, ~p"/api/pastes/#{expired.id}")
      assert json_response(conn1, 404)["error"] =~ "not found"

      conn2 = get(conn, ~p"/api/pastes/#{expired.id}/raw")
      assert response(conn2, 404) == "404 Not Found"
    end
  end

  describe "PUT /api/pastes/:id and DELETE /api/pastes/:id" do
    test "updates and deletes paste via Authorization Bearer header or body token", %{conn: conn} do
      paste = paste_fixture(%{content: "v1", language: "plaintext"})

      # Missing token -> 401
      conn_no_token = delete(conn, ~p"/api/pastes/#{paste.id}")
      assert json_response(conn_no_token, 401)["error"] =~ "required"

      # Wrong token -> 403
      conn_bad_token =
        conn
        |> put_req_header("authorization", "Bearer wrong_token")
        |> delete(~p"/api/pastes/#{paste.id}")

      assert json_response(conn_bad_token, 403)["error"] =~ "Invalid"

      # Update with valid Bearer token -> 200
      conn_update =
        conn
        |> put_req_header("authorization", "Bearer #{paste.edit_token}")
        |> put(~p"/api/pastes/#{paste.id}", %{content: "v2 updated", language: "python"})

      updated_body = json_response(conn_update, 200)
      assert updated_body["content"] == "v2 updated"
      assert updated_body["language"] == "python"

      # Delete with valid token in body -> 200
      conn_delete =
        delete(conn, ~p"/api/pastes/#{paste.id}", %{edit_token: paste.edit_token})

      del_body = json_response(conn_delete, 200)
      assert del_body == %{"deleted" => true, "id" => paste.id}

      # Verify deleted -> 404
      assert json_response(get(conn, ~p"/api/pastes/#{paste.id}"), 404)
    end
  end

  describe "rate limiting" do
    test "enforces per-IP rate limits and sets rate limit headers", %{conn: conn} do
      prev_config = Application.get_env(:fragment, Fragment.RateLimiter, [])
      Application.put_env(:fragment, Fragment.RateLimiter, limit: 2, window_ms: 60_000)

      on_exit(fn ->
        Application.put_env(:fragment, Fragment.RateLimiter, prev_config)
        RateLimiter.reset()
      end)

      conn1 = post(conn, ~p"/api/pastes", %{content: "one"})
      assert json_response(conn1, 201)
      assert get_resp_header(conn1, "x-ratelimit-remaining") == ["1"]

      conn2 = post(conn, ~p"/api/pastes", %{content: "two"})
      assert json_response(conn2, 201)
      assert get_resp_header(conn2, "x-ratelimit-remaining") == ["0"]

      conn3 = post(conn, ~p"/api/pastes", %{content: "three"})
      body = json_response(conn3, 429)
      assert body["error"] =~ "Rate limit exceeded"
      assert get_resp_header(conn3, "retry-after") != []
    end
  end
end
