const MAX_EDGE = 1600;
const MAX_BYTES = 2_500_000;

const dataSize = dataUrl => Math.ceil((dataUrl.length - dataUrl.indexOf(',') - 1) * 0.75);

export async function preparePhoto(file) {
  if (!file?.type?.startsWith('image/')) throw new Error('Please choose an image file.');
  if (file.size > 12_000_000) throw new Error('That image is too large. Please choose one under 12 MB.');
  const source = await new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error('We could not read that image.'));
    image.src = URL.createObjectURL(file);
  });
  const scale = Math.min(1, MAX_EDGE / Math.max(source.width, source.height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(1, Math.round(source.width * scale));
  canvas.height = Math.max(1, Math.round(source.height * scale));
  canvas.getContext('2d', { alpha: false }).drawImage(source, 0, 0, canvas.width, canvas.height);
  for (const quality of [0.86, 0.76, 0.66, 0.56]) {
    const output = canvas.toDataURL('image/jpeg', quality);
    if (dataSize(output) <= MAX_BYTES) return output;
  }
  throw new Error('This image is still too large. Please choose a closer, simpler photo.');
}
