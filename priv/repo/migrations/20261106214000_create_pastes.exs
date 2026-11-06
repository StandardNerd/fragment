defmodule Fragment.Repo.Migrations.CreatePastes do
  use Ecto.Migration

  def change do
    create table(:pastes, primary_key: false) do
      add :id, :string, primary_key: true
      add :content, :text, null: false
      add :language, :string, null: false, default: "plaintext"
      add :size_bytes, :integer, null: false, default: 0
      add :expires_at, :utc_datetime
      add :edit_token_hash, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:pastes, [:expires_at])
    create index(:pastes, [:inserted_at])
  end
end
