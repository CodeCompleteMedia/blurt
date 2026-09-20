// Four answers, told apart by letter as well as colour.
//
// The letter is what makes the phone readable for a colourblind student, and
// what lets the projector and the phone refer to the same answer without the
// phone showing any question text. It also gives the room something to say out
// loud — "B" is a word, where a diamond is a description — which matters on a
// blurt, where the answer is spoken.
//
// `color` is the tile's fill: deep enough that white answer text holds 5:1 on
// every one. `rim` is the neon tube around it and the glow it throws.
export const CHOICES = [
  { key: 'A', label: 'Answer A', color: '#d10f5c', rim: '#ff4d8d' },
  { key: 'B', label: 'Answer B', color: '#2446e8', rim: '#5c8bff' },
  { key: 'C', label: 'Answer C', color: '#a65a00', rim: '#ffb020' },
  { key: 'D', label: 'Answer D', color: '#077a4b', rim: '#2dff9a' },
]

export function choiceFor(index) {
  return CHOICES[index % CHOICES.length]
}
