import { execSync } from 'node:child_process';

export const SITE = 'https://tidesdb.com';

/**
 * Derive created/updated dates AND the original author from git history, so we
 * never hand-maintain `date`/`author` frontmatter. The deploy workflow checks
 * out with fetch-depth: 0, so full history is available at build time. Newest
 * commit = updated, oldest commit = created and its author = the creator.
 * Uncommitted files (local `astro dev`) fall back to now / no author.
 *
 * @param {string} filePath - repo-relative path, e.g. src/content/docs/articles/foo.md
 */
export function gitMeta(filePath) {
	let log = [];
	try {
		log = execSync(`git log --follow --format='%aI|%an' -- "${filePath}"`, {
			encoding: 'utf8',
		})
			.trim()
			.split('\n')
			.filter(Boolean);
	} catch {
		/* git unavailable or file untracked */
	}
	const parse = (line) => {
		const i = (line ?? '').indexOf('|');
		return i === -1 ? { date: '', name: '' } : { date: line.slice(0, i), name: line.slice(i + 1) };
	};
	const now = new Date().toISOString();
	const oldest = parse(log.at(-1));
	const newest = parse(log[0]);
	return {
		created: new Date(oldest.date || now),
		updated: new Date(newest.date || now),
		gitAuthor: oldest.name || null,
	};
}

/**
 * Resolve the display author: explicit frontmatter `author` wins, otherwise the
 * git creator, otherwise the org. `authorUrl` (frontmatter) optionally links it.
 */
export function resolveAuthor(entry, gitAuthor) {
	const name = entry.data?.author || gitAuthor || 'TidesDB';
	const url = entry.data?.authorUrl || null;
	return { name, url };
}

/** Pull the og:image out of an entry's `head` frontmatter. Returns an absolute URL. */
export function ogImage(entry) {
	const meta = (entry.data?.head ?? []).find(
		(h) => h.tag === 'meta' && h.attrs?.property === 'og:image'
	);
	const content = meta?.attrs?.content;
	if (!content) return null;
	// Normalise to an absolute URL rooted at the site.
	try {
		return new URL(content, SITE).href;
	} catch {
		return content;
	}
}

/** Human-readable date, e.g. "January 16, 2026". */
export function fmtDate(d) {
	return d.toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
}
