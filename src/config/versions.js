// Single source of truth for versioned documentation.
//
// A "version" is a TidesDB major release LINE, modelled as a DISTRIBUTION (a
// bill of materials): the TidesDB C manual (core) plus the integrations
// (TideSQL, Kafka) and language bindings that belong to that major. Each
// component keeps its own repo, its own version, and its own release cadence.
//
// The version dropdown selects the major. Component versions are shown as
// read-only badges — never a second dropdown. See components/VersionSwitcher
// .astro and components/Sidebar.astro.
//
// A component is declared ONCE, as `{ id, label, repo, tag }`. There is no
// synced-vs-link-out switch to maintain, because the answer is not ours to
// give: scripts/sync-docs.mjs asks GitHub whether that repo publishes a
// doc/manual.json for this major, and
//
//   published for this major → its chapters are rendered into the site
//   published for another    → a link-out (those pages describe another release)
//   no doc/manual.json       → a link-out to the repository
//   no repository yet        → compatibility page only, with no link
//
// So a component is promoted by PUSHING docs to its repo and re-running the
// sync, never by editing this file. Nothing on this site can document code that
// is not published — see the header of scripts/doc-source.mjs.
//
// `tidesdb` on a component is a stated fact for the undocumented case: the
// major that component currently supports, which we cannot read from a manifest
// that does not exist yet. It is ignored once the repo publishes one.
//
// `tag: null` means no pinned release, so the repo's default branch is read and
// the compatibility page marks it unpinned. Set a tag once released and the
// read becomes immutable.
//
// Legacy majors (< v10) predate the restructured manual → status 'legacy',
// routed to /docs/legacy/.

const GH = 'https://github.com/tidesdb';

/** @type {any[]} */
export const VERSIONS = [
	{
		id: 'v10',
		label: '10.0.0',
		status: 'current',
		latest: true,

		// The C storage engine manual — the spine of the distribution. Pinned to
		// the release tag, so these pages are exactly the v10.0.0 manual and a
		// re-sync on any machine reproduces them byte for byte.
		core: { repo: 'tidesdb', tag: 'v10.0.0' },

		// Integrations: TideSQL (the SQL storage engine) and the Kafka connector.
		//
		// TideSQL ships as two engines built from two repos — one for MariaDB, one
		// for MySQL — so it is modelled as a labelled parent with a VARIANT per
		// server rather than one merged manual. The system variables, compatibility
		// notes and install steps genuinely differ between the two, and a merged
		// table hedged with "on MySQL this one is named differently" serves neither
		// reader. Variants get their own namespace (tidesql/<variant>), so no page
		// of one can be mistaken for the other.
		integrations: [
			{
				id: 'tidesql',
				label: 'TideSQL',
				variants: [
					// The primary target: expanded when TideSQL opens, so the common
					// case stays one click.
					{ id: 'mariadb', label: 'MariaDB', repo: 'tidesql', tag: null, tidesdb: '10.0.0', open: true },
					// Listed before it exists on purpose: the compatibility page shows
					// it as announced, and the day tidesdb/tidesql-mysql is pushed with
					// a doc/ directory it appears in the sidebar on the next sync.
					{ id: 'mysql', label: 'MySQL', repo: 'tidesql-mysql', tag: null },
				],
			},
			{ id: 'kafka', label: 'Kafka connector', repo: 'tidesdb-kafka', tag: null, tidesdb: '9' },
		],

		// Language bindings (FFI). C is the core itself, so it's not listed here.
		// Every published binding repo is still on the TidesDB 9 line and ships no
		// doc/manual.json, so all of them currently render as link-outs. Push a
		// doc/ directory declaring "tidesdb": "10.0.0" to any of these and it is
		// documented here on the next sync, with no change to this file.
		bindings: [
			{ id: 'cpp', label: 'C++', repo: 'tidesdb-cpp', tag: null, tidesdb: '9' },
			{ id: 'rust', label: 'Rust', repo: 'tidesdb-rs', tag: null, tidesdb: '9' },
			{ id: 'go', label: 'Go', repo: 'tidesdb-go', tag: null, tidesdb: '9' },
			{ id: 'python', label: 'Python', repo: 'tidesdb-python', tag: null, tidesdb: '9' },
			{ id: 'java', label: 'Java', repo: 'tidesdb-java', tag: null, tidesdb: '9' },
			{ id: 'csharp', label: 'C#', repo: 'tidesdb-cs', tag: null, tidesdb: '9' },
			{ id: 'typescript', label: 'TypeScript', repo: 'tidesdb-ts', tag: null, tidesdb: '9' },
			{ id: 'lua', label: 'Lua', repo: 'tidesdb-lua', tag: null, tidesdb: '9' },
		],
	},
	{
		id: 'v9',
		label: '9.x',
		status: 'legacy',
		link: `${GH}/tidesdb/tree/v9.3.14`,
	},
];

/** The version served at bare /docs and used as the default target. */
export const LATEST = VERSIONS.find((v) => v.latest) ?? VERSIONS[0];

/** Versions that ship the restructured manual bundle. */
export const CURRENT_VERSIONS = VERSIONS.filter((v) => v.status === 'current');

/** Look up a version by its URL id ('v10'), or undefined. */
export function versionById(id) {
	return VERSIONS.find((v) => v.id === id);
}

/**
 * Given any pathname, return the active version id if it is under /docs/<id>/,
 * otherwise null. Used by the sidebar to know which tree to render.
 * @param {string} pathname
 * @returns {string|null}
 */
export function activeVersionId(pathname) {
	const m = pathname.match(/^\/docs\/(v[^/]+)(?:\/|$)/);
	return m && versionById(m[1]) ? m[1] : null;
}

/**
 * Flatten a distribution's components into a single ordered list for the
 * compatibility table: core, integrations, then bindings. An integration with
 * variants contributes one row per variant ("TideSQL for MariaDB"), keyed
 * `<integration>-<variant>` to match the ids sync writes into the nav manifest.
 * @param {any} version
 */
export function distributionComponents(version) {
	if (version.status !== 'current') return [];
	const rows = [{ id: 'core', label: 'TidesDB (core)', kind: 'Core', component: version.core }];
	for (const it of version.integrations ?? []) {
		if (it.variants?.length) {
			for (const variant of it.variants) {
				rows.push({
					id: `${it.id}-${variant.id}`,
					label: `${it.label} for ${variant.label}`,
					kind: 'Integration',
					component: variant,
				});
			}
			continue;
		}
		rows.push({ id: it.id, label: it.label, kind: 'Integration', component: it });
	}
	for (const b of version.bindings ?? []) {
		rows.push({ id: b.id, label: b.label, kind: 'Language binding', component: b });
	}
	return rows;
}
