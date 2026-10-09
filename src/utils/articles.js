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
 * Dates and author for one article, with frontmatter winning over git.
 *
 * `created` is the publication date, taken from `date` in frontmatter when it is
 * set and from the oldest commit otherwise. The override exists because git's
 * first commit is the date writing STARTED, which is the wrong date for anything
 * that sat as a draft or unlisted for a while. `updated` always comes from git,
 * since the last commit really is the last edit.
 *
 * @param {any} entry - a `docs` collection entry
 */
export function articleDates(entry) {
	const meta = gitMeta(entry.filePath ?? '');
	return {
		created: entry.data?.date ?? meta.created,
		updated: meta.updated,
		gitAuthor: meta.gitAuthor,
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

/**
 * The articles to list, matching Starlight's own draft rule exactly.
 *
 * Starlight filters drafts with `import.meta.env.MODE !== 'production' || draft
 * === false`, so a draft renders under `astro dev` (with its draft notice) and
 * is not generated at all in a production build. Our pages query the collection
 * directly, so without this they would advertise a card, a feed item and a
 * /blog/<slug> redirect for a page that does not exist once deployed.
 *
 * `unlisted: true` is also excluded here, but unlike a draft that page is still
 * built, so it keeps a public URL you can share while it stays off the listing,
 * the feed and the redirects. Publish either by removing the line.
 *
 * @param {any[]} entries - everything in the `docs` collection
 */
export function publishedArticles(entries) {
	return entries.filter(
		(entry) =>
			entry.id.startsWith('articles/') &&
			entry.data?.unlisted !== true &&
			(import.meta.env.MODE !== 'production' || entry.data?.draft !== true)
	);
}

/**
 * Summary for an article, for the blog card and the RSS item.
 *
 * `description` frontmatter when it exists, otherwise the opening prose of the
 * body. Two articles ship without one, which left both the blog card and the
 * feed item blank; a feed item with no description is close to useless in a
 * reader, so it falls back rather than showing nothing.
 */
export function summarize(entry, limit = 200) {
	const described = entry.data?.description;
	if (described) return described;

	const text = (entry.body ?? '')
		.replace(/^---\r?\n[\s\S]*?\r?\n---/, '')
		.replace(/```[\s\S]*?```/g, ' ')
		.replace(/!\[[^\]]*\]\([^)]*\)/g, ' ')
		.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
		.replace(/<[^>]+>/g, ' ')
		.replace(/^\s*\|.*$/gm, ' ')
		.replace(/[`*_#>]/g, '')
		// Articles open with a byline and a published-on line, so an excerpt taken
		// straight from the top would read "by Alex Gaetano Padula published on
		// June 4th, 2026 ..." instead of the article's first sentence.
		.replace(/^\s*(by|published on)\b.*$/gim, ' ')
		.replace(/\s+/g, ' ')
		.trim();

	if (!text) return '';
	if (text.length <= limit) return text;
	// Cut on a word boundary so the excerpt does not end mid-word.
	const cut = text.slice(0, limit);
	const lastSpace = cut.lastIndexOf(' ');
	return `${(lastSpace > limit * 0.6 ? cut.slice(0, lastSpace) : cut).trimEnd()}\u2026`;
}

/**
 * Compact date, e.g. "Jan 16, 2026", for the blog cards. At three and four
 * columns a card's meta row is about 250px wide, and the long month name alone
 * pushed the row onto a second line.
 */
export function fmtDateShort(d) {
	return d.toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' });
}
