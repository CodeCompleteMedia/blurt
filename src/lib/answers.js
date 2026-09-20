// Four answers, told apart by shape as well as colour — the shape is what makes
// the phone readable for a colourblind student, and what lets the projector and
// the phone refer to the same answer without the phone showing any text.

//
// `color` is the tile's fill: deep enough that white answer text holds 5:1 on
// every one. `rim` is the neon tube around it and the glow it throws.
export const SHAPES = [
  { key: 'triangle', label: 'Triangle', color: '#d10f5c', rim: '#ff4d8d' },
  { key: 'diamond', label: 'Diamond', color: '#2446e8', rim: '#5c8bff' },
  { key: 'circle', label: 'Circle', color: '#a65a00', rim: '#ffb020' },
  { key: 'square', label: 'Square', color: '#077a4b', rim: '#2dff9a' },
]

export function shapeFor(index) {
  return SHAPES[index % SHAPES.length]
}
