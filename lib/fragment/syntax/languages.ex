defmodule Fragment.Syntax.Languages do
  @moduledoc """
  Supported programming languages, display labels, and alias normalization.
  """

  @languages [
    {"auto", "Auto-detect"},
    {"elixir", "Elixir"},
    {"javascript", "JavaScript"},
    {"typescript", "TypeScript"},
    {"python", "Python"},
    {"go", "Go"},
    {"rust", "Rust"},
    {"html", "HTML"},
    {"css", "CSS"},
    {"json", "JSON"},
    {"sql", "SQL"},
    {"markdown", "Markdown"},
    {"bash", "Bash / Shell"},
    {"ruby", "Ruby"},
    {"c", "C / C++"},
    {"yaml", "YAML"},
    {"plaintext", "Plain Text"}
  ]

  @canonical_ids Enum.map(@languages, &elem(&1, 0)) -- ["auto"]
  @labels Map.new(@languages)

  @aliases %{
    "auto" => "auto",
    "ex" => "elixir",
    "exs" => "elixir",
    "heex" => "html",
    "js" => "javascript",
    "jsx" => "javascript",
    "mjs" => "javascript",
    "ts" => "typescript",
    "tsx" => "typescript",
    "py" => "python",
    "python3" => "python",
    "golang" => "go",
    "rs" => "rust",
    "htm" => "html",
    "xml" => "html",
    "svg" => "html",
    "scss" => "css",
    "jsonc" => "json",
    "postgres" => "sql",
    "postgresql" => "sql",
    "sqlite" => "sql",
    "mysql" => "sql",
    "md" => "markdown",
    "sh" => "bash",
    "shell" => "bash",
    "zsh" => "bash",
    "rb" => "ruby",
    "cpp" => "c",
    "c++" => "c",
    "h" => "c",
    "hpp" => "c",
    "yml" => "yaml",
    "text" => "plaintext",
    "txt" => "plaintext",
    "plain" => "plaintext",
    "none" => "plaintext"
  }

  @doc """
  Returns all select options `{label, value}` for UI dropdowns, including Auto-detect.
  """
  def select_options do
    Enum.map(@languages, fn {id, label} -> {label, id} end)
  end

  @doc """
  Returns select options without `auto` (for editing an existing paste's language or docs).
  """
  def concrete_select_options do
    @languages
    |> Enum.reject(fn {id, _} -> id == "auto" end)
    |> Enum.map(fn {id, label} -> {label, id} end)
  end

  @doc """
  Returns list of canonical concrete language IDs.
  """
  def canonical_ids, do: @canonical_ids

  @doc """
  Returns all valid input language identifiers (including "auto" and aliases).
  """
  def valid_language?(nil), do: true
  def valid_language?(""), do: true

  def valid_language?(lang) when is_binary(lang) do
    down = String.downcase(String.trim(lang))
    down in @canonical_ids or Map.has_key?(@aliases, down)
  end

  def valid_language?(_), do: false

  @doc """
  Normalizes a language input string to a canonical language ID or `"auto"`.
  Returns `{:ok, canonical}` or `:error`.
  """
  def normalize(nil), do: {:ok, "auto"}
  def normalize(""), do: {:ok, "auto"}

  def normalize(lang) when is_binary(lang) do
    down = String.downcase(String.trim(lang))

    cond do
      down == "" -> {:ok, "auto"}
      down in @canonical_ids -> {:ok, down}
      Map.has_key?(@aliases, down) -> {:ok, Map.fetch!(@aliases, down)}
      true -> :error
    end
  end

  def normalize(_), do: :error

  @doc """
  Returns the human-readable display name for a language ID.
  """
  def label(lang) when is_binary(lang) do
    Map.get(@labels, lang, String.capitalize(lang))
  end

  def label(_), do: "Plain Text"
end
