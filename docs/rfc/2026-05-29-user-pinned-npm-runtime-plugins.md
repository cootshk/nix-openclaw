# RFC: User-Pinned npm Runtime Plugins

- Date: 2026-05-29
- Status: Draft
- Audience: OpenClaw and nix-openclaw maintainers

## Executive Model

OpenClaw supports npm runtime plugins through `openclaw plugins install
npm:<package>`. That flow is mutable: it can resolve registry metadata, install
dependencies, write install records, and restart the gateway.

nix-openclaw should support the same class of plugin without copying that
lifecycle. In Nix mode, arbitrary npm support means:

1. the user chooses the package;
2. the user pins the exact package version and artifact hashes;
3. nix-openclaw calls an approved Nix builder from those data-only pins;
4. Nix builds an immutable plugin root;
5. nix-openclaw renders normal OpenClaw config pointing at that root.

The package choice can be arbitrary. The build inputs cannot be arbitrary at
evaluation, build, activation, or runtime.

## Decision

Extend `programs.openclaw.runtimePlugins` from `listOf str` to a list of runtime
plugin selectors:

- string: curated nix-openclaw runtime plugin id;
- attrset: user-pinned npm runtime plugin source.

Curated strings keep their current meaning:

```nix
programs.openclaw.runtimePlugins = [
  "slack"
];
```

Maintainer model: strings select curated package roots; npm attrsets are pinned
source facts; only nix-openclaw calls the builder; generated OpenClaw config
still stays load paths plus enabled entries.

User-pinned npm plugins use a data-only selector:

```nix
programs.openclaw.runtimePlugins = [
  {
    id = "acme-calendar";
    source = {
      kind = "npm";
      packageName = "@acme/openclaw-calendar";
      version = "1.2.3";
      npmIntegrity = "sha512-...";
      nixHash = "sha256-...";
    };
  }
];

programs.openclaw.config.plugins.entries.acme-calendar.config = {
  calendarId = "primary";
};
```

The module, not the user, calls:

```nix
pkgs.openclawPackages.buildRuntimePluginFromNpm {
  id = "acme-calendar";
  packageName = "@acme/openclaw-calendar";
  version = "1.2.3";
  npmIntegrity = "sha512-...";
  nixHash = "sha256-...";
}
```

That builder returns the immutable plugin root and exposes internal
`passthru.openclawRuntimePlugin` metadata. The module only consumes that
metadata from packages it builds from the selector. Users do not pass arbitrary
derivations as selectors in this RFC.

## Why This Is The Nix Boundary

`runtimePlugins = [ "npm:@acme/openclaw-calendar" ]` looks convenient, but it
is the wrong boundary. A string npm spec cannot carry the Nix fixed-output hash, npm
integrity, dependency policy, or package-specific builder decisions that make
the result reproducible.

Arbitrary derivation selectors are also the wrong first boundary. A derivation
can attach forgeable `passthru` metadata after doing anything during its own
build, including package-manager resolution or lifecycle scripts. Nix cannot
prove builder provenance from `passthru`.

The enforceable boundary is a data-only selector that nix-openclaw normalizes by
calling the approved builder. The user controls the package facts. nix-openclaw
controls how those facts become a plugin root.

Raw `plugins.load.paths` is not enough because it bypasses the invariants
nix-openclaw already owns for `runtimePlugins`: enabled entries, restrictive
allowlist merging, duplicate id checks, deny/disabled contradictions, collision
checks with nix-openclaw plugins, and one supported source of generated load
paths. Users can still own raw OpenClaw config directly, but that is outside the
supported `runtimePlugins` lane.

A separate `runtimePluginSources` attrset is worse for this slice. It makes
users declare source and selection separately even though one selector can carry
the plugin id and source facts. If a future UI needs a named source registry,
that can be added later without making the first API larger.

## Scope

This RFC supports user-supplied npm packages when the package can be built into
a plugin root by the generic nix-openclaw npm builder.

The first arbitrary-npm builder supports:

- exact package name and version;
- exact npm tarball integrity;
- exact Nix fixed-output hash;
- complete tarballs with no runtime dependencies;
- complete tarballs with bundled runtime dependencies.

Bundled means the published tarball is self-contained for runtime: every
runtime dependency import resolves from files inside the tarball after unpack,
without package-manager install or rebuild.

Packages with unbundled runtime dependencies are not in the first
implementation. They need a user-owned dependency lock schema. The
official-plugin dependency materialization RFC proves the builder shape, but it
does not define the arbitrary user lock format.

