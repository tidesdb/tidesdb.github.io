// @ts-check
import { readFileSync } from 'node:fs';
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { LATEST } from './src/config/versions.js';

// Landing chapter for the latest docs bundle (first entry in reading order).
const LATEST_DOCS = `/docs/${LATEST.id}/preface`;
const D = `/docs/${LATEST.id}`;

// The pre-v10 site kept one flat page per topic under /reference/ and two
// explainers under /getting-started/. The restructured manual replaced all of
// them, so every one of those URLs is mapped to its nearest equivalent rather
// than left to 404 — they are the site's oldest and best-linked pages.
//
// Per-component pages are resolved through the sync manifest rather than
// hard-coded, because whether a component is documented HERE changes on its own
// (see scripts/sync-docs.mjs). While one is unpublished its old URL lands on the
// compatibility page — the on-site index that explains the situation and links
// to the repo — and the moment its docs are published and synced, the same
// redirect follows to the real chapter with no edit here.
// Written by sync-docs, which `npm run build` and `npm run dev` both run first.
// Tolerate its absence so a bare `astro build`/`astro preview` still loads: with
// no manifest every component simply resolves to the compatibility page.
/** @type {{ components: Record<string, { source?: string, landing?: string|null }> }} */
let nav = { components: {} };
try {
	nav = JSON.parse(readFileSync(new URL(`./src/config/nav/${LATEST.id}.json`, import.meta.url), 'utf8'));
} catch {
	console.warn('[redirects] no nav manifest yet — run `npm run sync-docs`');
}

/**
 * Where a component's docs live on this site, or the compatibility page.
 * @param {string} id
 */
function componentDocs(id) {
	const rec = nav.components?.[id];
	const documented = rec?.source === 'tag' || rec?.source === 'branch';
	return documented && rec.landing ? rec.landing : `${D}/compatibility`;
}

const LEGACY_REFERENCE = {
	'/getting-started/what-is-tidesdb': `${D}/preface`,
	'/getting-started/how-does-tidesdb-work': `${D}/internals/architecture`,
	'/reference/c': `${D}/reference/database`,
	'/reference/building': `${D}/administration/building`,
	'/reference/tuning': `${D}/appendix/configuration`,
	'/reference/admintool': `${D}/internals/testing-and-tools`,
	'/reference/tidesql': componentDocs('tidesql-mariadb'),
	'/reference/kafka': componentDocs('kafka'),
	'/reference/cplusplus': componentDocs('cpp'),
	'/reference/csharp': componentDocs('csharp'),
	'/reference/go': componentDocs('go'),
	'/reference/java': componentDocs('java'),
	'/reference/lua': componentDocs('lua'),
	'/reference/python': componentDocs('python'),
	'/reference/rust': componentDocs('rust'),
	'/reference/typescript': componentDocs('typescript'),
};

// https://astro.build/config
export default defineConfig({
	site: 'https://tidesdb.com',
	redirects: {
		// Bare docs entry points land on the latest bundle's first chapter.
		'/docs': LATEST_DOCS,
		[`/docs/${LATEST.id}`]: LATEST_DOCS,
		...LEGACY_REFERENCE,
	},
	integrations: [
		starlight({
			title: 'TidesDB',
			description: 'Fast, embeddable LSM-tree based key-value storage engine library written in C. ACID transactions, great concurrency, cross-platform support.',
			customCss: [
				'./src/styles/custom.css',
				'./src/styles/home.css',
			  ],
			components: {
				PageTitle: './src/components/PageTitle.astro',
				Head: './src/components/Head.astro',
				SocialIcons: './src/components/SocialIcons.astro',
				Sidebar: './src/components/Sidebar.astro',
				Pagination: './src/components/Pagination.astro',
			},
			logo: {
				light: './src/assets/tidesdb-logo-v8.svg',
				dark: './src/assets/tidesdb-logo-v8.svg',
				replacesTitle: true,
			},
			social: {
				youtube: 'https://www.youtube.com/@TidesDB',
				github: 'https://github.com/tidesdb/tidesdb',
				discord: 'https://discord.gg/tWEmjR66cy',
			},
			head: [
				{
					tag: 'link',
					attrs: {
						rel: 'preconnect',
						href: 'https://fonts.googleapis.com'
					}
				},
				{
					tag: 'link',
					attrs: {
						rel: 'preconnect',
						href: 'https://fonts.gstatic.com',
						crossorigin: 'anonymous'
					}
				},
				{
					tag: 'link',
					attrs: {
						href: 'https://fonts.googleapis.com/css2?family=Public+Sans:wght@300;400;500;600;700&family=Fira+Mono:wght@400;500;700&display=swap',
						rel: 'stylesheet'
					}
				},
				{
					tag: 'meta',
					attrs: {
						name: 'keywords',
						content: 'tidesdb, database, key-value store, lsm-tree, storage engine, embeddable database, c library, nosql, acid transactions, high performance database, column family, write-ahead log, bloom filter, data compression, cross-platform database, database library, key value database, fast database, embeddable storage, database engine, persistent storage, in-memory database, disk storage, concurrent database, transactional database, open source database'
					}
				},
				{
					tag: 'meta',
					attrs: {
						name: 'author',
						content: 'TidesDB Team'
					}
				},
				{
					tag: 'meta',
					attrs: {
						property: 'og:type',
						content: 'website'
					}
				},
				{
					tag: 'meta',
					attrs: {
						property: 'og:site_name',
						content: 'TidesDB'
					}
				},
				{
					tag: 'meta',
					attrs: {
						name: 'twitter:card',
						content: 'summary_large_image'
					}
				},
				{
					tag: 'meta',
					attrs: {
						name: 'robots',
						content: 'index, follow'
					}
				},
				{
					tag: 'meta',
					attrs: {
						name: 'language',
						content: 'English'
					}
				},
				{
					tag: 'meta',
					attrs: {
						name: 'revisit-after',
						content: '7 days'
					}
				},
				{
					tag: 'script',
					attrs: {
						async: true,
						src: 'https://www.googletagmanager.com/gtag/js?id=G-5P4BKM1TX3'
					}
				},
				{
					tag: 'script',
					content: `
						window.dataLayer = window.dataLayer || [];
						function gtag(){dataLayer.push(arguments);}
						gtag('js', new Date());
						gtag('config', 'G-5P4BKM1TX3');
					`
				}
			],
			sidebar: [
				{
					label: 'Getting Started',
					slug: 'getting-started',
				},
				{
					// Versions are chosen from the dropdown inside the docs, not
					// listed here. This just links into the latest bundle; the
					// custom Sidebar override renders the per-version tree.
					label: 'Documentation',
					link: LATEST_DOCS,
				},

				{
					label: 'Blog',
					link: '/blog',
				},
				{
					label: 'YouTube',
					link: 'https://www.youtube.com/@TidesDB',
				},
				{
					label: 'GitHub', link: 'https://github.com/tidesdb',
				},
				{
					label: 'Discord', link: 'https://discord.gg/tWEmjR66cy',
				},
				{
					label: 'Sponsors', link: 'https://tidesdb.com/sponsors'
				},
				{
					label: 'Partners', link: '/partners'
				},
				{
					label: 'Company',
					items: [
						{ label: 'About TidesDB Corp.', slug: 'company/about-tidesdb-corp' },
						//{ label: 'How does TidesDB work?', slug: 'getting-started/how-does-tidesdb-work' },
					],
				},
			],
		}),
	],
});
