# nimble brand assets

The wordmark is Bricolage Grotesque ExtraBold (800), lowercase, with letter-spacing at
-0.035em. The rule sits flush to the baseline at roughly 7% of the type size, running the
full width of the wordmark.

## Files

Every SVG has its type converted to outlines, so no font has to be installed and the
artwork scales to any size.

| File | What it is |
|---|---|
| `nimble-wordmark-on-light.svg` | The ink wordmark, transparent, for light surfaces. |
| `nimble-wordmark-on-dark.svg` | The cream wordmark, transparent, for dark surfaces. |
| `nimble-wordmark-on-light-ground.svg` | The wordmark on paper `#F7F3ED`, with clear space built in. |
| `nimble-wordmark-on-dark-ground.svg` | The wordmark on ink `#14110F`, with clear space built in. |
| `nimble-wordmark-mono-on-light.svg` | The single-colour ink wordmark. |
| `nimble-wordmark-mono-on-dark.svg` | The single-colour cream wordmark. |
| `nimble-wordmark-mono.svg` | The wordmark in `currentColor`, for inline use. |
| `nimble-icon.svg` | The "n" tile at 256x256, with a 22% corner radius. |
| `nimble-icon-on-dark.svg` | The same tile for dark surfaces. |

Each wordmark above also ships as a PNG under the same name. The icon ships as a raster
ladder from `nimble-icon-32.png` to `nimble-icon-1024.png`.

The transparent files carry a viewBox trimmed to the exact ink bounds, so they sit flush in
any layout. Add clear space with padding rather than expecting it inside the file.

## Colours

| Name | Value |
|---|---|
| ink | `#14110F` |
| paper | `#F7F3ED` |
| ember | `#C1440E` |
| fox | `#F26B21` |
| amber | `#F5C05F` |

The rule on dark is `linear-gradient(90deg, #C1440E 0%, #F26B21 55%, #F5C05F 100%)`. The
rule on light is `linear-gradient(90deg, #B3300B 0%, #F26B21 55%, #E9A93F 100%)`.

## Usage

The clear space on all sides is the height of the "n". The minimum wordmark width is 72px,
and the icon replaces the wordmark below that. A mono file is the one to use over
photography or busy colour.