This RFC does not support:

- `latest`, dist-tags, semver ranges, or npm aliases;
- npm registry resolution during user builds;
- npm, pnpm, yarn, or corepack during activation or runtime;
- lifecycle scripts in the generic builder;
- native rebuilds in the generic builder;
- mutable OpenClaw install records;
- ClawHub package discovery or ClawHub security verdicts;
- unbundled dependency-bearing npm packages until the user-owned dependency
  lock schema exists;
- git/path/local plugin sources;
- user-supplied runtime plugin derivations.

Those source classes need separate RFCs if they become worth supporting.

## User API

Top-level and per-instance semantics stay the same. Instance-level
`runtimePlugins` replaces the top-level list for that instance.

Good:

```nix
programs.openclaw.runtimePlugins = [
  "slack"
  {
    id = "acme-calendar";
    source = {
      kind = "npm";
      packageName = "@acme/openclaw-calendar";
      version = "1.2.3";
      npmIntegrity = "sha512-...";
      nixHash = "sha256-...";
    };
  }
];
```

Future only, after the user-owned dependency-lock schema exists:

```nix
programs.openclaw.runtimePlugins = [
  {
    id = "acme-memory";
    source = {
      kind = "npm";
      packageName = "@acme/openclaw-memory";
      version = "2.0.0";
      npmIntegrity = "sha512-...";
      nixHash = "sha256-...";
      dependencyLock = ./acme-memory-dependencies.nix;
    };
  }
];
```

Bad:

```nix
programs.openclaw.runtimePlugins = [
  "npm:@acme/openclaw-calendar@1.2.3"
];
```

Bad:

```nix
programs.openclaw.customPlugins = [
  { source = "npm:@acme/openclaw-calendar"; }
];
```

Bad:

```bash
openclaw plugins install npm:@acme/openclaw-calendar
openclaw plugins install @acme/openclaw-calendar
```

Bad:

```nix
programs.openclaw.runtimePlugins = [
  (pkgs.callPackage ./my-runtime-plugin.nix { })
];
```

## Builder Contract

`pkgs.openclawPackages.buildRuntimePluginFromNpm` takes a pinned npm package and
returns an immutable OpenClaw runtime plugin root. `pkgs.openclaw` remains the
product package; it should not become a builder namespace.

Required selector fields:

- `id`;
- `source.kind = "npm"`;
- `source.packageName`;
- `source.version`;
- `source.npmIntegrity`;
- `source.nixHash`.

The first builder supports only the public npm registry. It constructs the
tarball URL from `packageName` and `version` using the canonical
`registry.npmjs.org` tarball shape. It must not query the npm packument, resolve
dist-tags, or run `npm view`/`npm pack` to discover the tarball.

Optional fields:

- `source.dependencyLock`, only after the user-owned arbitrary dependency lock
  schema is defined. Before that schema exists, the module rejects this field.

The selector schema is closed. Unknown fields are errors. The string fields
`id`, `source.packageName`, `source.version`, `source.npmIntegrity`, and
`source.nixHash` must be plain strings with empty `builtins.getContext` before the
module calls the builder. The module validates plugin id, npm package name,
version, npm integrity, and Nix fixed-output hash grammar first, then
constructs the builder derivation.

The generic builder must:

1. fetch the exact npm tarball as a fixed-output derivation;
2. validate npm integrity;
3. reject unsafe tar members and escaping symlinks;
4. validate `package.json` name/version;
5. validate `openclaw.plugin.json` exists and has the expected id;
6. validate runtime entry files exist;
7. validate OpenClaw compatibility metadata against the packaged OpenClaw;
8. reject runtime dependencies unless they are bundled;
9. reject lifecycle scripts in the generic path;
10. expose internal `passthru.openclawRuntimePlugin` for module normalization.

The module must reject a selector when:

- a value is neither a curated string id nor a supported attrset selector;
- an attrset selector has `source.kind` other than `"npm"`;
- an attrset selector is missing any required pin field;
- any selector string carries Nix string context;
- an attrset selector has unknown fields;
- a V1 attrset selector sets `source.dependencyLock`;
- two selectors resolve to the same plugin id;
- a user-pinned npm selector id matches a curated runtime plugin id, even when
  the curated string is not selected;
- the selected id collides with a nix-openclaw plugin id;
- the selected id is disabled or denied in raw OpenClaw config;
- `config.plugins.installs` is non-empty in the same instance;
- raw `plugins.load.paths` is mixed with `runtimePlugins` in the same instance.

