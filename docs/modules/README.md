# Health modules — initial interface

The native and web clients now separate the health overview from choosing a data
source. The Oura connector is **included in the current build**, disabled by
default, and requires explicit activation. Existing recorded history remains
visible when it is disabled.

On iOS the preference gates pairing, manual/automatic sync and factory reset in
`RingSync`, and disabling it pauses an active connection. The web preference gates
the dashboard's ring controls in that browser. It does **not** disable the
standalone CLI, its local server endpoints, or another browser session. It is a
user preference, not authentication or a sandbox.

## Importing a manifest

Open **Ajustes → Módulos → Importar manifiesto**, then select
[`example-manifest.json`](example-manifest.json) or another local JSON file.
Both clients support the same schema, size and identity limits:

- Exact fields: `schemaVersion`, `id`, `name`, `version`, `author`, `description`,
  `permissions`. Version 1 only; no extra executable or URL fields.
- Up to 64 KiB per file and 20 stored manifests. Unique ID, semantic version of
  the form `1.0.0`, bounded plain text, no control characters.
- Known permissions: `bluetooth`, `health-read`, `health-write`, `network`,
  `local-storage`. The built-in ID `org.openhealth.oura` is reserved.

Imported manifests are **inert metadata for inspection**. They do not install,
execute or connect a third-party adapter, and declaring a permission does not
grant it. An imported `network` declaration is displayed explicitly. There are no
remote catalog requests, code downloads, or automatic updates in this flow.

This first redesign provides the source-selection interface and a documented
manifest format. A separately distributed Oura adapter, a runtime adapter API,
signature verification and permission isolation are future implementation work.
The current build still includes Oura integration code; importing a manifest does
not remove that dependency or change the provenance/license of bundled models.

## Appearance and data

Both clients offer System, Light and Dark preferences. The dark palette uses a
pure-black canvas. Home uses red, Ring a deeper sensor green, and Settings a
red/green combination with a copper tint. Interface text is English. Native navigation is the standard
SwiftUI `TabView`, with system Liquid Glass on iOS 26, minimization on scroll,
and platform accessibility behavior. Native home uses a grouped list; Settings
and Ring use forms. Web keeps backdrop filters on navigation, with solid fallbacks,
and follows reduced transparency/motion preferences. The illuminated ring uses
the user-supplied photograph with an AI-cleaned transparent cutout; it does not
indicate a live SpO₂ measurement. The overview uses an existing sleep score
or sleep efficiency, never an invented readiness score. No demo health measurements
are bundled into the application. See [asset and generation prompt](../design/ring-product.md).

## Distribution and legal scope

No personal `oura.db` is included by either Xcode spec. The local simulator build
scripts require `HEALTH_INCLUDE_PERSONAL_DATA=1` to include a developer's database;
never distribute that development artifact.

Modular packaging, open-source licensing and nonprofit intent are not a legal
clearance. Reverse-engineering exceptions depend on jurisdiction and conditions;
for example, [EU Directive 2009/24/EC, Article 6](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32009L0024)
places conditions on decompilation for interoperability. This example is not a
legal assessment of this app in Chile or any distribution market. Review code,
model and firmware provenance, licenses and branding before distribution.

See the [focused source security review](../security-review-2026-10-21.md) for
verified fixes, remaining trust boundaries and validation limits.
