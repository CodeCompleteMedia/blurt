// Four answers, told apart by shape as well as colour — the shape is what makes
// the phone readable for a colourblind student, and what lets the projector and
// the phone refer to the same answer without the phone showing any text.

export const SHAPES = [
  { key: 'triangle', label: 'Triangle', color: '#E0451F' },
  { key: 'diamond', label: 'Diamond', color: '#2A6FD6' },
  { key: 'circle', label: 'Circle', color: '#D99A12' },
  { key: 'square', label: 'Square', color: '#1E9B68' },
]

export function shapeFor(index) {
  return SHAPES[index % SHAPES.length]
}
