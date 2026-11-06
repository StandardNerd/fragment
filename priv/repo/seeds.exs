# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
alias Fragment.Pastes
alias Fragment.Pastes.Paste
alias Fragment.Repo

samples = [
  %{
    id: "elixir01",
    language: "elixir",
    expires_in: "never",
    content: """
    defmodule Fragment.Greeter do
      @moduledoc "Minimal greeting example in Elixir."

      def hello(name \\\\ "world") when is_binary(name) do
        "Hello, \#{name}!"
        |> String.trim()
        |> IO.puts()
      end
    end
    """
  },
  %{
    id: "python01",
    language: "python",
    expires_in: "30d",
    content: """
    from dataclasses import dataclass

    @dataclass
    class Paste:
        slug: str
        content: str
        language: str = "python"

    if __name__ == "__main__":
        p = Paste(slug="python01", content="print('hello')")
        print(f"Created paste {p.slug} ({len(p.content)} bytes)")
    """
  },
  %{
    id: "rust0001",
    language: "rust",
    expires_in: "7d",
    content: """
    #[derive(Debug)]
    struct Fragment<'a> {
        id: &'a str,
        bytes: usize,
    }

    fn main() {
        let item = Fragment { id: "rust0001", bytes: 128 };
        println!("Fragment {:?} ready", item);
    }
    """
  }
]

for sample <- samples do
  if is_nil(Repo.get(Paste, sample.id)) do
    {:ok, _paste} = Pastes.create_paste(sample)
  end
end
