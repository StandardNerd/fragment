defmodule Fragment.PastesTest do
  use Fragment.DataCase, async: false

  import Fragment.PastesFixtures

  alias Fragment.Pastes
  alias Fragment.Pastes.{ExpirationWorker, Paste}
  alias Fragment.Syntax.{Detector, Highlighter}

  describe "create_paste/1" do
    test "creates a paste with valid attributes and returns one-time edit_token" do
      attrs = %{
        content: "defmodule Hello do\n  def world, do: :ok\nend",
        language: "auto",
        expires_in: "1h"
      }

      assert {:ok, %Paste{} = paste} = Pastes.create_paste(attrs)
      assert is_binary(paste.id)
      assert String.length(paste.id) == 8
      assert paste.language == "elixir"
      assert paste.size_bytes == byte_size(attrs.content)
      assert %DateTime{} = paste.expires_at
      assert DateTime.diff(paste.expires_at, DateTime.utc_now(), :second) in 3590..3605
      assert is_binary(paste.edit_token)
      assert String.starts_with?(paste.edit_token, "frag_")
      assert is_binary(paste.edit_token_hash)
      assert paste.edit_token_hash != paste.edit_token
      assert Paste.valid_edit_token?(paste, paste.edit_token)
      refute Paste.valid_edit_token?(paste, "wrong_token")
    end

    test "supports all expiration intervals" do
      for {expires_in, min_sec, max_sec} <- [
            {"10m", 590, 605},
            {"1h", 3590, 3605},
            {"1d", 86390, 86405},
            {"7d", 604_790, 604_805},
            {"30d", 2_591_990, 2_592_005}
          ] do
        {:ok, paste} = Pastes.create_paste(%{content: "test", expires_in: expires_in})
        diff = DateTime.diff(paste.expires_at, DateTime.utc_now(), :second)
        assert diff >= min_sec and diff <= max_sec
      end

      {:ok, never_paste} = Pastes.create_paste(%{content: "forever", expires_in: "never"})
      assert is_nil(never_paste.expires_at)
    end

    test "rejects blank or missing content" do
      assert {:error, changeset} = Pastes.create_paste(%{content: ""})
      assert "can't be blank" in errors_on(changeset).content

      assert {:error, changeset} = Pastes.create_paste(%{content: "   \n\t  "})
      assert "can't be blank" in errors_on(changeset).content
    end

    test "enforces 512 KB maximum paste size" do
      max_content = String.duplicate("a", Paste.max_paste_bytes())
      assert {:ok, _paste} = Pastes.create_paste(%{content: max_content})

      oversized_content = String.duplicate("a", Paste.max_paste_bytes() + 1)
      assert {:error, changeset} = Pastes.create_paste(%{content: oversized_content})
      assert [err] = errors_on(changeset).content
      assert err =~ "maximum allowed size is 512 KB"
    end

    test "rejects unsupported language or invalid expiration" do
      assert {:error, cs1} = Pastes.create_paste(%{content: "hi", language: "brainfuck"})
      assert "is not a supported language" in errors_on(cs1).language

      assert {:error, cs2} = Pastes.create_paste(%{content: "hi", expires_in: "999y"})
      assert [err] = errors_on(cs2).expires_in
      assert err =~ "supported values are never, 10m, 1h, 1d, 7d, 30d"
    end
  end

  describe "expiration and purging" do
    test "expired pastes return nil from get_paste/1 and raise on get_paste!/1" do
      expired = expired_paste_fixture()
      assert is_nil(Pastes.get_paste(expired.id))

      expired2 = expired_paste_fixture()
      assert_raise Ecto.NoResultsError, fn -> Pastes.get_paste!(expired2.id) end
    end

    test "purge_expired_pastes/0 and ExpirationWorker remove only expired pastes" do
      Ecto.Adapters.SQL.Sandbox.allow(Fragment.Repo, self(), ExpirationWorker)

      active = paste_fixture(%{content: "still active", expires_in: "1h"})
      expired1 = expired_paste_fixture()
      expired2 = expired_paste_fixture()

      assert {:ok, 2} = ExpirationWorker.purge_now()
      assert is_nil(Pastes.get_paste(expired1.id))
      assert is_nil(Pastes.get_paste(expired2.id))
      assert %Paste{id: id} = Pastes.get_paste(active.id)
      assert id == active.id
    end
  end

  describe "update_paste/3 and delete_paste/2 with edit token" do
    test "allows updating and deleting only with the valid edit token" do
      paste = paste_fixture(%{content: "initial", language: "plaintext"})
      token = paste.edit_token

      assert {:error, :missing_token} = Pastes.update_paste(paste, "", %{content: "hacked"})

      assert {:error, :invalid_token} =
               Pastes.update_paste(paste, "frag_wrong", %{content: "hacked"})

      assert {:ok, updated} =
               Pastes.update_paste(paste, token, %{content: "updated content", language: "elixir"})

      assert updated.content == "updated content"
      assert updated.language == "elixir"

      assert {:error, :invalid_token} = Pastes.delete_paste(updated, "frag_wrong")
      assert {:ok, _} = Pastes.delete_paste(updated, token)
      assert is_nil(Pastes.get_paste(paste.id))
    end
  end

  describe "language detection and syntax highlighting" do
    test "auto-detects common languages accurately" do
      assert Detector.detect(~s({"name": "fragment", "version": 1})) == "json"
      assert Detector.detect("defmodule Foo do\n  def bar(x), do: x |> baz()\nend") == "elixir"

      assert Detector.detect("def compute(x):\n    if __name__ == '__main__':\n        print(x)") ==
               "python"

      assert Detector.detect("package main\n\nfunc main() {\n\tfmt.Println(\"hi\")\n}") == "go"

      assert Detector.detect("fn main() {\n    let mut x = 5;\n    println!(\"{}\", x);\n}") ==
               "rust"

      assert Detector.detect("SELECT id, content FROM pastes WHERE expires_at IS NULL;") == "sql"

      assert Detector.detect("<!DOCTYPE html>\n<html><body><div>Hello</div></body></html>") ==
               "html"

      assert Detector.detect("#!/bin/bash\nset -euo pipefail\necho \"done\"") == "bash"
      assert Detector.detect("just some ordinary notes without code") == "plaintext"
    end

    test "syntax highlighter safely escapes HTML entities to prevent XSS" do
      malicious = "<script>alert(\"xss & 'injection'\")</script>"

      for lang <- ["javascript", "html", "elixir", "plaintext", "json", "markdown"] do
        {:safe, html} = Highlighter.highlight(malicious, lang)
        refute html =~ "<script>"
        refute html =~ "</script>"
        assert html =~ "&lt;script&gt;" or html =~ "&lt;/script" or html =~ "script"
      end
    end
  end
end
