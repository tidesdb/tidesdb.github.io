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

## Project Structure

```
├── src/
│   ├── content/
│   │   └── docs/           # Documentation markdown files
│   │       ├── getting-started/
│   │       └── reference/
│   ├── styles/
│   │   └── custom.css      # Custom styling
│   └── assets/             # Images and static assets
├── astro.config.mjs        # Astro configuration
└── package.json
```

## Tech Stack

- **Framework**: [Astro](https://astro.build/)
- **Documentation**: [Starlight](https://starlight.astro.build/)
- **Styling**: Custom CSS with design system

## Contributions

Maintainers of official TidesDB libraries can submit additions and corrections to the reference documentation.

Anyone can create a PR (Pull Request) for:
- Fixing errors (spelling, write-ups, descriptions)
- Suggesting design improvements
- Proposing optimizations
- Adding new documentation sections

### Contributing Guidelines

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Make your changes
4. Test locally with `npm run dev`
5. Commit your changes (`git commit -m 'Add some feature'`)
6. Push to the branch (`git push origin feature/your-feature`)
7. Open a Pull Request

## License

See the main [TidesDB repository](https://github.com/tidesdb/tidesdb) for license information.