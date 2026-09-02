import { defineCollection, z } from 'astro:content';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

export const collections = {
	docs: defineCollection({
		loader: docsLoader(),
		// Optional author overrides. When omitted, the article's creator is taken
		// from git history (see src/utils/articles.js).
		schema: docsSchema({
			extend: z.object({
				author: z.string().optional(),
				authorUrl: z.string().url().optional(),
			}),
		}),
	}),
};
