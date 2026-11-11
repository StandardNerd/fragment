defmodule FragmentWeb.Layouts do
  @moduledoc """
  Application layouts and shared navigation/footer components.
  """
  use FragmentWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col bg-[var(--frag-bg)] text-[var(--frag-text)]">
      <header class="border-b border-[var(--frag-border)] bg-[var(--frag-surface)]/80 backdrop-blur-md sticky top-0 z-30">
        <div class="mx-auto max-w-5xl px-4 sm:px-6 h-14 flex items-center justify-between gap-4">
          <div class="flex items-center gap-6">
            <a
              href={~p"/"}
              class="group inline-flex items-center gap-2.5 text-base font-semibold tracking-tight text-[var(--frag-text)] hover:opacity-90 transition-opacity"
            >
              <img
                src={~p"/images/fragment_logo_dark_mode.png"}
                alt="fragment logo"
                class="logo-dark hidden dark:block h-14 w-auto rounded-md object-contain shadow-2xs"
              />
              <img
                src={~p"/images/fragment-logo.png"}
                alt="fragment logo"
                class="logo-light block dark:hidden h-14 w-auto rounded-md object-contain bg-white shadow-2xs"
              />
            </a>
          </div>

          <nav class="flex items-center gap-2 sm:gap-3" aria-label="Main navigation">
            <a
              href={~p"/"}
              class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs sm:text-sm font-medium bg-[var(--frag-accent)] hover:bg-[var(--frag-accent-hover)] text-white transition-colors"
            >
              <.icon name="hero-plus-mini" class="size-4" />
              <span>New</span>
            </a>

            <a
              href={~p"/api"}
              class="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-md text-xs sm:text-sm font-medium text-[var(--frag-text-muted)] hover:text-[var(--frag-text)] hover:bg-[var(--frag-surface-elevated)] border border-transparent hover:border-[var(--frag-border)] transition-colors"
            >
              <span class="font-mono text-xs">API</span>
            </a>

            <.theme_toggle />
          </nav>
        </div>
      </header>

      <main class="flex-1 mx-auto w-full max-w-5xl px-4 sm:px-6 py-8 sm:py-10">
        <.flash_group flash={@flash} />
        {render_slot(@inner_block)}
      </main>

      <footer class="border-t border-[var(--frag-border)] py-6 mt-12">
        <div class="mx-auto max-w-5xl px-4 sm:px-6 flex flex-col sm:flex-row items-center justify-between gap-3 text-xs text-[var(--frag-text-muted)]">
          <div class="flex items-center gap-2">
            <img
              src={~p"/images/fragment_logo_dark_mode.png"}
              alt="fragment logo"
              class="logo-dark hidden dark:block h-4 w-auto rounded-xs object-contain"
            />
            <img
              src={~p"/images/fragment-logo.png"}
              alt="fragment logo"
              class="logo-light block dark:hidden h-4 w-auto rounded-xs object-contain bg-white"
            />
            <span class="font-mono font-semibold text-[var(--frag-text)]">fragment</span>
            <span>&mdash;</span>
            <span>minimal anonymous pastebin</span>
          </div>
          <div class="flex items-center gap-4">
            <a
              href={~p"/"}
              class="hover:text-[var(--frag-text)] transition-colors"
            >
              New Paste
            </a>
            <span class="text-[var(--frag-border)]">&bull;</span>
            <a
              href={~p"/api"}
              class="hover:text-[var(--frag-accent)] font-mono transition-colors"
            >
              API Docs
            </a>
          </div>
        </div>
      </footer>
    </div>
    """
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="mb-4 empty:mb-0">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  def theme_toggle(assigns) do
    ~H"""
    <button
      type="button"
      id="theme-toggle"
      data-phx-theme="toggle"
      aria-label="Switch to dark mode"
      title="Switch to dark mode"
      onclick="window.dispatchEvent(new CustomEvent('phx:set-theme', {detail: {theme: 'toggle'}}))"
      class="inline-flex items-center justify-center size-8 sm:size-9 rounded-md border border-[var(--frag-border)] bg-[var(--frag-surface-elevated)] text-[var(--frag-text-muted)] hover:text-[var(--frag-text)] hover:border-[var(--frag-accent)] focus:outline-hidden focus-visible:ring-2 focus-visible:ring-[var(--frag-accent)] transition-all cursor-pointer"
    >
      <span
        class="hidden [[data-theme=dark]_&]:inline-flex items-center justify-center"
        aria-hidden="true"
      >
        <.icon name="hero-sun-micro" class="size-4 text-[var(--frag-accent)]" />
      </span>
      <span
        class="inline-flex [[data-theme=dark]_&]:hidden items-center justify-center"
        aria-hidden="true"
      >
        <.icon name="hero-moon-micro" class="size-4 text-[var(--frag-text-muted)]" />
      </span>
    </button>
    """
  end
end
