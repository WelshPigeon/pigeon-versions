#!/usr/bin/env node
/**
 * Pigeon Studios version registry builder.
 *
 * Reads the hand-edited files in resources/, validates them, and writes the generated files:
 *
 *   api/v2/<slug>.json   what the update checker in each resource reads
 *   registry.json        an index of every resource
 *
 * Usage:
 *   node tools/build.mjs           validate and write the generated files
 *   node tools/build.mjs --check   validate, and fail if any generated file is missing, stale or out of date (CI)
 *
 * Needs Node.js 18 or newer. No dependencies.
 */

import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const RESOURCES_DIR = join(ROOT, 'resources');
const API_DIR = join(ROOT, 'api', 'v2');
const RAW_BASE = 'https://raw.githubusercontent.com/WelshPigeon/pigeon-versions/main';

const SLUG_RE = /^[a-z0-9][a-z0-9-]{1,63}$/;
const SEMVER_RE = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const STATUSES = ['active', 'deprecated', 'discontinued'];
const KINDS = ['free', 'paid'];
const MAX_HIGHLIGHTS = 5;

const errors = [];
const fail = (file, message) => errors.push(`${file}: ${message}`);

// ---------------------------------------------------------------------------
// Semantic versions

function parseSemver(version) {
    const match = SEMVER_RE.exec(version);
    if (!match) return null;
    return {
        major: Number(match[1]),
        minor: Number(match[2]),
        patch: Number(match[3]),
        pre: match[4] ? match[4].split('.') : [],
    };
}

