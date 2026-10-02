# Tool brand icons · Keynest 0.7

These are local build assets for identifying the user's API services and tools. No runtime image download or favicon lookup is performed. The PNGs contain real brand artwork, not generated marks or generic system symbols. Names and trademarks remain with their respective owners; the collection does not indicate partnership or endorsement.

Sources were retrieved on **2026-09-29**. Newly added images are 256 × 256 RGBA PNGs. PNG and SVG source artwork was proportionally fitted to a transparent square without changing the mark's geometry or colors. The native UI supplies a white background. SVGs from Simple Icons use the exact brand hex color in that repository's pinned metadata. Raster favicon sources may be smaller than 256 pixels; those are resampled for a consistent output canvas and remain intended for small UI sizes.

LobeHub files are pinned to [`329f378cbd1a88f45b60cd096b9111ce16f3ea39`](https://github.com/lobehub/lobe-icons/tree/329f378cbd1a88f45b60cd096b9111ce16f3ea39). Simple Icons files are pinned to [`d4e6ba93e48f178898707f0145ec285f28b64b38`](https://github.com/simple-icons/simple-icons/tree/d4e6ba93e48f178898707f0145ec285f28b64b38). Slow GitHub raw downloads were fetched from the same fixed-commit jsDelivr mirror; every repository file was checked against the Git blob SHA-1 from the official repository tree, as well as recording SHA-256. There is no unpinned CDN URL in the app.

The complete build manifest is [`brand-icon-manifest.json`](../../scripts/brand-icon-manifest.json), including original URL, optional mirror, upstream Git object hash, downloaded-source SHA-256 and final PNG SHA-256. [`SHA256SUMS`](SHA256SUMS) covers all final PNGs in this directory. Vendor-hosted URLs are recorded with source hashes; a future source change causes the acquisition script to stop instead of silently accepting different artwork.

There are **15 tool PNGs**. Generic Skill templates intentionally have no invented brand mark and can show a combination of the API providers they use. Claude Code and OpenClaw have their own LobeHub brand artwork.

## Sources

| Local PNG | Upstream asset | Collection license or source status | Official source page / notes |
| --- | --- | --- | --- |
| `cursor.png` | [Source](https://raw.githubusercontent.com/lobehub/lobe-icons/329f378cbd1a88f45b60cd096b9111ce16f3ea39/packages/static-png/light/cursor.png) | MIT (LobeHub) | Fixed repository commit; original brand colors. |
| `cline.png` | [Source](https://raw.githubusercontent.com/lobehub/lobe-icons/329f378cbd1a88f45b60cd096b9111ce16f3ea39/packages/static-png/light/cline.png) | MIT (LobeHub) | Fixed repository commit; original brand colors. |
| `roo-code.png` | [Source](https://raw.githubusercontent.com/lobehub/lobe-icons/329f378cbd1a88f45b60cd096b9111ce16f3ea39/packages/static-png/light/roocode.png) | MIT (LobeHub) | Fixed repository commit; original brand colors. |
| `opencode.png` | [Source](https://raw.githubusercontent.com/lobehub/lobe-icons/329f378cbd1a88f45b60cd096b9111ce16f3ea39/packages/static-png/light/opencode.png) | MIT (LobeHub) | Fixed repository commit; original brand colors. |
| `claude-code.png` | [Source](https://raw.githubusercontent.com/lobehub/lobe-icons/329f378cbd1a88f45b60cd096b9111ce16f3ea39/packages/static-png/light/claudecode-color.png) | MIT (LobeHub) | Fixed repository commit; original brand colors. |
| `dify.png` | [Source](https://raw.githubusercontent.com/lobehub/lobe-icons/329f378cbd1a88f45b60cd096b9111ce16f3ea39/packages/static-png/light/dify-color.png) | MIT (LobeHub) | Fixed repository commit; original brand colors. |
| `n8n.png` | [Source](https://raw.githubusercontent.com/lobehub/lobe-icons/329f378cbd1a88f45b60cd096b9111ce16f3ea39/packages/static-png/light/n8n-color.png) | MIT (LobeHub) | Fixed repository commit; original brand colors. |
| `langgraph.png` | [Source](https://raw.githubusercontent.com/lobehub/lobe-icons/329f378cbd1a88f45b60cd096b9111ce16f3ea39/packages/static-png/light/langgraph-color.png) | MIT (LobeHub) | Fixed repository commit; original brand colors. |
| `crewai.png` | [Source](https://raw.githubusercontent.com/lobehub/lobe-icons/329f378cbd1a88f45b60cd096b9111ce16f3ea39/packages/static-png/light/crewai-color.png) | MIT (LobeHub) | Fixed repository commit; original brand colors. |
| `open-webui.png` | [Source](https://raw.githubusercontent.com/lobehub/lobe-icons/329f378cbd1a88f45b60cd096b9111ce16f3ea39/packages/static-png/light/openwebui.png) | MIT (LobeHub) | Fixed repository commit; original brand colors. |
| `cherry-studio.png` | [Source](https://raw.githubusercontent.com/lobehub/lobe-icons/329f378cbd1a88f45b60cd096b9111ce16f3ea39/packages/static-png/light/cherrystudio-color.png) | MIT (LobeHub) | Fixed repository commit; original brand colors. |
| `openclaw.png` | [Source](https://raw.githubusercontent.com/lobehub/lobe-icons/329f378cbd1a88f45b60cd096b9111ce16f3ea39/packages/static-png/light/openclaw-color.png) | MIT (LobeHub) | Fixed repository commit; original brand colors. |
| `continue.png` | [Source](https://www.continue.dev/favicon.png) | Vendor trademark asset; no separate open-source license asserted | [Official page](https://www.continue.dev) |
| `flowise.png` | [Source](https://raw.githubusercontent.com/FlowiseAI/Flowise/9291856d1ea4a4ceea9f8fef8ce14f4f6c81e8eb/packages/ui/public/logo512.png) | Official Flowise repository asset (Apache-2.0 repository; trademark retained) | [Official page](https://github.com/FlowiseAI/Flowise/tree/9291856d1ea4a4ceea9f8fef8ce14f4f6c81e8eb) `packages/ui/public/logo512.png`, outside the enterprise directory. |
| `anythingllm.png` | [Source](https://anythingllm.com/images/brand/logo-mark.svg) | Vendor trademark asset; no separate open-source license asserted | [Official page](https://anythingllm.com) |

## Licenses and reproducibility

- LobeHub MIT license: [LICENSE-LOBEHUB.txt](LICENSE-LOBEHUB.txt).
- Flowise repository license: [LICENSE-FLOWISE.md](LICENSE-FLOWISE.md); the PNG is in the public UI directory. The license distinguishes commercial enterprise files from the Apache 2.0 portion.
- Official vendor website/favicon/organization assets: [LICENSE-VENDOR-ASSETS.md](LICENSE-VENDOR-ASSETS.md). These are not relabeled MIT or CC0, and no separate open-source grant is asserted.
- Build-time only: `python3 scripts/acquire-brand-icons.py --download` acquires the curated manifest; without `--download` it only renders cached sources. Requires Python with Pillow and `rsvg-convert`. The normal app build only copies the committed PNG assets and does not need these tools or network access.
- Offline verification: `python3 scripts/verify-brand-icons.py` checks catalogue coverage, PNG signatures, size, every final hash and original-icon preservation, then writes `.build/icon-sources-0.7/brand-contact-sheet.png`. The 61 provider and 15 tool images passed those checks and were visually reviewed on 2026-09-29.
