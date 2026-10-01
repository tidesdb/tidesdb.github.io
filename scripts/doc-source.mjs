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
// A component says WHICH commit to read in one of three ways:
//
//   track: '10'      newest vX.Y.Z release in that major line. Patch and minor
//                    releases reach the site on the next build, with no commit
//                    here; a new major never does, because that is a new
//                    distribution. This is the normal choice.
//   tag: 'v10.0.1'   exactly that release, forever — for freezing a line that
//                    should stop moving, or publishing a pre-release.
//   neither          the default branch tip: work that has not been released at
//                    all. Flagged as unpinned wherever it is shown.
//
// Each resolved tag is immutable, so the clone cache is keyed by repo@tag and a
// newly released tag simply gets a fresh entry.

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

/**
 * Release tags in one major line, newest first — the mechanism behind `track`.
 *
 * Only plain `vX.Y.Z` tags count. A pre-release (`v10.1.0-rc1`) is never picked
 * up by tracking a line; pin it with `tag` if you deliberately want to publish
 * docs for one. The major is matched exactly, so tracking 10 will follow 10.1.0
 * and 10.2.3 but never cross to 11 — a new major is a new distribution, which is
 * a decision for versions.js rather than something a release should trigger.
 */
function releasesInMajor(url, major) {
	let out;
	try {
		out = git(['ls-remote', '--tags', '--refs', url]);
	} catch {
		return [];
	}
	const found = [];
	for (const line of out.split('\n')) {
		const name = line.split('refs/tags/')[1]?.trim();
		const m = name && /^v?(\d+)\.(\d+)\.(\d+)$/.exec(name);
		if (!m) continue;
		const parts = [Number(m[1]), Number(m[2]), Number(m[3])];
		if (parts[0] !== Number(major)) continue;
		found.push({ name, parts });
	}
	found.sort((a, b) => b.parts[0] - a.parts[0] || b.parts[1] - a.parts[1] || b.parts[2] - a.parts[2]);
	return found.map((f) => f.name);
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
	const { repo, tag = null, track = null } = source;
	if (!repo) throw new Error('a component must name a `repo`');
	if (tag && track != null) {
		throw new Error(`${repo}: set either \`tag\` (frozen) or \`track\` (newest in a line), not both`);
	}
	const repoUrl = `${GH}/${repo}`;

	// Which commit to read, in order of precedence:
	//   tag    — exactly that release, forever
	//   track  — newest vX.Y.Z in that major line, so a patch or minor release
	//            reaches the site on the next build with no commit here
	//   else   — the default branch tip (work that has not been released yet)
	// Tracking a line with no release in it yet falls back to the branch tip,
	// which is how a component behaves before its first release.
	let ref = tag;
	let tracked = false;
	if (!ref && track != null) {
		ref = releasesInMajor(repoUrl, track)[0] ?? null;
		tracked = Boolean(ref);
	}
	if (!ref) ref = defaultBranch(repoUrl);
	if (!ref) return { status: 'missing', repo, repoUrl, ref: null };

	const manifest = await fetchManifest(repo, ref);
	if (!manifest) return { status: 'undocumented', repo, repoUrl, ref };

	const pinned = Boolean(tag) || tracked;
	return {
		status: 'documented',
		repo,
		repoUrl,
		ref,
		manifest,
		provenance: {
			kind: pinned ? 'tag' : 'branch',
			ref,
			tracked,
			describe: tracked
				? `${repo}@${ref} (newest in ${track}.x)`
				: `${repo}@${ref}${tag ? '' : ' (branch tip)'}`,
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