/** Compares two versions by semver precedence: -1, 0 or 1. Build metadata is ignored. */
function compareSemver(a, b) {
    const x = parseSemver(a);
    const y = parseSemver(b);
    for (const key of ['major', 'minor', 'patch']) {
        if (x[key] !== y[key]) return x[key] < y[key] ? -1 : 1;
    }
    if (!x.pre.length || !y.pre.length) {
        if (x.pre.length === y.pre.length) return 0;
        return x.pre.length ? -1 : 1;
    }
    for (let i = 0; i < Math.max(x.pre.length, y.pre.length); i++) {
        const p = x.pre[i];
        const q = y.pre[i];
        if (p === undefined) return -1;
        if (q === undefined) return 1;
        const pNum = /^\d+$/.test(p);
        const qNum = /^\d+$/.test(q);
        if (pNum && qNum) {
            if (Number(p) !== Number(q)) return Number(p) < Number(q) ? -1 : 1;
        } else if (pNum !== qNum) {
            return pNum ? -1 : 1;
        } else if (p !== q) {
            return p < q ? -1 : 1;
        }
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Validation

function isValidDate(value) {
    if (typeof value !== 'string' || !DATE_RE.test(value)) return false;
    const date = new Date(`${value}T00:00:00Z`);
    return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

function isHttpsUrl(value) {
    if (typeof value !== 'string') return false;
    try {
        return new URL(value).protocol === 'https:';
    } catch {
        return false;
    }
}

/** Plain text: trimmed, within the length limit, and free of control characters and FiveM colour codes. */
function isText(value, max) {
    return typeof value === 'string' && value.trim() === value && value.length > 0 && value.length <= max && !/[\u0000-\u001f\u007f^]/.test(value);
}

function checkKeys(file, where, object, allowed) {
    for (const key of Object.keys(object)) {
        if (!allowed.includes(key)) fail(file, `${where}: unknown field "${key}"`);
    }
    for (const key of allowed) {
        if (!(key in object) && key !== '$schema') fail(file, `${where}: missing field "${key}"`);
    }
}

function validateResource(file, data, expectedSlug) {
    if (typeof data !== 'object' || data === null || Array.isArray(data)) {
        fail(file, 'must be a JSON object');
        return false;
    }
    const before = errors.length;

    checkKeys(file, 'resource', data, ['$schema', 'slug', 'name', 'kind', 'status', 'notice', 'links', 'minimum_version', 'releases']);

    if (!SLUG_RE.test(data.slug ?? '')) fail(file, 'slug must be 2–64 lowercase letters, numbers and hyphens');
    else if (data.slug !== expectedSlug) fail(file, `slug "${data.slug}" must match the file name "${expectedSlug}"`);
    if (!isText(data.name, 60)) fail(file, 'name must be 1–60 characters with no control characters or "^"');
    if (!KINDS.includes(data.kind)) fail(file, `kind must be one of: ${KINDS.join(', ')}`);
    if (!STATUSES.includes(data.status)) fail(file, `status must be one of: ${STATUSES.join(', ')}`);
    if (data.notice !== null && !isText(data.notice, 200)) fail(file, 'notice must be null or 1–200 characters');
    if (data.status !== 'active' && data.notice === null) fail(file, `a ${data.status} resource needs a notice telling owners what to do`);

    if (typeof data.links !== 'object' || data.links === null || Array.isArray(data.links)) {
        fail(file, 'links must be an object');
    } else {
        checkKeys(file, 'links', data.links, ['repository', 'store', 'support']);
        for (const key of ['repository', 'store']) {
            if (data.links[key] !== null && !isHttpsUrl(data.links[key])) fail(file, `links.${key} must be null or an https URL`);
        }
        if (!isHttpsUrl(data.links.support)) fail(file, 'links.support must be an https URL');
        if (data.kind === 'paid' && data.links.store === null) fail(file, 'a paid resource needs links.store');
    }

    if (data.minimum_version !== null && !SEMVER_RE.test(data.minimum_version ?? '')) fail(file, 'minimum_version must be null or a semantic version');

    if (!Array.isArray(data.releases) || data.releases.length === 0) {
        fail(file, 'releases must list at least one release, newest first');
        return false;
    }

    data.releases.forEach((release, i) => {
        const where = `releases[${i}]`;
        if (typeof release !== 'object' || release === null || Array.isArray(release)) return fail(file, `${where} must be an object`);
        checkKeys(file, where, release, ['version', 'date', 'title', 'security', 'url', 'notes']);
        if (!SEMVER_RE.test(release.version ?? '')) fail(file, `${where}.version must be a semantic version without a "v", such as 1.2.0`);
        if (!isValidDate(release.date)) fail(file, `${where}.date must be a real date in YYYY-MM-DD format`);
        if (!isText(release.title, 100)) fail(file, `${where}.title must be 1–100 characters with no control characters or "^"`);
        if (typeof release.security !== 'boolean') fail(file, `${where}.security must be true or false`);
        if (release.url !== null && !isHttpsUrl(release.url)) fail(file, `${where}.url must be null or an https URL`);
        if (!Array.isArray(release.notes) || release.notes.length === 0 || release.notes.length > 30) fail(file, `${where}.notes must list 1–30 changes`);
        else release.notes.forEach((note, n) => {
            if (!isText(note, 200)) fail(file, `${where}.notes[${n}] must be 1–200 characters with no control characters or "^"`);
        });
    });

    for (let i = 1; i < data.releases.length; i++) {
        const newer = data.releases[i - 1];
        const older = data.releases[i];
        if (SEMVER_RE.test(newer?.version) && SEMVER_RE.test(older?.version) && compareSemver(newer.version, older.version) <= 0) {
            fail(file, `releases must be newest first with no duplicates: ${newer.version} is listed before ${older.version}`);
        }
        if (isValidDate(newer?.date) && isValidDate(older?.date) && newer.date < older.date) {
            fail(file, `release ${newer.version} is dated before ${older.version}`);
        }
    }

    const latest = data.releases[0];
    if (data.minimum_version && SEMVER_RE.test(data.minimum_version) && SEMVER_RE.test(latest?.version) && compareSemver(data.minimum_version, latest.version) > 0) {
        fail(file, `minimum_version ${data.minimum_version} is newer than the latest release ${latest.version}`);
    }

    return errors.length === before;
}

// ---------------------------------------------------------------------------
// Output

const json = (value) => `${JSON.stringify(value, null, 2)}\n`;

function apiDocument(resource) {
    const latest = resource.releases[0];
    return {
        schema: 2,
        slug: resource.slug,
        name: resource.name,
        status: resource.status,
        notice: resource.notice,
        latest: {
            version: latest.version,
            date: latest.date,
            title: latest.title,
            security: latest.security,
            highlights: latest.notes.slice(0, MAX_HIGHLIGHTS),
            url: latest.url,
        },
        minimum_version: resource.minimum_version,
        security_releases: resource.releases.filter((r) => r.security).map((r) => r.version),
        links: {
            download: latest.url ?? resource.links.store ?? resource.links.repository ?? resource.links.support,
            repository: resource.links.repository,
            store: resource.links.store,
            support: resource.links.support,
        },
    };
}

// ---------------------------------------------------------------------------
// Build

const resources = [];
const files = existsSync(RESOURCES_DIR) ? readdirSync(RESOURCES_DIR).sort() : [];
for (const name of files) {
    const file = `resources/${name}`;
    if (name === '.gitkeep') continue;
    if (!name.endsWith('.json')) {
        fail(file, 'only .json files belong in resources/');
        continue;
    }
    let data;
    try {
        data = JSON.parse(readFileSync(join(RESOURCES_DIR, name), 'utf8'));
    } catch (error) {
        fail(file, `isn't valid JSON: ${error.message}`);
        continue;
    }
    if (validateResource(file, data, name.slice(0, -5))) resources.push(data);
}

if (errors.length) {
    console.error(`\n✖ ${errors.length} problem${errors.length === 1 ? '' : 's'} found:\n`);
    for (const error of errors) console.error(`  • ${error}`);
    console.error('');
    process.exit(1);
}

const expected = new Map();
for (const resource of resources) {
    expected.set(`api/v2/${resource.slug}.json`, json(apiDocument(resource)));
}
expected.set('registry.json', json({
    schema: 2,
    brand: 'Pigeon Studios',
    updated: resources.map((r) => r.releases[0].date).sort().at(-1) ?? null,
    api: `${RAW_BASE}/api/v2/{slug}.json`,
    resources: Object.fromEntries(resources.map((r) => [r.slug, {
        name: r.name,
        kind: r.kind,
        status: r.status,
        version: r.releases[0].version,
        date: r.releases[0].date,
        security: r.releases[0].security,
        api: `api/v2/${r.slug}.json`,
    }])),
}));

const stale = existsSync(API_DIR)
    ? readdirSync(API_DIR).filter((name) => name !== '.gitkeep' && !expected.has(`api/v2/${name}`)).map((name) => `api/v2/${name}`)
    : [];

const checkOnly = process.argv.includes('--check');
const changed = [];
for (const [file, content] of expected) {
    const path = join(ROOT, file);
    const current = existsSync(path) ? readFileSync(path, 'utf8').replace(/\r\n/g, '\n') : null;
    if (current === content) continue;
    changed.push(file);
    if (!checkOnly) {
        mkdirSync(dirname(path), { recursive: true });
        writeFileSync(path, content);
    }
}

const summary = `${resources.length} resource${resources.length === 1 ? '' : 's'}`;
if (checkOnly) {
    if (changed.length || stale.length) {
        console.error('\n✖ Generated files are out of date. Run "node tools/build.mjs" and commit the result.\n');
        for (const file of changed) console.error(`  • needs regenerating: ${file}`);
        for (const file of stale) console.error(`  • should be deleted: ${file}`);
        console.error('');
        process.exit(1);
    }
    console.log(`✔ ${summary} valid; every generated file is up to date.`);
} else {
    console.log(`✔ ${summary} valid. ${changed.length} file${changed.length === 1 ? '' : 's'} written.`);
    for (const file of changed) console.log(`  • ${file}`);
    if (stale.length) {
        console.log('\n! These files no longer belong to any resource. Delete them before committing:');
        for (const file of stale) console.log(`  • ${file}`);
    }
}
