# nimble colors

Each gradient runs at 45 degrees from the top left corner of its shape to the bottom right corner, unless its row names another direction, and each stop is listed with its offset.

The mark is a square N, 377 units on a side, with stems 89 units wide and a diagonal 144 units thick, so the diagonal is the golden ratio of the stem. Each curve of the fox is an arc of a circle whose radius is a Fibonacci number, from 377 down to 5. The stack sets the wordmark 34 units below the mark, with caps 55 units tall and an 8-unit stroke, and the wordmark spans the full width of the mark. The lockup scales the same wordmark to caps 89 units tall and centers it on the mark, 89 units to its right. The deepest Ember stop keeps 5.55:1 against the navy, above the 3:1 that WCAG asks of graphics.

## On Dark

| Use | Stops |
|---|---|
| Mark | `#FFD54A` at 0, `#FF9F43` at 0.5, `#F25C2B` at 1 |
| Wordmark, left to right | `#FFD54A` at 0, `#FF9F43` at 0.5, `#F25C2B` at 1 |
| Icon tile, top to bottom | `#142029` at 0, `#0A1015` at 1 |

| Use | Color |
|---|---|
| Ground | `#0E151C` |

## On Light

The light files reverse the dark ones: the Ember gradient fills the ground and the icon tile, and the mark and wordmark sit on it in navy.

| Use | Stops |
|---|---|
| Ground and icon tile | `#FFD54A` at 0, `#FF9F43` at 0.5, `#F25C2B` at 1 |

| Use | Color |
|---|---|
| Mark and wordmark | `#0E151C` |

## Mono

A mono file without a ground fills each shape with `currentColor`, so an inline copy takes the color of the text around it. A mono file for a dark ground fills with `#FFFFFF`, and one for a light ground fills with `#0E151C`. The mono files with a ground set the white artwork on `#0E151C`.
