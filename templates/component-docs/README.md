# Component documentation convention

Every FFI binding and integration documents itself in its **own repo**, under a
top-level `doc/` directory, using the same format as `tidesdb/doc`. The website
(`tidesdb.github.io`) pulls it in and renders it under the matching TidesDB
major — e.g. the Python binding lands at `/docs/v10/bindings/python/…`.

Copy the files in this folder into your component repo as a starting point.

## Layout

```
doc/
  manual.json              ← table of contents (required)
  01-getting-started/
    install.md
    quickstart.md
  02-guide/
    transactions.md
    iterators.md
  03-reference/
    database.md
    column-family.md
```

Directory names are arbitrary; `manual.json` maps them. Numbered prefixes just
keep source files in reading order on disk.

## `manual.json`

The table of contents. Top-level fields plus ordered `parts`:

- **`title`**: the component's manual title.
- **`tidesdb`**: the TidesDB version (`major.minor.patch`) this component
  supports, e.g. `"10.0.0"`. This is the authority the site uses to place the
  component under the right TidesDB major and to fill the compatibility table.
- **part**: `id`, `title` (the sidebar group heading), `dir` (folder — `""` if
  the file sits directly in `doc/`), `chapters`.
- **chapter**: `file` (within `dir`), `slug` (component-local, e.g.
  `reference/database`), `title` (sidebar label).

Do **not** put the component's *own* version in `manual.json` — the site never
shows it; the TidesDB major it's tied to is what matters. A **single-chapter
part** renders as a direct sidebar link (its heading is the page), not a
one-item dropdown.

## Markdown frontmatter

Only two fields are required:

```md
---
title: Database
description: One-line summary used for SEO and social cards.
---
```

You do **not** write a `slug` — the website injects the fully-qualified,
namespaced slug (`docs/<major>/bindings/<lang>/<slug>`) from `manual.json` at
sync time. Body content is normal Markdown (headings, code, tables, and
Starlight `:::note` / `:::tip` asides).

## How it appears on the site

- One part → the component collapses to a single sidebar group named after the
  component. Multiple parts → nested groups under the component.
- Until this `doc/` exists, the component shows as a link-out to its GitHub repo.
- Once it exists, the maintainer flips the component in the website's
  `src/config/versions.js` from `{ link }` to
  `{ source: { git: '<tag>', repo: '<path>' }, version: '<x.y.z>' }`, runs
  `npm run sync-docs`, and the pages appear with a version badge.
