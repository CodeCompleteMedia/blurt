// Shrinks a picture before it is uploaded.
//
// A phone photo is four to eight megabytes. The wall shows it at perhaps 1600
// pixels wide, and thirty phones do not show it at all — but the projector's
// laptop has to fetch it over school wifi at the moment the question appears,
// and a question that arrives before its picture is a broken question.

const MAX_EDGE = 1600

export async function shrinkImage(file) {
  if (!file.type.startsWith('image/')) throw new Error('That file is not an image')
  // A GIF may be animated, and drawing it to a canvas would freeze it.
  if (file.type === 'image/gif') {
    if (file.size > 2 * 1024 * 1024) throw new Error('GIFs must be under 2MB')
    return file
  }

  const bitmap = await createImageBitmap(file)
  const scale = Math.min(1, MAX_EDGE / Math.max(bitmap.width, bitmap.height))
  const canvas = document.createElement('canvas')
  canvas.width = Math.round(bitmap.width * scale)
  canvas.height = Math.round(bitmap.height * scale)
  canvas.getContext('2d').drawImage(bitmap, 0, 0, canvas.width, canvas.height)
  bitmap.close()

  const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/webp', 0.82))
  if (!blob) throw new Error('Could not read that image')
  return blob
}
