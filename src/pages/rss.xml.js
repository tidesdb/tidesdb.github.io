// RSS feed for the articles, served at /rss.xml.
//
// Selects articles the same way /blog and /blog/<slug> do, by the `articles/`
// prefix on the collection id, and takes dates and authors from git history via
// the same helpers, so the feed can never disagree with the blog listing about
// when something was published or who wrote it.
//
// Items carry the frontmatter description rather than the rendered article. Full
// content would mean pulling in a markdown renderer and a sanitiser just for the
// feed, and these articles lean on tables and plots that read poorly in a feed
// reader anyway, so the description plus a link is the honest version.

import rss from '@astrojs/rss';
import { getCollection } from 'astro:content';
import { SITE, articleDates, publishedArticles, resolveAuthor, summarize } from '../utils/articles.js';

export async function GET(context) {
	const articles = publishedArticles(await getCollection('docs'))
		.map((entry) => ({ entry, meta: articleDates(entry) }))
		.sort((a, b) => b.meta.created.getTime() - a.meta.created.getTime());

	return rss({
		title: 'TidesDB Blog',
		description: 'Benchmarks, engineering deep-dives, and updates from the TidesDB team.',
		// `context.site` comes from `site` in astro.config.mjs; SITE is the fallback
		// so the feed still builds with absolute links if that is ever unset.
		site: context.site ?? SITE,
		trailingSlash: true,
		items: articles.map(({ entry, meta }) => ({
			title: entry.data.title,
			description: summarize(entry),
			link: `/${entry.id}/`,
			pubDate: meta.created,
			author: resolveAuthor(entry, meta.gitAuthor).name,
		})),
		customData: '<language>en-us</language>',
	});
}
