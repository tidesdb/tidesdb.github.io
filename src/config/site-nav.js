// The site's top-level navigation, declared once.
//
// Two components render this list: SocialIcons.astro draws it as header
// dropdowns on desktop, and MobileSiteNav.astro draws it as a flat list inside
// the mobile menu — Starlight hides the header's whole right-hand group below
// its 50rem breakpoint, so the desktop nav simply does not exist on a phone.
//
// They share this module rather than each keeping a copy, because a link that
// exists in only one of them is a page half the site's visitors cannot reach,
// and that is invisible to whoever is testing on a laptop.
//
// Per-component destinations resolve through the sync manifest (see
// utils/nav.js): a component moves between an on-site chapter and its GitHub
// repo as it publishes docs, and entries with nowhere to point drop out.

import { componentHref } from '../utils/nav.js';
import { LATEST } from './versions.js';

/**
 * Nav sections in header order. A section is either a single link (`href`) or a
 * menu (`links`). Menu entries whose destination is unknown are omitted.
 */
export function siteNavSections() {
	const v = LATEST.id;
	return [
		{
			id: 'docs',
			label: 'Docs',
			links: [
				{ label: 'Getting Started', href: '/getting-started/' },
				{ label: 'TidesDB manual', href: `/docs/${v}/preface` },
				{ label: 'TideSQL', href: componentHref(v, 'tidesql-mariadb') },
				{ label: 'Language bindings', href: '/getting-started/#bindings' },
				{ label: 'Kafka connector', href: componentHref(v, 'kafka') },
				{ label: 'Compatibility', href: `/docs/${v}/compatibility` },
			].filter((link) => link.href),
		},
		{ id: 'blog', label: 'Blog', href: '/blog' },
		{
			id: 'company',
			label: 'Company',
			links: [
				{ label: 'About TidesDB Corp.', href: '/company/about-tidesdb-corp' },
				{ label: 'Licensing', href: '/licensing' },
				{ label: 'Support', href: '/support' },
				{ label: 'Partners', href: '/partners' },
				{ label: 'Sponsors', href: '/sponsors' },
			],
		},
	];
}
