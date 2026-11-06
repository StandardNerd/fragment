defmodule Fragment.Syntax.Highlighter do
  @moduledoc """
  Server-side syntax highlighter with strict HTML escaping and zero client-side JS overhead.
  Emits semantic `.hl-*` CSS classes that adapt automatically to dark and light themes.
  """

  alias Phoenix.HTML

  @max_tokenized_bytes 262_144

  @keywords %{
    "elixir" => MapSet.new(~w(
        def defp defmodule defmacro defmacrop defstruct defprotocol defimpl defexception
        defdelegate defguard defguardp defoverridable do end fn case cond with for if unless
        else try catch rescue after raise reraise throw receive send spawn alias import
        require use quote unquote unquote_splicing super when and or not in true false nil
      )),
    "javascript" => MapSet.new(~w(
        const let var function return if else for while do switch case break continue
        default try catch finally throw new delete typeof instanceof void in of class
        extends super import export from as async await yield static get set this
        true false null undefined debugger
      )),
    "typescript" => MapSet.new(~w(
        const let var function return if else for while do switch case break continue
        default try catch finally throw new delete typeof instanceof void in of class
        extends super import export from as async await yield static get set this
        true false null undefined interface type enum namespace declare readonly private
        protected public abstract implements keyof infer is asserts satisfies
      )),
    "python" => MapSet.new(~w(
        def class return if elif else for while break continue pass try except finally
        raise with as import from lambda yield async await global nonlocal del assert
        in is and or not True False None self cls match case
      )),
    "go" => MapSet.new(~w(
        break default func interface select case defer go map struct chan else goto
        package switch const fallthrough if range type continue for import return var
        true false nil iota
      )),
    "rust" => MapSet.new(~w(
        as async await break const continue crate dyn else enum extern false fn for if
        impl in let loop match mod move mut pub ref return self Self static struct super
        trait true type unsafe use where while macro_rules
      )),
    "sql" => MapSet.new(~w(
        select from where insert into values update set delete create alter drop table
        index view database schema primary key foreign references unique not null default
        auto_increment serial primary join inner left right full outer on group by order
        asc desc having limit offset union all distinct as and or in exists between like
        ilike case when then else end begin commit rollback transaction pragma with
        returning cascade restrict count sum avg min max coalesce cast
      )),
    "bash" => MapSet.new(~w(
        if then else elif fi case esac for select while until do done in function time
        coproc return exit break continue local export readonly declare typeset unset
        shift source eval exec set trap wait true false echo printf cd pwd read test
      )),
    "ruby" => MapSet.new(~w(
        BEGIN END alias and begin break case class def defined? do else elsif end ensure
        false for if in module next nil not or redo rescue retry return self super then
        true undef unless until when while yield require require_relative include extend
        attr_accessor attr_reader attr_writer private protected public
      )),
    "c" => MapSet.new(~w(
        auto break case catch class const constexpr continue default delete do else enum
        explicit export extern false final for friend goto if inline mutable namespace
        new noexcept nullptr operator private protected public register reinterpret_cast
        return sizeof static static_assert static_cast struct switch template this
        thread_local throw true try typedef typeid typename union using virtual volatile
        while NULL
      )),
    "css" => MapSet.new(~w(
        important media import keyframes supports layer font-face charset namespace
        from to solid dashed dotted none auto inherit initial unset revert flex grid
        block inline inline-block relative absolute fixed sticky hidden visible pointer
      )),
    "yaml" => MapSet.new(~w(
        true false null yes no on off
      ))
  }

  @types %{
    "typescript" => MapSet.new(~w(
        string number boolean any unknown never void object symbol bigint Array Promise
        Record Partial Required Readonly Pick Omit Exclude Extract Map Set Date RegExp Error
      )),
    "go" => MapSet.new(~w(
        bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64
        rune string uint uint8 uint16 uint32 uint64 uintptr any comparable
      )),
    "rust" => MapSet.new(~w(
        i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String
        Vec Box Rc Arc Cell RefCell Option Result Some None Ok Err HashMap HashSet
      )),
    "c" => MapSet.new(~w(
        void char short int long float double signed unsigned bool size_t ssize_t
        int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t uintptr_t
        ptrdiff_t FILE string vector map set unique_ptr shared_ptr
      )),
    "python" => MapSet.new(~w(
        int float str bool list dict set tuple bytes object Exception TypeError ValueError
        KeyError IndexError RuntimeError Optional Union Any Callable Iterable Sequence
      )),
    "sql" => MapSet.new(~w(
        int integer bigint smallint tinyint decimal numeric float real double precision
        char varchar text blob boolean date time timestamp datetime timestamptz uuid json jsonb
      ))
  }

  @doc """
  Highlights `content` for the given `language` and returns a list of `{line_number, Phoenix.HTML.safe()}` tuples.
  Every character of `content` is guaranteed to be HTML-escaped.
  """
  def highlight_lines(content, language) when is_binary(content) do
    lang = normalize_lang(language)
    lines = String.split(content, ~r/\r?\n/)
    tokenize_enabled? = byte_size(content) <= @max_tokenized_bytes and lang != "plaintext"

    lines
    |> Enum.with_index(1)
    |> Enum.map(fn {line, idx} ->
      rendered =
        if tokenize_enabled? do
          highlight_line(line, lang)
        else
          escape_text(line)
        end

      {idx, HTML.raw(rendered)}
    end)
  end

  def highlight_lines(_, _), do: [{1, HTML.raw("")}]

  @doc """
  Highlights `content` as a single `Phoenix.HTML.safe()` string.
  """
  def highlight(content, language) when is_binary(content) do
    lang = normalize_lang(language)

    if byte_size(content) <= @max_tokenized_bytes and lang != "plaintext" do
      content
      |> String.split(~r/\r?\n/)
      |> Enum.map_join("\n", &highlight_line(&1, lang))
      |> HTML.raw()
    else
      content
      |> escape_text()
      |> HTML.raw()
    end
  end

  def highlight(_, _), do: HTML.raw("")

  defp normalize_lang(lang) when is_binary(lang), do: String.downcase(String.trim(lang))
  defp normalize_lang(_), do: "plaintext"

  defp highlight_line("", _lang), do: ""

  defp highlight_line(line, "markdown") do
    cond do
      Regex.match?(~r/^\s*\#{1,6}\s+/, line) ->
        wrap("hl-heading", line)

      Regex.match?(~r/^\s*```/, line) ->
        wrap("hl-keyword", line)

      Regex.match?(~r/^\s*>\s+/, line) ->
        wrap("hl-comment", line)

      true ->
        scan_markdown_inline(line, [])
    end
  end

  defp highlight_line(line, "html") do
    scan_html(line, [])
  end

  defp highlight_line(line, "json") do
    scan_json(line, [])
  end

  defp highlight_line(line, "yaml") do
    scan_yaml(line, [])
  end

  defp highlight_line(line, lang) do
    scan_code(line, lang, [])
  end

  # HTML scanner
  defp scan_html("", acc), do: IO.iodata_to_binary(Enum.reverse(acc))

  defp scan_html("<!--" <> _ = rest, acc) do
    case :binary.match(rest, "-->") do
      {pos, 3} ->
        len = pos + 3
        comment = binary_part(rest, 0, len)
        rem = binary_part(rest, len, byte_size(rest) - len)
        scan_html(rem, [wrap("hl-comment", comment) | acc])

      :nomatch ->
        IO.iodata_to_binary(Enum.reverse([wrap("hl-comment", rest) | acc]))
    end
  end

  defp scan_html("<" <> _ = rest, acc) do
    case Regex.run(~r/^<\/?[a-zA-Z0-9:_-]+/, rest) do
      [tag_open] ->
        rem = binary_part(rest, byte_size(tag_open), byte_size(rest) - byte_size(tag_open))
        scan_html_attrs(rem, [wrap("hl-tag", tag_open) | acc])

      _ ->
        <<ch::utf8, rem::binary>> = rest
        scan_html(rem, [escape_char(ch) | acc])
    end
  end

  defp scan_html(rest, acc) do
    case :binary.match(rest, "<") do
      {pos, 1} when pos > 0 ->
        text = binary_part(rest, 0, pos)
        rem = binary_part(rest, pos, byte_size(rest) - pos)
        scan_html(rem, [escape_text(text) | acc])

      _ ->
        IO.iodata_to_binary(Enum.reverse([escape_text(rest) | acc]))
    end
  end

  defp scan_html_attrs("", acc), do: IO.iodata_to_binary(Enum.reverse(acc))

  defp scan_html_attrs("/" <> ">" <> rem, acc) do
    scan_html(rem, [wrap("hl-tag", "/>") | acc])
  end

  defp scan_html_attrs(">" <> rem, acc) do
    scan_html(rem, [wrap("hl-tag", ">") | acc])
  end

  defp scan_html_attrs(rest, acc) do
    cond do
      match = Regex.run(~r/^\s+/, rest) ->
        [ws] = match
        rem = drop_prefix(rest, ws)
        scan_html_attrs(rem, [ws | acc])

      match = Regex.run(~r/^[a-zA-Z_:][-a-zA-Z0-9_:.@]*/, rest) ->
        [attr] = match
        rem = drop_prefix(rest, attr)
        scan_html_attrs(rem, [wrap("hl-attr", attr) | acc])

      String.starts_with?(rest, "=") ->
        rem = drop_prefix(rest, "=")
        scan_html_attrs(rem, [wrap("hl-operator", "=") | acc])

      match = Regex.run(~r/^("[^"]*"|'[^']*')/, rest) ->
        [str | _] = match
        rem = drop_prefix(rest, str)
        scan_html_attrs(rem, [wrap("hl-string", str) | acc])

      true ->
        <<ch::utf8, rem::binary>> = rest
        scan_html_attrs(rem, [escape_char(ch) | acc])
    end
  end

  # JSON scanner
  defp scan_json("", acc), do: IO.iodata_to_binary(Enum.reverse(acc))

  defp scan_json(rest, acc) do
    cond do
      match = Regex.run(~r/^\s+/, rest) ->
        [ws] = match
        scan_json(drop_prefix(rest, ws), [ws | acc])

      match = Regex.run(~r/^"(?:\\.|[^"\\])*"(?=\s*:)/, rest) ->
        [key] = match
        scan_json(drop_prefix(rest, key), [wrap("hl-attr", key) | acc])

      match = Regex.run(~r/^"(?:\\.|[^"\\])*"/, rest) ->
        [str] = match
        scan_json(drop_prefix(rest, str), [wrap("hl-string", str) | acc])

      match = Regex.run(~r/^-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/, rest) ->
        [num] = match
        scan_json(drop_prefix(rest, num), [wrap("hl-number", num) | acc])

      match = Regex.run(~r/^(true|false|null)\b/, rest) ->
        [kw | _] = match
        scan_json(drop_prefix(rest, kw), [wrap("hl-keyword", kw) | acc])

      match = Regex.run(~r/^[{}\[\]:,]/, rest) ->
        [p] = match
        scan_json(drop_prefix(rest, p), [wrap("hl-punctuation", p) | acc])

      true ->
        <<ch::utf8, rem::binary>> = rest
        scan_json(rem, [escape_char(ch) | acc])
    end
  end

  # YAML scanner
  defp scan_yaml(line, _acc) do
    cond do
      Regex.match?(~r/^\s*#/, line) ->
        wrap("hl-comment", line)

      match = Regex.run(~r/^(\s*[-a-zA-Z0-9_.]+)(:\s*)(.*)$/, line) ->
        [_, key, colon, rest] = match

        IO.iodata_to_binary([
          wrap("hl-attr", key),
          wrap("hl-punctuation", colon),
          scan_code(rest, "yaml", [])
        ])

      true ->
        scan_code(line, "yaml", [])
    end
  end

  # Markdown inline scanner
  defp scan_markdown_inline("", acc), do: IO.iodata_to_binary(Enum.reverse(acc))

  defp scan_markdown_inline(rest, acc) do
    cond do
      match = Regex.run(~r/^`[^`]+`/, rest) ->
        [code] = match
        scan_markdown_inline(drop_prefix(rest, code), [wrap("hl-string", code) | acc])

      match = Regex.run(~r/^\*\*[^*]+\*\*/, rest) ->
        [bold] = match
        scan_markdown_inline(drop_prefix(rest, bold), [wrap("hl-keyword", bold) | acc])

      match = Regex.run(~r/^\[[^\]]+\]\([^\)]+\)/, rest) ->
        [link] = match
        scan_markdown_inline(drop_prefix(rest, link), [wrap("hl-function", link) | acc])

      true ->
        <<ch::utf8, rem::binary>> = rest
        scan_markdown_inline(rem, [escape_char(ch) | acc])
    end
  end

  # General code scanner for Elixir, JS/TS, Python, Go, Rust, SQL, Bash, Ruby, C, CSS
  defp scan_code("", _lang, acc), do: IO.iodata_to_binary(Enum.reverse(acc))

  defp scan_code(rest, lang, acc) do
    cond do
      # Whitespace
      match = Regex.run(~r/^\s+/, rest) ->
        [ws] = match
        scan_code(drop_prefix(rest, ws), lang, [ws | acc])

      # Line comments
      comment_prefix?(rest, lang) ->
        IO.iodata_to_binary(Enum.reverse([wrap("hl-comment", rest) | acc]))

      # Inline C-style block comments /* ... */
      lang in ["javascript", "typescript", "go", "rust", "c", "css", "sql"] and
          String.starts_with?(rest, "/*") ->
        case :binary.match(rest, "*/") do
          {pos, 2} ->
            len = pos + 2
            c = binary_part(rest, 0, len)
            scan_code(drop_prefix(rest, c), lang, [wrap("hl-comment", c) | acc])

          :nomatch ->
            IO.iodata_to_binary(Enum.reverse([wrap("hl-comment", rest) | acc]))
        end

      # Preprocessor / Attributes / Module attributes
      lang == "c" and Regex.match?(~r/^#[a-zA-Z_]\w*/, rest) ->
        [dir] = Regex.run(~r/^#[a-zA-Z_]\w*(?:\s*<[^>]+>)?/, rest)
        scan_code(drop_prefix(rest, dir), lang, [wrap("hl-keyword", dir) | acc])

      lang == "elixir" and Regex.match?(~r/^@[a-zA-Z_]\w*/, rest) ->
        [attr] = Regex.run(~r/^@[a-zA-Z_]\w*/, rest)
        scan_code(drop_prefix(rest, attr), lang, [wrap("hl-attr", attr) | acc])

      lang == "rust" and Regex.match?(~r/^#!?\[[^\]]*\]/, rest) ->
        [attr] = Regex.run(~r/^#!?\[[^\]]*\]/, rest)
        scan_code(drop_prefix(rest, attr), lang, [wrap("hl-attr", attr) | acc])

      lang == "python" and Regex.match?(~r/^@[a-zA-Z_][\w.]*/, rest) ->
        [dec] = Regex.run(~r/^@[a-zA-Z_][\w.]*/, rest)
        scan_code(drop_prefix(rest, dec), lang, [wrap("hl-attr", dec) | acc])

      # Strings (double, single, backtick)
      match = match_string(rest, lang) ->
        scan_code(drop_prefix(rest, match), lang, [wrap("hl-string", match) | acc])

      # Elixir / Ruby atoms & symbols
      lang in ["elixir", "ruby"] and Regex.match?(~r/^:[a-zA-Z_]\w*[?!]?/, rest) ->
        [atom] = Regex.run(~r/^:[a-zA-Z_]\w*[?!]?/, rest)
        scan_code(drop_prefix(rest, atom), lang, [wrap("hl-builtin", atom) | acc])

      lang == "elixir" and Regex.match?(~r/^[a-zA-Z_]\w*:(?!:)/, rest) ->
        [kw_key] = Regex.run(~r/^[a-zA-Z_]\w*:/, rest)
        scan_code(drop_prefix(rest, kw_key), lang, [wrap("hl-attr", kw_key) | acc])

      # Bash / PHP / Env variables
      lang in ["bash", "elixir"] and
          Regex.match?(~r/^\$(?:\{[a-zA-Z_]\w*\}|[a-zA-Z_0-9?@#*$!]+)/, rest) ->
        [var] = Regex.run(~r/^\$(?:\{[a-zA-Z_]\w*\}|[a-zA-Z_0-9?@#*$!]+)/, rest)
        scan_code(drop_prefix(rest, var), lang, [wrap("hl-variable", var) | acc])

      # Numbers (hex, binary, float, int)
      match =
          Regex.run(
            ~r/^(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?)/,
            rest
          ) ->
        [num] = match
        scan_code(drop_prefix(rest, num), lang, [wrap("hl-number", num) | acc])

      # CSS custom properties / properties
      lang == "css" and Regex.match?(~r/^--[a-zA-Z0-9_-]+|^[a-zA-Z-]+(?=\s*:)/, rest) ->
        [prop] = Regex.run(~r/^--[a-zA-Z0-9_-]+|^[a-zA-Z-]+(?=\s*:)/, rest)
        scan_code(drop_prefix(rest, prop), lang, [wrap("hl-attr", prop) | acc])

      lang == "css" and Regex.match?(~r/^#[0-9a-fA-F]{3,8}\b/, rest) ->
        [hex] = Regex.run(~r/^#[0-9a-fA-F]{3,8}\b/, rest)
        scan_code(drop_prefix(rest, hex), lang, [wrap("hl-number", hex) | acc])

      # Identifiers, Keywords, Types, Function calls
      match = Regex.run(~r/^[a-zA-Z_$][a-zA-Z0-9_$]*[?!]?/, rest) ->
        [ident] = match
        rem = drop_prefix(rest, ident)
        class = classify_identifier(ident, rem, lang)
        token = if class, do: wrap(class, ident), else: escape_text(ident)
        scan_code(rem, lang, [token | acc])

      # Operators
      match =
          Regex.run(
            ~r/^(?:\|>|->|=>|::|:=|===|!==|==|!=|<=|>=|&&|\|\||<<|>>|[+\-*\/%=<>!&|^~]+)/,
            rest
          ) ->
        [op] = match
        scan_code(drop_prefix(rest, op), lang, [wrap("hl-operator", op) | acc])

      # Punctuation
      match = Regex.run(~r/^[(){}\[\].,;:]/, rest) ->
        [p] = match
        scan_code(drop_prefix(rest, p), lang, [wrap("hl-punctuation", p) | acc])

      true ->
        <<ch::utf8, rem::binary>> = rest
        scan_code(rem, lang, [escape_char(ch) | acc])
    end
  end

  defp comment_prefix?(rest, lang) do
    cond do
      lang in ["elixir", "python", "bash", "ruby", "yaml"] ->
        String.starts_with?(rest, "#")

      lang in ["javascript", "typescript", "go", "rust", "c"] ->
        String.starts_with?(rest, "//")

      lang == "sql" ->
        String.starts_with?(rest, "--")

      true ->
        false
    end
  end

  defp match_string(rest, lang) do
    cond do
      String.starts_with?(rest, ~s(""")) ->
        case Regex.run(~r/^"""(?:\\.|[^\\])*?"""|^""".*$/, rest) do
          [m] -> m
          _ -> nil
        end

      String.starts_with?(rest, "\"") ->
        case Regex.run(~r/^"(?:\\.|[^"\\])*"?/, rest) do
          [m] -> m
          _ -> nil
        end

      String.starts_with?(rest, "'") and lang != "rust" ->
        case Regex.run(~r/^'(?:\\.|[^'\\])*'?/, rest) do
          [m] -> m
          _ -> nil
        end

      String.starts_with?(rest, "'") and lang == "rust" ->
        case Regex.run(~r/^'(?:\\.|[^'\\])'|^'[a-zA-Z_]\w*/, rest) do
          [m] -> m
          _ -> nil
        end

      String.starts_with?(rest, "`") and lang in ["javascript", "typescript", "go", "sql", "bash"] ->
        case Regex.run(~r/^`(?:\\.|[^`\\])*`?/, rest) do
          [m] -> m
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp classify_identifier(ident, rem, lang) do
    lookup_ident = if lang == "sql", do: String.downcase(ident), else: ident
    keywords = Map.get(@keywords, lang, MapSet.new())
    types = Map.get(@types, lang, MapSet.new())

    cond do
      MapSet.member?(keywords, lookup_ident) ->
        "hl-keyword"

      MapSet.member?(types, lookup_ident) ->
        "hl-type"

      Regex.match?(~r/^[A-Z][A-Za-z0-9_]*$/, ident) and lang != "sql" ->
        "hl-type"

      String.starts_with?(rem, "(") or (lang == "rust" and String.ends_with?(ident, "!")) ->
        "hl-function"

      true ->
        nil
    end
  end

  defp drop_prefix(str, prefix) do
    len = byte_size(prefix)
    binary_part(str, len, byte_size(str) - len)
  end

  defp wrap(class, text) do
    [~s(<span class="), class, ~s(">), escape_text(text), "</span>"]
  end

  @doc """
  Safely HTML-escapes any binary string.
  """
  def escape_text(text) when is_binary(text) do
    text
    |> HTML.html_escape()
    |> HTML.safe_to_string()
  end

  defp escape_char(?&), do: "&amp;"
  defp escape_char(?<), do: "&lt;"
  defp escape_char(?>), do: "&gt;"
  defp escape_char(?"), do: "&quot;"
  defp escape_char(?'), do: "&#39;"
  defp escape_char(ch), do: <<ch::utf8>>
end
