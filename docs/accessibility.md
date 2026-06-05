# Accessibility

Liminal targets WCAG 2.1 AA where practical. This document describes patterns used in the app, how to extend them, and known limitations.

## Patterns

### Icon-only controls

Every icon-only button or link must have an accessible name via `aria-label` (or visible text). Decorative icons inside labeled controls use `<.icon aria_hidden={true}>` (the default).

Hover tooltips (`<.with_tooltip>` + daisyUI `data-tip`) are mouse-only enhancements. Put the screen-reader name on the **focusable child** (button, link), not on the tooltip wrapper.

### Toggle groups (filters, tag chips)

Use `role="group"` with `aria-label` on the container and `aria-pressed={selected?}` on each toggle button. Keep existing `btn` / `badge` styling.

### Form fields

`<.input>` sets `aria-invalid`, `aria-describedby`, and daisyUI `validator` / `validator-hint` when a field has errors. Associate standalone selects with `<label for="…">`.

### Modals

`<.modal>` sets `aria-modal="true"` and `aria-labelledby` pointing at the `h2` title. Every modal should expose a visible Cancel/Close action.

### Live regions

Indexing status badges and empty states use `role="status"` and, where content updates dynamically, `aria-live="polite"`.

### Landmarks

- Skip link: Tailwind `sr-only focus:not-sr-only` → `#main-content`
- Account menu: `<nav aria-label="Account">`
- Theme toggle: `role="group"` with per-button `aria-label` and `aria-pressed`

### Screen-reader-only text

Use Tailwind `sr-only` — do not add custom `.sr-only` CSS.

## Known limitations

### Masonry layout

`assets/js/masonry_hook.js` positions cards with absolute layout. DOM/tab order is: new-link card, then streamed links. Visual column order on wide viewports may differ. This is accepted until native CSS masonry is broadly supported.

### Catppuccin themes

Latte/Mocha tokens and muted text (`text-base-content/45`–`/70`, viewed-link opacity) are unchanged. Some combinations may not meet WCAG contrast minimums. Contrast findings on theme tokens are documented, not treated as regressions to fix in this pass.

### Hover-only tooltips

daisyUI `data-tip` tooltips are not exposed on keyboard focus. Essential information must be in `aria-label` or visible text.

### Keyboard shortcuts

Global shortcuts (e.g. focus URL, paste link, toggle tags by number) are hinted inline via `<kbd>` badges on the new-link form for sighted keyboard users. There is no separate shortcuts help panel — adding one would compromise the links page layout. Screen reader coverage for shortcut discovery is intentionally limited; the paste hint uses `aria-label` where it does not affect visual design.

## Testing

### Automated

```bash
mix test test/liminal_web/live/link_live/index_test.exs
mix precommit
```

LiveView tests assert key ARIA attributes (`aria-pressed`, `aria-label`, landmarks).

### Manual (with server running)

```bash
mix phx.server
```

1. Tab through all routes; confirm focus is visible (daisyUI `btn` focus rings).
2. Run Lighthouse accessibility and axe DevTools on `/`, `/tags`, `/users/settings`, `/admin/users`.
3. Screen reader smoke test: create a link, filter, open a modal, delete with confirmation.
4. On the links page, note that tab order follows DOM, not visual masonry columns.

## Adding new UI

1. Name every interactive control (`aria-label` or visible label).
2. Use `<.input>` for form fields.
3. Use `role="group"` + `aria-pressed` for toggle groups.
4. Use `<.modal>` for dialogs; prefer existing flash for async feedback.
5. Prefer LiveView/HEEx and `Phoenix.LiveView.JS` over custom JS.
