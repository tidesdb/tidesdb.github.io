// Resolve a component's documentation from GitHub — and ONLY from GitHub.
//
// The site documents what is PUBLISHED. A component therefore appears as real
// documentation here if, and only if, its own public repository carries a
// doc/manual.json declaring support for the TidesDB major it is filed under.
// There is deliberately no local-path escape hatch: docs that exist only on
// somebody's laptop must be pushed before the website will render them, so the
// site can never advertise an API that a reader cannot go and get.
//
// A component that is not (yet) documented is not an error. It degrades to a
// link-out pointing at its repository, and the compatibility page reports the
// major it currently supports. Push a doc/ directory to that repo and the next
// `npm run sync-docs` promotes it automatically — no config change anywhere.
//
// Resolution has two steps so that the common "no docs yet" case costs one
// cheap HTTP request instead of a clone:
//
//   1. probeComponent()  reads doc/manual.json over raw.githubusercontent.com
//   2. openReader()      shallow-clones the repo, only once step 1 succeeded
//
// `tag: null` means the component has no pinned release, so its default branch
// is read and the result is marked as such — reproducible only for that moment.
// Pin a tag and the read becomes immutable (and the clone cache permanent).

import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const CACHE_ROOT = join(ROOT, '.docs-cache');
const ORG = 'tidesdb';
const GH = `https://github.com/${ORG}`;
const RAW = `https://raw.githubusercontent.com/${ORG}`;

function git(args, cwd) {
	return execFileSync('git', args, {
		cwd,
		encoding: 'utf8',
		maxBuffer: 64 * 1024 * 1024,
		stdio: ['ignore', 'pipe', 'pipe'],
	});
}

/**
 * The repo's default branch ('master'), or null when the repository does not
 * exist or is not readable. Doubles as our existence check.
 */
function defaultBranch(url) {
	try {
		const out = git(['ls-remote', '--symref', url, 'HEAD']);
		return out.match(/^ref:\s+refs\/heads\/(\S+)\s+HEAD/m)?.[1] ?? null;
	} catch {
		return null;
	}
}

/** doc/manual.json at <repo>@<ref>, or null when the repo publishes none. */
async function fetchManifest(repo, ref) {
	const res = await fetch(`${RAW}/${repo}/${ref}/doc/manual.json`);
	if (res.status === 404) return null;
	if (!res.ok) {
		throw new Error(`${repo}: GitHub returned ${res.status} for doc/manual.json@${ref}`);
	}
	try {
		return JSON.parse(await res.text());
	} catch (err) {
		throw new Error(`${repo}: doc/manual.json@${ref} is not valid JSON — ${err.message}`);
	}
}

/**
 * Ask GitHub what a component publishes, without cloning it. Returns one of:
 *
 *   { status: 'missing' }       no such repository (or it is private)
 *   { status: 'undocumented' }  repo exists, but publishes no doc/manual.json
 *   { status: 'documented' }    plus `manifest`, `ref` and `provenance`
 *
 * @param {{repo: string, tag?: string|null}} source
 */
export async function probeComponent(source) {
	const { repo, tag = null } = source;
	if (!repo) throw new Error('a component must name a `repo`');
	const repoUrl = `${GH}/${repo}`;

	// A pinned tag is taken at face value; otherwise find the default branch,
	// which also tells us whether the repository exists at all.
	const ref = tag ?? defaultBranch(repoUrl);
	if (!ref) return { status: 'missing', repo, repoUrl, ref: null };

	const manifest = await fetchManifest(repo, ref);
	if (!manifest) return { status: 'undocumented', repo, repoUrl, ref };

	return {
		status: 'documented',
		repo,
		repoUrl,
		ref,
		manifest,
		provenance: {
			kind: tag ? 'tag' : 'branch',
			ref,
			describe: `${repo}@${ref}${tag ? '' : ' (branch tip)'}`,
		},
	};
}

/**
 * Shallow-clone <repo>@<ref> and return `(relativePathInDoc) => contents`.
 * A tagged ref is immutable, so its cache entry is reused forever; a branch tip
 * moves, so it is re-cloned on every sync.
 */
export function openReader(repo, ref, { immutable }) {
	const dest = join(CACHE_ROOT, `${repo}@${ref}`.replace(/[/\\]/g, '-'));
	if (!(immutable && existsSync(join(dest, 'doc/manual.json')))) {
		rmSync(dest, { recursive: true, force: true });
		mkdirSync(CACHE_ROOT, { recursive: true });
		try {
			git(['clone', '--depth', '1', '--branch', ref, '--filter=blob:none', `${GH}/${repo}`, dest]);
		} catch (err) {
			const detail = (err.stderr || err.message).toString().trim().split('\n').pop();
			throw new Error(`${repo}: cloning ${ref} failed — ${detail}`);
		}
	}
	return (rel) => readFileSync(join(dest, 'doc', rel), 'utf8');
}
