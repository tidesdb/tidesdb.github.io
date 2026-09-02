#!/usr/bin/env node
// Sync versioned documentation into the site repo, from GitHub.
//
// For each `current` distribution in src/config/versions.js this asks every
// component's PUBLIC repository whether it publishes doc/manual.json for the
// TidesDB major it is filed under. That single question decides everything:
//
//   published + right major → its chapters are rendered into the site
//   published + wrong major → a link-out (its pages describe another release)
//   no doc/manual.json      → a link-out to the repository
//   no repository yet       → listed on the compatibility page only, no link
//
// So promoting a component is a push, not a config change: add doc/ to its
// repo, re-run this, and it appears. Nothing here can render docs that only
// exist on the machine running the sync — see scripts/doc-source.mjs.
//
// It writes:
//
//   1. content into src/content/docs/docs/<id>/<namespace>/<slug>.md, with the
//      frontmatter `slug` rewritten so pages land at /docs/<id>/<namespace>/…
//      (core has no namespace; integrations use their id, or <id>/<variant>
//      when an integration ships per-server builds; bindings use
//      bindings/<id>).
//   2. src/config/nav/<id>.json — a committed nav TREE the Sidebar renders:
//      core parts, then each integration, then a "Language bindings" group,
//      plus a leading "Compatibility" link. Alongside it a `components` map
//      records, per component, the TidesDB version it declares support for, its
//      own release, its landing page, and whether its docs were read from a tag
//      or a branch tip — the compatibility page renders that. So the build
//      never needs the component repos.
//
// Everything it writes is GITIGNORED and regenerated on every build (`npm run
// build` and `npm run dev` both run this first). A component's docs live in that
// component's repository and nowhere else, so this repo never carries a second
// copy to drift out of date: pulling is the only way they get here, and a
// release ships the docs that were published when it was built.
//
// The cost is that a build needs network access to GitHub. That is deliberate —
// a build that cannot reach a component's docs fails loudly instead of quietly
// deploying a stale copy of them. Pin components to release tags (rather than
// `tag: null`, which tracks a moving branch tip) to keep builds reproducible.

import { existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CURRENT_VERSIONS } from '../src/config/versions.js';
import { openReader, probeComponent } from './doc-source.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const CONTENT_ROOT = join(ROOT, 'src/content/docs/docs');
const NAV_ROOT = join(ROOT, 'src/config/nav');

/** Leading integer of a version string ('9', '10.0.0'), or null. */
function majorOf(value) {
	const n = parseInt(String(value ?? ''), 10);
	return Number.isFinite(n) ? n : null;
}

/**
 * Force the page's slug to the fully-qualified, namespaced one. The manifest is
 * the authority for slug/order, so a source doc only needs `title` (and ideally
 * `description`) in its frontmatter — if it declares a `slug` we overwrite it,
 * if not we inject one.
 */
function ensureSlug(md, fullSlug) {
	const fm = md.match(/^---\r?\n([\s\S]*?)\r?\n---/);
	if (!fm) throw new Error('source doc has no frontmatter (needs at least a title)');
	const block = fm[1];
	const newBlock = /^slug:\s*.+$/m.test(block)
		? block.replace(/^slug:\s*.+$/m, `slug: ${fullSlug}`)
		: `${block}\nslug: ${fullSlug}`;
	return md.replace(block, newBlock);
}

/**
 * Write one component's chapters into docs/<versionId>/<namespace>/ and return
 * its nav groups (one per manual part). `namespace` is '' for core.
 */
function writeChapters(read, manifest, versionId, namespace) {
	const base = namespace ? `docs/${versionId}/${namespace}` : `docs/${versionId}`;
	const outDir = namespace ? join(CONTENT_ROOT, versionId, namespace) : join(CONTENT_ROOT, versionId);

	const groups = [];
	let pageCount = 0;
	for (const part of manifest.parts) {
		const entries = [];
		for (const chapter of part.chapters) {
			// `dir` may be "" when a file sits directly in doc/ (single-page docs).
			const rel = part.dir ? `${part.dir}/${chapter.file}` : chapter.file;
			const fullSlug = `${base}/${chapter.slug}`;
			const dest = join(outDir, `${chapter.slug}.md`);
			mkdirSync(dirname(dest), { recursive: true });
			writeFileSync(dest, ensureSlug(read(rel), fullSlug));
			pageCount++;
			entries.push({ kind: 'page', title: chapter.title, slug: fullSlug });
		}
		if (entries.length === 1) {
			// Single-page part → a direct link (the heading IS the page); no
			// one-item dropdown.
			groups.push({ kind: 'page', title: part.title, slug: entries[0].slug });
		} else {
			groups.push({ kind: 'group', label: part.title, entries });
		}
	}
	return { groups, pageCount };
}

