// Reading time estimate for an article, computed from its raw markdown.
//
// Taken from `entry.body` at build time rather than injected by a remark plugin,
// because remark-injected frontmatter only reaches a page through `render()`'s
// `remarkPluginFrontmatter`, which a Starlight component override cannot get at.
// Reading from the body works in both places that need it, the article page and
// the blog listing, from the same entry object.
//
// What gets stripped matters more than the words-per-minute figure. These
// articles are mostly benchmark write-ups, so they carry fenced config blocks,
// long image paths and sha256 hashes that nobody reads at prose speed. Leaving
// those in roughly doubles the estimate on a table-heavy article.

/** Average adult silent reading speed for technical prose. */
const WORDS_PER_MINUTE = 225;

/**
 * Words a reader actually reads, with the machinery removed.
 * @param {string} markdown
 */
export function countWords(markdown) {
	if (!markdown) return 0;
	const text = markdown
		// YAML frontmatter.
		.replace(/^---\r?\n[\s\S]*?\r?\n---/, '')
		// Fenced code blocks, including the config dumps these articles quote.
		.replace(/```[\s\S]*?```/g, ' ')
		.replace(/~~~[\s\S]*?~~~/g, ' ')
		// Images: alt text is not read, and the path certainly is not.
		.replace(/!\[[^\]]*\]\([^)]*\)/g, ' ')
		// Links: keep the visible text, drop the target.
		.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
		// HTML tags, keeping any text between them.
		.replace(/<[^>]+>/g, ' ')
		// Bare URLs.
		.replace(/https?:\/\/\S+/g, ' ')
		// Table rules, and the pipes that separate cells.
		.replace(/^\s*\|?[\s:-]*\|[\s|:-]*$/gm, ' ')
		.replace(/\|/g, ' ')
		// Inline code fences, emphasis and heading markers, keeping the content.
		.replace(/[`*_#>]/g, '')
		// Long hex strings (checksums) are one token, not forty words.
		.replace(/\b[0-9a-f]{16,}\b/gi, ' ');

	const words = text.split(/\s+/).filter((w) => /[a-z0-9]/i.test(w));
	return words.length;
}

/**
 * Minutes to read, rounded up, never less than one. A zero-word entry still
 * reports 1 rather than 0, because "0 min read" reads like a bug.
 * @param {string} markdown
 */
export function readingMinutes(markdown) {
	const words = countWords(markdown);
	return Math.max(1, Math.round(words / WORDS_PER_MINUTE));
}

/** "8 min read" */
export function readingLabel(markdown) {
	return `${readingMinutes(markdown)} min read`;
}
