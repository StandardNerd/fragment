defmodule Fragment.Syntax.Detector do
  @moduledoc """
  Heuristic language auto-detector for code snippets.
  """

  @max_sample_bytes 16_384

  @doc """
  Detects the most likely language for the given `content`.
  Returns a canonical language identifier string (e.g., `"elixir"`, `"python"`, `"plaintext"`).
  """
  def detect(content) when is_binary(content) do
    sample =
      if byte_size(content) > @max_sample_bytes do
        binary_part(content, 0, @max_sample_bytes)
      else
        content
      end
      |> String.trim()

    cond do
      sample == "" ->
        "plaintext"

      shebang = detect_shebang(sample) ->
        shebang

      valid_json?(sample) ->
        "json"

      true ->
        score_languages(sample)
    end
  end

  def detect(_), do: "plaintext"

  defp detect_shebang(sample) do
    case String.split(sample, ~r/\r?\n/, parts: 2) do
      ["#!" <> line | _] ->
        line = String.downcase(line)

        cond do
          String.contains?(line, "elixir") -> "elixir"
          String.contains?(line, "python") -> "python"
          String.contains?(line, "ruby") -> "ruby"
          String.contains?(line, ["node", "deno", "bun"]) -> "javascript"
          String.contains?(line, ["ts-node", "tsx"]) -> "typescript"
          String.contains?(line, ["bash", "zsh", "/sh", " sh"]) -> "bash"
          true -> nil
        end

      _ ->
        nil
    end
  end

  defp valid_json?(sample) do
    first = String.first(sample)
    last = String.last(sample)

    if (first == "{" and last == "}") or (first == "[" and last == "]") do
      case Jason.decode(sample) do
        {:ok, decoded} when is_map(decoded) or is_list(decoded) -> true
        _ -> false
      end
    else
      false
    end
  end

  defp score_languages(sample) do
    rules = [
      {"elixir",
       [
         {~r/\bdefmodule\s+[A-Z][\w\.]*\s+do\b/, 10},
         {~r/\bdefp?\s+[a-z_]\w*.*do\b/, 6},
         {~r/\|>/, 5},
         {~r/@(moduledoc|doc|spec|impl|derive)\b/, 6},
         {~r/\b(GenServer|Supervisor|Phoenix|Ecto|Plug|Enum|Stream|Map|Keyword)\./, 5},
         {~r/%[A-Z][\w\.]*\{/, 5},
         {~r/\b(alias|import|use|require)\s+[A-Z][\w\.]*/, 4}
       ]},
      {"rust",
       [
         {~r/\bfn\s+[a-z_]\w*\s*\(/, 6},
         {~r/\blet\s+mut\s+[a-z_]\w*/, 7},
         {~r/\b(pub\s+(fn|struct|enum|mod|trait|use)|impl\b)/, 7},
         {~r/\b(println!|vec!|format!|panic!|eprintln!)\s*\(/, 8},
         {~r/\b(Option|Result|Some|None|Ok|Err)\b/, 3},
         {~r/#\[derive\(/, 9},
         {~r/::/, 2}
       ]},
      {"go",
       [
         {~r/^package\s+[a-z_]\w*/m, 10},
         {~r/\bfunc\s+(\([^)]+\)\s*)?[A-Za-z_]\w*\s*\(/, 7},
         {~r/:=/, 4},
         {~r/\bfmt\.(Print|Println|Printf|Sprintf|Errorf)\b/, 8},
         {~r/\bif\s+err\s*!=\s*nil\b/, 9},
         {~r/\btype\s+[A-Za-z_]\w*\s+(struct|interface)\s*\{/, 7}
       ]},
      {"python",
       [
         {~r/^def\s+[a-zA-Z_]\w*\s*\([^)]*\)\s*(->\s*[^:]+)?:/m, 8},
         {~r/^class\s+[A-Z]\w*(\([^)]*\))?\s*:/m, 7},
         {~r/^(from\s+[\w\.]+\s+import\s+|import\s+[\w\.]+)/m, 5},
         {~r/\bif\s+__name__\s*==\s*['"]__main__['"]\s*:/, 10},
         {~r/\b(elif|None|True|False|self\.)\b/, 4},
         {~r/\bprint\s*\(/, 2}
       ]},
      {"typescript",
       [
         {~r/\binterface\s+[A-Z]\w*\s*(<[^>]+>)?\s*\{/, 9},
         {~r/\btype\s+[A-Z]\w*\s*(<[^>]+>)?\s*=/, 7},
         {~r/:\s*(string|number|boolean|any|unknown|void|never|Record<|Array<|Promise<)\b/, 6},
         {~r/\b(readonly|keyof|as\s+const|satisfies)\b/, 6},
         {~r/\b(const|let|function|export|import)\b/, 2}
       ]},
      {"javascript",
       [
         {~r/\b(const|let|var)\s+[a-zA-Z_$][\w$]*\s*=/, 4},
         {~r/\bfunction\s+[a-zA-Z_$][\w$]*\s*\(/, 5},
         {~r/=>/, 3},
         {~r/\bconsole\.(log|error|warn|info|debug)\s*\(/, 7},
         {~r/\b(document\.(getElementById|querySelector)|window\.|module\.exports|require\()/, 7},
         {~r/\b(export\s+(default|const|function|class)|import\s+.*\s+from\s+['"])/, 6},
         {~r/===/, 3}
       ]},
      {"html",
       [
         {~r/<!DOCTYPE\s+html>/i, 12},
         {~r/<(html|head|body|div|span|section|article|header|footer|main|script|style|form|input|button|table|ul|li|a)\b[^>]*>/i,
          6},
         {~r/<\/(html|head|body|div|span|section|article|header|footer|main|script|style|form|button|table|ul|li|a)>/i,
          6}
       ]},
      {"css",
       [
         {~r/@(media|keyframes|import|layer|supports|font-face)\b/, 7},
         {~r/[.#]?[a-zA-Z_-][\w-]*\s*\{[^}]*\b(color|background|margin|padding|display|border|font-size|width|height|flex|grid)\s*:/s,
          9},
         {~r/--[a-zA-Z0-9-]+\s*:\s*[^;]+;/, 6}
       ]},
      {"sql",
       [
         {~r/\bSELECT\b.+\bFROM\b/is, 9},
         {~r/\b(CREATE|ALTER|DROP)\s+(TABLE|INDEX|VIEW|DATABASE)\b/i, 10},
         {~r/\bINSERT\s+INTO\b.+\bVALUES\b/is, 10},
         {~r/\bUPDATE\s+\w+\s+SET\b/is, 9},
         {~r/\b(INNER|LEFT|RIGHT|OUTER)\s+JOIN\b/i, 6},
         {~r/\b(WHERE|GROUP\s+BY|ORDER\s+BY|LIMIT)\b/i, 3}
       ]},
      {"bash",
       [
         {~r/\bset\s+-[euo]+/, 8},
         {~r/\bif\s+\[\[?\s+.+\s+\]\]?;\s*then\b/, 9},
         {~r/^(\s*fi|\s*done|\s*esac)\s*$/m, 6},
         {~r/\b(echo|export|chmod|chown|mkdir|grep|awk|sed|curl|sudo|apt-get|brew)\s+/, 4},
         {~r/\$\{[A-Za-z_][A-Za-z0-9_]*[^}]*\}/, 5}
       ]},
      {"ruby",
       [
         {~r/\bdef\s+[a-z_]\w*[?!]?\s*(\([^)]*\))?\s*\n.*?\bend\b/s, 6},
         {~r/\b(attr_accessor|attr_reader|attr_writer|require_relative|puts)\b/, 7},
         {~r/\bdo\s*\|[^|]+\|/, 7},
         {~r/\bclass\s+[A-Z]\w*\s*<\s*[A-Z][\w:]*/, 7}
       ]},
      {"c",
       [
         {~r/^#include\s*[<"][^>"]+[>"]/m, 10},
         {~r/\bint\s+main\s*\(/, 9},
         {~r/\b(printf|fprintf|malloc|free|sizeof|std::cout|std::vector|std::string)\b/, 7},
         {~r/\b(struct|typedef|uint32_t|size_t|NULL|nullptr)\b/, 5}
       ]},
      {"yaml",
       [
         {~r/^---\s*$/m, 5},
         {~r/^[a-zA-Z0-9_-]+:\s*\n(\s{2,}[a-zA-Z0-9_-]+:\s*.+\n?)+/m, 8},
         {~r/^[a-zA-Z0-9_-]+:\s*(\n\s+-\s+.+)+/m, 8}
       ]},
      {"markdown",
       [
         {~r/^#\{1,6\}\s+.+$/m, 5},
         {~r/^```[a-zA-Z0-9_-]*\s*\n.*?\n```/ms, 8},
         {~r/\[[^\]]+\]\(https?:\/\/[^\)]+\)/, 6},
         {~r/^(\s*[-*+]\s+.+\n){2,}/m, 4}
       ]}
    ]

    {best_lang, best_score} =
      Enum.reduce(rules, {"plaintext", 0}, fn {lang, patterns}, {acc_lang, acc_score} ->
        score =
          Enum.reduce(patterns, 0, fn {regex, weight}, sum ->
            if Regex.match?(regex, sample), do: sum + weight, else: sum
          end)

        if score > acc_score do
          {lang, score}
        else
          {acc_lang, acc_score}
        end
      end)

    # Fix markdown heading regex check separately as well
    md_score =
      if(Regex.match?(~r/^(\#{1,6})\s+\S+/m, sample), do: 5, else: 0) +
        if(Regex.match?(~r/^```[\w-]*\r?\n[\s\S]+?\r?\n```/m, sample), do: 8, else: 0) +
        if Regex.match?(~r/\[[^\]]+\]\([^\)]+\)/, sample), do: 5, else: 0

    cond do
      md_score > best_score and md_score >= 5 -> "markdown"
      best_score >= 4 -> best_lang
      true -> "plaintext"
    end
  end
end