/** Collapse a component's parts into one nav node labelled by the component. */
function collapse(label, nodes) {
	// Whole component is a single page → a direct link labelled by the component
	// (no one-item dropdown).
	if (nodes.length === 1 && nodes[0].kind === 'page') {
		return { kind: 'page', title: label, slug: nodes[0].slug };
	}
	// A single multi-chapter part → flatten so it isn't Component > Part.
	if (nodes.length === 1 && nodes[0].kind === 'group') {
		return { kind: 'group', label, entries: nodes[0].entries };
	}
	return { kind: 'group', label, entries: nodes };
}

/** First reachable page/link href under a nav node (its landing page). */
function firstHref(node) {
	if (!node) return null;
	if (node.kind === 'page') return `/${node.slug}/`;
	if (node.kind === 'link') return node.href;
	if (node.kind === 'group') {
		for (const e of node.entries) {
			const h = firstHref(e);
			if (h) return h;
		}
	}
	return null;
}

/**
 * Every component of a distribution as a flat list of slots, in table order.
 * `namespace` decides where its pages land; `id` keys the components map and
 * must match what versions.js `distributionComponents` derives.
 */
function slotsFor(version) {
	const slots = [{ role: 'core', id: 'core', component: version.core, namespace: '' }];
	for (const it of version.integrations ?? []) {
		if (it.variants?.length) {
			for (const variant of it.variants) {
				slots.push({
					role: 'variant',
					parent: it,
					id: `${it.id}-${variant.id}`,
					component: variant,
					namespace: `${it.id}/${variant.id}`,
				});
			}
			continue;
		}
		slots.push({ role: 'integration', id: it.id, component: it, namespace: it.id });
	}
	for (const binding of version.bindings ?? []) {
		slots.push({
			role: 'binding',
			id: binding.id,
			component: binding,
			namespace: `bindings/${binding.id}`,
		});
	}
	return slots;
}

/**
 * Render one probed slot: its nav node (null when there is nothing to link to)
 * and the record the compatibility page reads. Core is exempt from the major
 * check — it defines the major rather than declaring support for one.
 */
function renderSlot(slot, probe, version, major) {
	const { component, namespace, role } = slot;
	const label = component.label ?? 'TidesDB';
	const linkNode = () => ({ kind: 'link', label, href: probe.repoUrl });
	const base = {
		supports: component.tidesdb ?? null,
		version: null,
		source: probe.status,
		ref: probe.ref,
		repo: probe.repoUrl,
		landing: null,
	};

	if (probe.status === 'missing') {
		console.log(`    ${namespace || 'core'} — no repository published yet`);
		// No node: a sidebar entry linking to a 404 is worse than no entry. The
		// component still appears on the compatibility page as announced.
		return { node: null, pageCount: 0, record: { ...base, landing: null } };
	}

	if (probe.status === 'undocumented') {
		console.log(`    ${namespace || 'core'} — repo has no doc/manual.json, linking out`);
		const node = linkNode();
		return { node, pageCount: 0, record: { ...base, landing: firstHref(node) } };
	}

	// To be rendered under a major, a component must SAY it supports that major.
	// Silence is not consent: a manual that declares no `tidesdb` version is
	// linked out rather than filed under whichever major happens to be current,
	// because we would otherwise be making the claim on the component's behalf.
	// Core is exempt — it defines the major rather than declaring support for it.
	const declared = probe.manifest.tidesdb ?? null;
	if (role !== 'core' && majorOf(declared) !== major) {
		const reason = declared
			? `publishes docs for TidesDB ${declared}, not ${major}`
			: 'publishes docs that declare no "tidesdb" version';
		console.log(`    ${namespace} — ${reason}: linking out`);
		const node = linkNode();
		return {
			node,
			pageCount: 0,
			record: {
				...base,
				supports: declared ?? component.tidesdb ?? null,
				source: 'mismatch',
				landing: firstHref(node),
			},
		};
	}

	console.log(`    ${namespace || 'core'} ← ${probe.provenance.describe}`);
	const read = openReader(probe.repo, probe.ref, { immutable: probe.provenance.kind === 'tag' });
	const { groups, pageCount } = writeChapters(read, probe.manifest, version.id, namespace);
	const record = {
		...base,
		// Core IS the distribution, so it reports the major itself.
		supports: role === 'core' ? (version.core.version ?? version.label) : declared,
		version: probe.manifest.version ?? (role === 'core' ? version.label : null),
		source: probe.provenance.kind,
	};
	return { groups, pageCount, record, label };
}

