defmodule FragmentWeb.PasteControllerTest do
  use FragmentWeb.ConnCase, async: false

  import Fragment.PastesFixtures

  alias Fragment.Pastes.Paste

  describe "GET / (new paste page)" do
    test "renders new fragment form with dark mode default, line numbers gutter, and API footer link",
         %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      assert html =~ ~s(data-theme="dark")
      assert html =~ "New fragment"
      assert html =~ ~s(id="code-line-numbers")
      assert html =~ ~s(data-line="1")
      assert html =~ "API Docs"
    end

    test "pre-loads paste content and matching line numbers when cloning via ?clone=:id", %{
      conn: conn
    } do
      source =
        paste_fixture(%{
          content: "defmodule Cloned do\n  IO.puts(:cloned_snippet)\nend",
          language: "elixir"
        })

      conn = get(conn, ~p"/?clone=#{source.id}")
      html = html_response(conn, 200)
      assert html =~ "Clone fragment"
      assert html =~ "##{source.id}"
      assert html =~ "IO.puts(:cloned_snippet)"
      assert html =~ ~s(data-line="1")
      assert html =~ ~s(data-line="2")
      assert html =~ ~s(data-line="3")
    end
  end

  describe "POST /pastes (create paste)" do
    test "creates paste, redirects to show page, and displays one-time edit token once", %{
      conn: conn
    } do
      conn =
        post(conn, ~p"/pastes", %{
          "paste" => %{
            "content" => "defmodule MyPaste do\n  def x, do: 42\nend",
            "language" => "auto",
            "expires_in" => "1d"
          }
        })

      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == ~p"/#{id}"

      # First visit to the paste shows the one-time secret token banner
      conn1 = get(recycle(conn), ~p"/#{id}")
      html1 = html_response(conn1, 200)
      assert html1 =~ "Save your claim / edit secret"
      assert html1 =~ "frag_"
      assert html1 =~ "Elixir"

      # Subsequent visit does NOT show the one-time token banner again
      conn2 = get(recycle(conn1), ~p"/#{id}")
      html2 = html_response(conn2, 200)
      refute html2 =~ "Save your claim / edit secret"
    end

    test "returns 422 with clear error message for blank or oversized content", %{conn: conn} do
      conn1 = post(conn, ~p"/pastes", %{"paste" => %{"content" => ""}})
      assert html_response(conn1, 422) =~ "can&#39;t be blank"

      too_big = String.duplicate("x", Paste.max_paste_bytes() + 10)
      conn2 = post(conn, ~p"/pastes", %{"paste" => %{"content" => too_big}})
      assert html_response(conn2, 422) =~ "maximum allowed size is 512 KB"
    end
  end

  describe "GET /:id and GET /raw/:id" do
    test "renders syntax-highlighted paste and safely escapes HTML", %{conn: conn} do
      paste =
        paste_fixture(%{
          content: "const msg = \"<script>alert('xss')</script>\";",
          language: "javascript"
        })

      conn = get(conn, ~p"/#{paste.id}")
      html = html_response(conn, 200)
      assert html =~ "##{paste.id}"
      assert html =~ "JavaScript"
      assert html =~ "hl-keyword"
      refute html =~ "<script>alert('xss')</script>"
      assert html =~ "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;"
    end

    test "GET /raw/:id serves unescaped plain text with text/plain content-type", %{conn: conn} do
      raw_text = "const a = 1 < 2 && 3 > 1;\n<script>alert(\"raw\")</script>"
      paste = paste_fixture(%{content: raw_text, language: "javascript"})

      conn = get(conn, ~p"/raw/#{paste.id}")
      assert response(conn, 200) == raw_text
      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    end

    test "returns 404 for expired or non-existent paste on show and raw routes", %{conn: conn} do
      expired = expired_paste_fixture()

      conn1 = get(conn, ~p"/#{expired.id}")
      assert html_response(conn1, 404) =~ "Not Found"

      conn2 = get(conn, ~p"/raw/#{expired.id}")
      assert response(conn2, 404) == "404 Not Found"

      conn3 = get(conn, ~p"/nonexistent99")
      assert html_response(conn3, 404) =~ "Not Found"
    end
  end

  describe "PUT /pastes/:id and DELETE /pastes/:id (edit/delete with token)" do
    test "updates and deletes paste with valid edit token, rejects invalid token", %{conn: conn} do
      paste = paste_fixture(%{content: "original text", language: "plaintext"})

      # Reject invalid token on update
      bad_update =
        put(conn, ~p"/pastes/#{paste.id}", %{
          "edit_token" => "frag_invalid",
          "paste" => %{"content" => "tampered", "language" => "plaintext"}
        })

      assert html_response(bad_update, 403) =~ "Invalid or missing edit token"

      # Accept valid token on update
      good_update =
        put(conn, ~p"/pastes/#{paste.id}", %{
          "edit_token" => paste.edit_token,
          "paste" => %{"content" => "updated via token", "language" => "markdown"}
        })

      assert redirected_to(good_update) == ~p"/#{paste.id}"

      raw_conn = get(conn, ~p"/raw/#{paste.id}")
      assert response(raw_conn, 200) == "updated via token"

      # Reject invalid token on delete
      bad_delete = delete(conn, ~p"/pastes/#{paste.id}", %{"edit_token" => "frag_wrong"})
      assert html_response(bad_delete, 403) =~ "Invalid or missing edit token"

      # Accept valid token on delete
      good_delete = delete(conn, ~p"/pastes/#{paste.id}", %{"edit_token" => paste.edit_token})
      assert redirected_to(good_delete) == ~p"/"

      missing_conn = get(conn, ~p"/#{paste.id}")
      assert html_response(missing_conn, 404) =~ "Not Found"
    end
  end

  describe "GET /api (API documentation page)" do
    test "renders API docs page", %{conn: conn} do
      conn = get(conn, ~p"/api")
      html = html_response(conn, 200)
      assert html =~ "API Documentation"
      assert html =~ "POST"
      assert html =~ "/api/pastes"
      assert html =~ "DELETE"
    end
  end
end