These are evaluation-time errors, not runtime warnings.

## Dependency Lock Ownership

For user-pinned npm plugins, the user owns the package choice and root artifact
update.

nix-openclaw owns the builder contract and validation. It does not vouch for the
plugin author, service behavior, or transitive dependency trustworthiness.

Unbundled dependency-bearing arbitrary npm support needs a later schema. That
schema must be a reviewed repo file or flake input, not a file generated during
activation or build. It must record exact dependency tarball URLs, npm
integrity, Nix fixed-output hashes, allowed URL schemes and hosts, package names
and versions, lifecycle policy, and native rebuild policy. It must reject
`workspace:`, `file:`, `link:` and `git:` runtime dependency specs in the
generic path.

Until that schema exists, a package with unbundled runtime dependencies fails
with a message explaining that the package is not reproducible under this source
class yet.

## OpenClaw Runtime Contract

nix-openclaw still renders upstream OpenClaw config:

```json
{
  "plugins": {
    "load": {
      "paths": ["/nix/store/...-openclaw-runtime-plugin-acme-calendar"]
    },
    "entries": {
      "acme-calendar": { "enabled": true }
    }
  }
}
```

Runtime settings stay under the upstream OpenClaw config shape for that plugin.
For a generic plugin entry this is usually:

```nix
programs.openclaw.config.plugins.entries.acme-calendar.config = {
  calendarId = "primary";
};
```

For a channel plugin, upstream may instead use `channels.<channel-id>`:

```nix
programs.openclaw.config.channels.acme-calendar.enabled = true;
```

Do not add package-specific runtime config under the selector. The selector
chooses code; OpenClaw config configures behavior.

The selector `id`, `openclaw.plugin.json.id`, and generated
`plugins.entries.<id>` key are the same OpenClaw plugin id. Channel config uses
the upstream channel id, which may differ from the plugin id.

## Persisted Registry Boundary

The generated Nix config is the source of truth for selected runtime plugins.
Mutable OpenClaw install records must not participate in this lane.

That means implementation needs one of these before shipping user-pinned npm
support:

- OpenClaw treats `OPENCLAW_NIX_MODE=1` plus config-origin runtime plugin load
  paths as a Nix-owned plugin source and ignores install records from both
  persisted registry state and config-authored `plugins.installs` for
  Nix-selected plugin ids; or
- nix-openclaw sets `OPENCLAW_DISABLE_PERSISTED_PLUGIN_REGISTRY=1` for managed
  gateway processes that use `runtimePlugins`, until upstream has a
  non-breakglass Nix-mode policy, and nix-openclaw rejects
  `config.plugins.installs` when `runtimePlugins` is non-empty.

This is not about writing install records; those are already rejected. It is
about stale existing `$OPENCLAW_STATE_DIR/plugins/installs.json` records. A stale
mutable npm install must not enable, shadow, or satisfy a Nix-selected runtime
plugin.

`preferPersisted = false` by itself is not a sufficient proof if OpenClaw still
feeds install records into derived discovery. The shipping proof must cover both
state-file install records and config-origin `plugins.installs`.

## User-Facing Documentation

The README should keep one OpenClaw runtime plugin install section.

After this RFC is implemented, add a short "Advanced: pinned npm runtime
plugins" subsection:

```nix
programs.openclaw.runtimePlugins = [
  {
    id = "my-plugin";
    source = {
      kind = "npm";
      packageName = "@me/openclaw-plugin";
      version = "1.0.0";
      npmIntegrity = "sha512-...";
      nixHash = "sha256-...";
    };
  }
];
```

The docs must say:

- this is for advanced users who are willing to pin and review package inputs;
- floating npm specs are not supported;
- `openclaw plugins install` is not part of the Nix workflow;
- runtime config still uses upstream OpenClaw config;
- `runtimePlugins = [ "npm:..." ]`, `customPlugins.source = "npm:..."`, and
  `openclaw plugins install ...` are the wrong paths in Nix mode;
- derivation selectors are also rejected; use the pinned attrset selector.

## Proof Gates

Evaluation tests:

- strings still resolve from `pkgs.openclawRuntimePlugins`;
- user-pinned npm attrsets call `pkgs.openclawPackages.buildRuntimePluginFromNpm`;
- derivation selectors fail;
- selector strings with Nix string context fail;
- unknown selector fields fail;
- `source.dependencyLock` fails until the user-owned lock schema exists;
- mixed curated strings and user-pinned npm selectors render load paths and
  enabled entries;
