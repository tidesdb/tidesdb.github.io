# TidesDB Web

Official documentation website for TidesDB - a fast, embeddable key-value storage engine library.

## Development

### Prerequisites
- Node.js (v18 or higher)
- npm

### Installation

```bash
npm install
```

### Running in Development Mode

Start the development server with hot reload:

```bash
npm run dev
```

The site will be available at `http://localhost:4321`

### Building for Production

Build the static site:

```bash
npm run build
```

Preview the production build:

```bash
npm run preview
```

## Component documentation

The manuals for TidesDB and its components are **not stored in this repository**.
`npm run dev` and `npm run build` both run `npm run sync-docs` first, which pulls
each component's `doc/` directory from its own GitHub repository into
`src/content/docs/docs/` (gitignored). Both steps therefore need network access.

Which components are in a distribution — and which release of each — is declared
in [`src/config/versions.js`](src/config/versions.js). A component is rendered as
documentation here only if its repository publishes a `doc/manual.json` declaring
support for that TidesDB major; otherwise it degrades to a link to its repo and is
listed on the generated `/docs/<version>/compatibility` page. So a component is
published to the site by pushing docs to **its own repo** and re-running the sync,
never by editing this one.

Pin a component to a release tag (`tag: 'v10.0.0'`) to make builds reproducible;
`tag: null` tracks the repo's default branch and is flagged as unpinned on the
compatibility page.
