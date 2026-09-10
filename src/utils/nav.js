// Resolve links into the versioned docs, from the manifest sync-docs writes.
//
// Anything outside the docs tree that wants to link INTO it — the top-nav Docs
// dropdown, the getting-started hub, marketing pages — must go through here
// rather than composing a path by hand. Where a component's docs live is not a
// fact this repo owns: a component is rendered here only while its repository
// publishes docs for the current major, and it moves between a local chapter
// and its GitHub repo without warning (see scripts/sync-docs.mjs). A hand-built
// `/docs/v10/<component>/preface` is a 404 waiting for the next release.
//
// `componentHref` never returns a URL that 404s: the component's first chapter
// when it is documented here, its repository when it is not, and null when it
// has no repository yet — callers drop null entries from their menus.

const navModules = import.meta.glob('../config/nav/*.json', { eager: true });

/** @type {Record<string, any>} */
const byId = {};
for (const mod of Object.values(navModules)) {
	const nav = /** @type {any} */ (mod).default;
	byId[nav.id] = nav;
}

/** The whole manifest for a version, or null before the first sync. */
export function navFor(versionId) {
	return byId[versionId] ?? null;
}

/**
 * Where a component's documentation lives, or null when there is nothing to
 * link to. `id` is the component key from versions.js `distributionComponents`
 * — 'core', 'tidesql-mariadb', 'kafka', 'rust', …
 */
export function componentHref(versionId, id) {
	return navFor(versionId)?.components?.[id]?.landing ?? null;
}

/** True when the component's docs are rendered on this site (not a link-out). */
export function isDocumented(versionId, id) {
	const source = navFor(versionId)?.components?.[id]?.source;
	return source === 'tag' || source === 'branch';
}

/** First reachable href under a nav node. */
export function landingHref(node) {
	if (!node) return null;
	if (node.kind === 'page') return `/${node.slug}/`;
	if (node.kind === 'link') return node.href;
	if (node.kind === 'group') {
		for (const entry of node.entries) {
			const href = landingHref(entry);
			if (href) return href;
		}
	}
	return null;
}

/** Landing page of a top-level sidebar node, found by its label. */
export function topNodeHref(versionId, label) {
	const tree = navFor(versionId)?.tree ?? [];
	return landingHref(tree.find((n) => (n.label ?? n.title) === label));
}
