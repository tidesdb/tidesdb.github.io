import { defineRouteMiddleware } from '@astrojs/starlight/route-data';

/** Total entries in a table of contents tree, nested ones included. */
function countEntries(items: { children?: unknown[] }[]): number {
	return items.reduce(
		(total, item) =>
			total + 1 + countEntries((item.children ?? []) as { children?: unknown[] }[]),
		0
	);
}

/**
 * Drop the table of contents on pages that have nothing to list.
 *
 * Two cases. Articles never show one, and any other page shows one only when it
 * has something to list: Starlight always injects an "Overview" entry pointing
 * at the page's own title, so a page with no headings otherwise gets a panel
 * containing exactly one link, to itself.
 *
 * This runs as route middleware rather than being handled in the PageSidebar
 * override, because `data-has-toc` on <html> is set from `Boolean(route.toc)`
 * in Starlight's Page.astro and drives both the content width and the two
 * column layout. Hiding just the panel would have left the gutter reserved and
 * the content column narrow for no reason. Clearing `toc` here means Starlight
 * never renders the panel, on desktop or mobile, and widens the content itself.
 */
export const onRequest = defineRouteMiddleware((context) => {
	const route = context.locals.starlightRoute;
	if (!route.toc) return;

	// Articles never get one. They are prose read start to finish, not reference
	// pages navigated by heading, and half of them carry no headings at all, so
	// a panel appearing on some articles and not others read as a glitch.
	const isArticle = typeof route.entry.id === 'string' && route.entry.id.startsWith('articles/');

	// Anywhere else, drop it only when there is nothing to list.
	if (isArticle || countEntries(route.toc.items) <= 1) {
		route.toc = undefined;
	}
});
