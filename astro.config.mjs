// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	site: 'https://tidesdb.com',
	integrations: [
		starlight({
			title: 'TidesDB',
			customCss: [
				'./src/styles/custom.css',
			  ],
			logo: {
				light: './src/assets/tidesdb-logo-v0.1-final.png',
				dark: './src/assets/tidesdb-logo-v0.1.svg',
				replacesTitle: true,
			},
			social: {
				github: 'https://github.com/tidesdb/tidesdb',
			},
			sidebar: [
				{
					label: 'Getting started',
					items: [
						{ label: 'What is TidesDB?', slug: 'getting-started/what-is-tidesdb' },
						{ label: 'How does TidesDB work?', slug: 'getting-started/how-does-tidesdb-work' },
					],
				},
				{
				 	label: 'Building TidesDB', slug: 'reference/building' 
				},
				{
					label: 'C Reference', slug: 'reference/c'
				},
				{
					label: 'C++ Reference',slug: 'reference/cpp'
				},
				{
					label: 'GO Reference', slug: 'reference/go'
				},
				{
					label: 'Python Reference',  slug: 'reference/python'
				},
				{
					label: 'Lua Reference', slug: 'reference/lua' 
				},
				{
					label: 'Java Reference',slug: 'reference/java'
				},
				{
					label: 'Rust Reference',slug: 'reference/rust'
				},
				{
					label: 'Zig Reference',slug: 'reference/zig'
				},
				{
					label: 'C# Reference',slug: 'reference/csharp'
				},
				{
					label: 'Node.JS Reference',slug: 'reference/nodejs'
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
