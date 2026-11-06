defmodule Fragment.Pastes.Paste do
  @moduledoc """
  Schema and changesets for anonymous pastes ("fragments").
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Fragment.Syntax.{Detector, Languages}

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  @max_paste_bytes 524_288
  @id_alphabet ~c"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  @id_length 8

  @expiration_options [
    {"Never", "never"},
    {"10 minutes", "10m"},
    {"1 hour", "1h"},
    {"1 day", "1d"},
    {"7 days", "7d"},
    {"30 days", "30d"}
  ]

  schema "pastes" do
    field :content, :string
    field :language, :string, default: "auto"
    field :size_bytes, :integer, default: 0
    field :expires_at, :utc_datetime
    field :edit_token_hash, :string

    field :expires_in, :string, virtual: true, default: "never"
    field :edit_token, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  def max_paste_bytes, do: @max_paste_bytes
  def expiration_options, do: @expiration_options

  @doc """
  Changeset used for live form validation before submission.
  """
  def form_changeset(paste, attrs \\ %{}) do
    paste
    |> cast(attrs, [:content, :language, :expires_in], empty_values: [])
    |> validate_required([:content], message: "can't be blank")
    |> validate_not_blank(:content)
    |> validate_content_size()
    |> validate_and_normalize_language(resolve_auto?: false)
    |> validate_expiration()
  end

  @doc """
  Changeset for creating a new paste.
  Generates the short slug `id`, secret `edit_token`, `edit_token_hash`,
  resolves `"auto"` language detection, and computes `expires_at`.
  """
  def create_changeset(paste, attrs \\ %{}) do
    paste
    |> cast(attrs, [:id, :content, :language, :expires_in, :expires_at], empty_values: [])
    |> validate_required([:content], message: "can't be blank")
    |> validate_not_blank(:content)
    |> validate_content_size()
    |> validate_and_normalize_language(resolve_auto?: true)
    |> resolve_expiration(attrs)
    |> compute_size_bytes()
    |> put_id_if_missing()
    |> put_new_edit_token()
    |> unique_constraint(:id, name: :pastes_pkey)
  end

  @doc """
  Changeset for updating an existing paste with a valid edit token.
  """
  def update_changeset(paste, attrs \\ %{}) do
    paste
    |> cast(attrs, [:content, :language, :expires_in, :expires_at], empty_values: [])
    |> validate_required([:content], message: "can't be blank")
    |> validate_not_blank(:content)
    |> validate_content_size()
    |> validate_and_normalize_language(resolve_auto?: true)
    |> maybe_update_expiration(attrs)
    |> compute_size_bytes()
  end

  defp validate_not_blank(changeset, field) do
    case get_field(changeset, field) do
      val when is_binary(val) ->
        if String.trim(val) == "" do
          add_error(changeset, field, "can't be blank")
        else
          changeset
        end

      _ ->
        changeset
    end
  end

  defp validate_content_size(changeset) do
    case get_field(changeset, :content) do
      content when is_binary(content) ->
        bytes = byte_size(content)

        if bytes > @max_paste_bytes do
          add_error(
            changeset,
            :content,
            "is too large (#{format_bytes(bytes)}); maximum allowed size is 512 KB (524,288 bytes)"
          )
        else
          changeset
        end

      _ ->
        changeset
    end
  end

  defp validate_and_normalize_language(changeset, opts) do
    resolve_auto? = Keyword.get(opts, :resolve_auto?, true)
    raw_lang = get_field(changeset, :language)

    case Languages.normalize(raw_lang) do
      {:ok, "auto"} ->
        if resolve_auto? do
          content = get_field(changeset, :content) || ""
          put_change(changeset, :language, Detector.detect(content))
        else
          put_change(changeset, :language, "auto")
        end

      {:ok, canonical} ->
        put_change(changeset, :language, canonical)

      :error ->
        add_error(changeset, :language, "is not a supported language")
    end
  end

  defp validate_expiration(changeset) do
    expires_in = get_field(changeset, :expires_in)

    case parse_expires_in(expires_in) do
      {:ok, _} ->
        changeset

      :error ->
        add_error(
          changeset,
          :expires_in,
          "is invalid; supported values are never, 10m, 1h, 1d, 7d, 30d"
        )
    end
  end

  defp resolve_expiration(changeset, attrs) do
    explicit_expires_at = Map.get(attrs, :expires_at) || Map.get(attrs, "expires_at")

    raw_expires_in =
      Map.get(attrs, :expires_in) || Map.get(attrs, "expires_in") ||
        get_field(changeset, :expires_in)

    cond do
      not is_nil(explicit_expires_at) ->
        changeset

      true ->
        case parse_expires_in(raw_expires_in) do
          {:ok, nil} ->
            put_change(changeset, :expires_at, nil)

          {:ok, seconds} ->
            expires_at =
              DateTime.utc_now()
              |> DateTime.add(seconds, :second)
              |> DateTime.truncate(:second)

            put_change(changeset, :expires_at, expires_at)

          :error ->
            add_error(
              changeset,
              :expires_in,
              "is invalid; supported values are never, 10m, 1h, 1d, 7d, 30d"
            )
        end
    end
  end

  defp maybe_update_expiration(changeset, attrs) do
    has_expires_in? = Map.has_key?(attrs, :expires_in) or Map.has_key?(attrs, "expires_in")
    has_expires_at? = Map.has_key?(attrs, :expires_at) or Map.has_key?(attrs, "expires_at")

    if has_expires_in? or has_expires_at? do
      resolve_expiration(changeset, attrs)
    else
      changeset
    end
  end

  @doc """
  Parses an `expires_in` value into `{:ok, seconds | nil}` or `:error`.
  """
  def parse_expires_in(val) when val in [nil, "", "never", "none", "0", 0], do: {:ok, nil}

  def parse_expires_in(val) when val in ["10m", "10_minutes", "10 minutes", "600", 600],
    do: {:ok, 600}

  def parse_expires_in(val) when val in ["1h", "1_hour", "1 hour", "3600", 3600], do: {:ok, 3_600}

  def parse_expires_in(val) when val in ["1d", "1_day", "1 day", "24h", "86400", 86_400],
    do: {:ok, 86_400}

  def parse_expires_in(val) when val in ["7d", "7_days", "7 days", "1w", "604800", 604_800],
    do: {:ok, 604_800}

  def parse_expires_in(val) when val in ["30d", "30_days", "30 days", "1m", "2592000", 2_592_000],
    do: {:ok, 2_592_000}

  def parse_expires_in(_), do: :error

  defp compute_size_bytes(changeset) do
    case get_field(changeset, :content) do
      content when is_binary(content) -> put_change(changeset, :size_bytes, byte_size(content))
      _ -> changeset
    end
  end

  defp put_id_if_missing(changeset) do
    case get_field(changeset, :id) do
      id when is_binary(id) and id != "" -> changeset
      _ -> put_change(changeset, :id, generate_id())
    end
  end

  defp put_new_edit_token(changeset) do
    if get_field(changeset, :edit_token_hash) do
      changeset
    else
      token = generate_edit_token()

      changeset
      |> put_change(:edit_token, token)
      |> put_change(:edit_token_hash, hash_token(token))
    end
  end

  @doc """
  Generates a random 8-character nanoid-style alphanumeric slug.
  """
  def generate_id(length \\ @id_length) do
    alphabet = List.to_tuple(@id_alphabet)
    size = tuple_size(alphabet)

    for <<byte <- :crypto.strong_rand_bytes(length)>>, into: "" do
      <<elem(alphabet, rem(byte, size))::utf8>>
    end
  end

  @doc """
  Generates a one-time secret edit/delete token.
  """
  def generate_edit_token do
    "frag_" <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
  end

  @doc """
  Hashes an edit token using SHA-256.
  """
  def hash_token(token) when is_binary(token) do
    :crypto.hash(:sha256, token)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Constant-time comparison to check if `token` matches `paste.edit_token_hash`.
  """
  def valid_edit_token?(%__MODULE__{edit_token_hash: expected_hash}, token)
      when is_binary(expected_hash) and is_binary(token) and token != "" do
    actual_hash = hash_token(String.trim(token))
    Plug.Crypto.secure_compare(expected_hash, actual_hash)
  end

  def valid_edit_token?(_, _), do: false

  @doc """
  Returns true if the paste has passed its expiration timestamp.
  """
  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: %DateTime{} = expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) != :gt
  end

  @doc """
  Formats byte count into human-readable string (e.g. "1.4 KB").
  """
  def format_bytes(bytes) when is_integer(bytes) and bytes < 1024, do: "#{bytes} B"

  def format_bytes(bytes) when is_integer(bytes) do
    kb = Float.round(bytes / 1024, 1)
    "#{kb} KB"
  end
end