async function syncVersion(version) {
	const major = majorOf(version.label);
	const slots = slotsFor(version);

	// Probe everything BEFORE touching the content directory, so a network
	// failure leaves the previously synced (and committed) docs intact.
	const probes = await Promise.all(slots.map((s) => probeComponent(s.component)));

	const outDir = join(CONTENT_ROOT, version.id);
	rmSync(outDir, { recursive: true, force: true });
	mkdirSync(outDir, { recursive: true });

	const rendered = new Map();
	let pages = 0;
	for (const [i, slot] of slots.entries()) {
		const result = renderSlot(slot, probes[i], version, major);
		pages += result.pageCount;
		rendered.set(slot.id, result);
	}

	const tree = [];
	/** @type {Record<string, any>} */
	const components = {};
	const nodeFor = (id) => {
		const r = rendered.get(id);
		return r.groups ? collapse(r.label, r.groups) : r.node;
	};

	// Compatibility overview (a generated page under src/pages).
	tree.push({ kind: 'page', title: 'Compatibility', slug: `docs/${version.id}/compatibility` });

	// Core manual — parts sit at the top level, expanded by default.
	const core = rendered.get('core');
	if (core.groups) {
		tree.push(...core.groups.map((g) => ({ ...g, open: true })));
		core.record.landing = firstHref(core.groups[0]);
	} else if (core.node) {
		tree.push(core.node);
		core.record.landing = firstHref(core.node);
	}
	components.core = core.record;

	// Integrations — each its own top-level node. An integration with `variants`
	// becomes a parent group holding one child group per variant (TideSQL >
	// MariaDB, TideSQL > MySQL), so no page of one can be read as the other's.
	for (const it of version.integrations ?? []) {
		if (it.variants?.length) {
			const entries = [];
			for (const variant of it.variants) {
				const id = `${it.id}-${variant.id}`;
				const node = nodeFor(id);
				const record = rendered.get(id).record;
				record.landing = firstHref(node);
				components[id] = record;
				if (node) entries.push(variant.open ? { ...node, open: true } : node);
			}
			// Every variant unpublished → no parent group worth showing.
			if (entries.length) tree.push({ kind: 'group', label: it.label, entries });
			continue;
		}
		const node = nodeFor(it.id);
		const record = rendered.get(it.id).record;
		record.landing = firstHref(node);
		components[it.id] = record;
		if (node) tree.push(node);
	}

	// Language bindings — grouped under one collapsible category, below the core
	// manual and the integrations: they are generated API references, not part
	// of the narrative manual.
	const bindingNodes = [];
	for (const b of version.bindings ?? []) {
		const node = nodeFor(b.id);
		const record = rendered.get(b.id).record;
		record.landing = firstHref(node);
		components[b.id] = record;
		if (node) bindingNodes.push(node);
	}
	if (bindingNodes.length) {
		tree.push({ kind: 'group', label: 'Language bindings', entries: bindingNodes });
	}

	mkdirSync(NAV_ROOT, { recursive: true });
	writeFileSync(
		join(NAV_ROOT, `${version.id}.json`),
		JSON.stringify(
			{
				id: version.id,
				label: version.label,
				syncedAt: new Date().toISOString().slice(0, 10),
				tree,
				components,
			},
			null,
			'\t'
		) + '\n'
	);

	const tally = (kind) => Object.values(components).filter((c) => c.source === kind).length;
	console.log(
		`  ${version.id} (${version.label}): ${pages} pages from ${tally('tag') + tally('branch')} ` +
			`published component(s); ${tally('undocumented') + tally('mismatch')} link-out(s), ` +
			`${tally('missing')} not yet published, ${tally('tag')} pinned to a tag`
	);
}

console.log('Syncing versioned docs from GitHub...');
if (!existsSync(CONTENT_ROOT)) mkdirSync(CONTENT_ROOT, { recursive: true });
for (const version of CURRENT_VERSIONS) {
	try {
		await syncVersion(version);
	} catch (err) {
		console.error(`  ${version.id}: FAILED — ${err.message}`);
		process.exitCode = 1;
	}
}
console.log('Done.');