- duplicate ids across strings and attrsets fail;
- a user selector with a curated id such as `slack` fails;
- missing required pin fields fail;
- existing denied, disabled, collision, and raw-load-path checks still fail;
- `config.plugins.installs` with `runtimePlugins` fails;
- generated config contains no `plugins.installs`.

Builder tests:

- exact no-dependency fixture builds;
- exact bundled-dependency fixture builds;
- unbundled dependency-bearing fixture fails until the user-owned lock schema
  exists;
- package name mismatch fails;
- manifest id mismatch fails;
- npm integrity mismatch fails;
- unsafe tar members fail;
- lifecycle-script fixture proves scripts do not run;
- no package manager executable is invoked by the generic builder.

Runtime smoke:

- seed `$OPENCLAW_STATE_DIR/plugins/installs.json` with a stale npm install for
  the same plugin id and prove it is ignored or rejected in Nix mode;
- seed rendered config with a forged `plugins.installs.<id>` record and prove
  Home Manager evaluation fails before runtime;
- `openclaw plugins list --json` sees the selected user plugin id;
- `openclaw plugins inspect <id> --runtime --json` sees runtime registrations;
- the same user-pinned selector works in top-level and per-instance config;
- activation and runtime do not write
  `$OPENCLAW_STATE_DIR/plugins/installs.json`.

Docs gate:

- README examples show attrset-based pinning, not npm spec strings;
- README shows the bad anti-patterns explicitly;
- README does not imply nix-openclaw audits arbitrary third-party plugin code.

## Implementation Order

1. Export `pkgs.openclawPackages.buildRuntimePluginFromNpm`.
2. Extend the `runtimePlugins` option type to accept curated string ids or
   user-pinned npm attrset selectors.
3. Normalize selectors into `{ id, package, loadPath = package, source }`
   before current duplicate, deny, disable, collision, and load-path checks.
4. Add generic builder validation for complete tarballs.
5. Add the persisted-registry guard or upstream Nix-mode registry-read policy.
6. Keep unbundled dependency-bearing arbitrary npm packages rejected until the
   user-owned dependency lock schema exists.
7. Add README advanced examples only after the full proof gate passes.

## Rejected Designs

### Put npm Specs Directly In `runtimePlugins`

Rejected. A spec string is not enough information to build reproducibly in Nix.
It either becomes a fake shorthand for mutable registry resolution or requires
hidden lock state somewhere else.

### Accept User-Supplied Derivations

Rejected for this source class. A derivation can attach plausible
`passthru.openclawRuntimePlugin` metadata after running arbitrary build logic.
That is fine for user-owned raw Nix, but it cannot be the supported arbitrary
npm path if nix-openclaw is promising no package-manager resolution, lifecycle
scripts, or hidden lock generation.

### Add `programs.openclaw.runtimePluginSources`

Rejected for the first arbitrary-npm slice. A second registry map makes users
declare source and selection separately:

```nix
programs.openclaw.runtimePluginSources.acme-calendar = { ... };
programs.openclaw.runtimePlugins = [ "acme-calendar" ];
```

One selector already contains the source facts and plugin id. The normalized
selector model still gives the module one place to enforce duplicates,
allowlist merging, deny/disabled contradictions, and load-path ownership.

### Use Raw `plugins.load.paths`

Rejected as the supported arbitrary-npm path. Raw load paths are the upstream
escape hatch. They do not give nix-openclaw a place to validate builder inputs,
enforce id collisions, merge restrictive allowlists, or reject contradictory
Nix-managed selections.

### Reuse `customPlugins`

Rejected. `customPlugins` is the nix-openclaw plugin mechanism for tools and
skills. OpenClaw runtime plugins should stay on the `runtimePlugins` path so
OpenClaw receives normal `plugins.load.paths` and `plugins.entries` config.

### Run npm During Home Manager Activation

Rejected. Activation-time package installation is mutable state, not a
declarative Nix result.

### Generate Lock Files During Build

Rejected. Build-time lock generation would hide the dependency decision inside
the build. The dependency lock must be an input, not an output.

## Open Questions

- Should nix-openclaw provide a lock-generation helper command later, or should
  users author dependency locks through ordinary Nix tooling?
- Should git/path/local runtime plugin sources reuse the same attrset selector
  shape in a later RFC?

These questions do not change the main boundary: arbitrary npm support is a
user-pinned selector normalized by nix-openclaw, not a mutable npm install.
