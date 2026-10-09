import { defineCollection, z } from 'astro:content';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

export const collections = {
	docs: defineCollection({
		loader: docsLoader(),
		// Optional author overrides. When omitted, the article's creator is taken
		// from git history (see src/utils/articles.js).
		//
		// Two ways to hold an article back, which do different things:
		//
		//   draft: true     Starlight's own flag. The page renders under
		//                   `astro dev` with a draft notice and is NOT generated
		//                   in a production build, so it has no public URL.
		//   unlisted: true  The page IS built and can be shared by link, but it
		//                   is kept out of /blog, the RSS feed, the /blog/<slug>
		//                   redirects, the sitemap and search, and is marked
		//                   noindex. Use this for a preview link.
		// The transform is how `unlisted` reaches Starlight's own `pagefind` flag.
		// Page.astro indexes a page when `entry.data.pagefind !== false`, and that
		// is read from the parsed frontmatter, so setting it here keeps an unlisted
		// article out of the site search without having to write two lines in every
		// draft's frontmatter.
		schema: (context) =>
			docsSchema({
				extend: z.object({
					author: z.string().optional(),
					authorUrl: z.string().url().optional(),
					unlisted: z.boolean().default(false),
					// Publication date override. Dates normally come from git, where
					// the oldest commit is treated as publication, which is wrong for
					// anything held back as a draft: it would publish carrying the date
					// you started writing and sort below newer posts. Set this on the
					// commit that publishes it.
					date: z.coerce.date().optional(),
				}),
			})(context).transform((data) =>
				data.unlisted ? { ...data, pagefind: false } : data
			),
	}),
};
