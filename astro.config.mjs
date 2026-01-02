// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	site: 'https://tidesdb.com',
	integrations: [
		starlight({
			title: 'TidesDB',
			description: 'Fast, embeddable LSM-tree based key-value storage engine library written in C. ACID transactions, great concurrency, cross-platform support.',
			customCss: [
				'./src/styles/custom.css',
			  ],
			components: {
				// Allow custom components to be used in content
			},
			logo: {
				light: './src/assets/tidesdb-logo-v0.1.svg',
				dark: './src/assets/tidesdb-logo-v0.1.svg',
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
					tag: 'link',
					attrs: {
						rel: 'canonical',
						href: 'https://tidesdb.com'
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
					label: 'Getting started',
					items: [
						{ label: 'What is TidesDB?', slug: 'getting-started/what-is-tidesdb' },
						{ label: 'How does TidesDB work?', slug: 'getting-started/how-does-tidesdb-work' },
					],
				},
				{
					label: 'Reference',
					items: [
						{ label: 'Building & Benchmarking', slug: 'reference/building' },
						{ label: 'C API Reference', slug: 'reference/c' },
					],
				},
				{
					label: 'Articles',
					items: [
						{ label: '1GB Value Observations TidesDB 7 & RocksDB 10', slug: 'articles/1gb-values-rocksdb10-tidesdb7' },
						{ label: 'Comparative Analysis of TidesDB v7.0.7 & RocksDB v10.7.5', slug: 'articles/benchmark-analysis-tidesdb-v7-0-7-rocksdb-v10-7-5' },
						{ label: 'Using TidesDB with Java via JExtract', slug: 'articles/using-tidesdb-with-java-via-jextract' },
						{ label: 'Death by a Thousand Cycles - Micro-Optimizations in TidesDB v7.0.4', slug: 'articles/tidesdb704-death-by-a-thousand-cycles' },
						{ label: 'What I Learned Building a Storage Engine That Outperforms RocksDB', slug: 'articles/what-i-learned-building-a-storage-engine-that-outperforms-rocksdb' },
						{ label: 'TidesDB 7 - RocksDB 10.7.5', slug: 'articles/benchmark-analysis-tidesdb7-rocksdb1075' },
						{ label: 'Seek and Range Query Performance · TidesDB v6.1.0 vs RocksDB v10.7.5', slug: 'articles/benchmark-design-range-seek-tidesdb610-rocksdb1075' },
						{ label: 'Design Decisions and Performance Analysis of TidesDB v6.0.1 & RocksDB v10.7.5', slug: 'articles/benchmark-design-analysis-tidesdb601-rocksdb1075' },
						{ label: 'Comparative Analysis of TidesDB v6 & RocksDB v10.7.5', slug: 'articles/benchmark-analysis-tidesdb6-rocksdb1075' },
						{ label: 'TidesDB vs RocksDB: Which Storage Engine is Faster?', slug: 'articles/tidesdb-vs-rocksdb' },
					],
				},
				{
					label: 'YouTube',
					link: 'https://www.youtube.com/@TidesDB',
				},
				{
					label: 'GitHub', link: 'https://github.com/tidesdb',
				},
				{
					label: 'Discord Community', link: 'https://discord.gg/tWEmjR66cy',
				}
			],
		}),
	],
});
