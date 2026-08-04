/* =====================================================================
   Genera los iconos de la PWA sin dependencias externas.
   Son PROVISIONALES: en cuanto tengas el logo real de La Corte en PNG
   cuadrado (512x512 minimo), reemplaza los archivos y olvidate de esto.

     node icons/generar-iconos.mjs

   Escribe icon-192.png, icon-512.png y apple-touch-icon.png.
   Los iconos son "maskable": fondo a sangre y el balon dentro del 80%
   central, porque Android e iOS les recortan las esquinas a su manera.
   ===================================================================== */
import { deflateSync } from 'node:zlib';
import { writeFileSync } from 'node:fs';

// Paleta tomada de las variables CSS de index.html
const AZUL   = [1, 51, 105];      // --azul
const DORADO = [255, 182, 18];    // --dorado
const BLANCO = [255, 255, 255];

// ---------- codificador PNG minimo (RGBA, sin filtros) ----------
const TABLA_CRC = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();

function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = TABLA_CRC[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

function chunk(tipo, datos) {
  const largo = Buffer.alloc(4);
  largo.writeUInt32BE(datos.length);
  const cuerpo = Buffer.concat([Buffer.from(tipo, 'ascii'), datos]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(cuerpo));
  return Buffer.concat([largo, cuerpo, crc]);
}

function png(ancho, alto, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(ancho, 0);
  ihdr.writeUInt32BE(alto, 4);
  ihdr[8] = 8;   // bits por canal
  ihdr[9] = 6;   // RGBA
  // filas con byte de filtro 0 al inicio
  const crudo = Buffer.alloc(alto * (ancho * 4 + 1));
  for (let y = 0; y < alto; y++) {
    crudo[y * (ancho * 4 + 1)] = 0;
    rgba.copy(crudo, y * (ancho * 4 + 1) + 1, y * ancho * 4, (y + 1) * ancho * 4);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(crudo, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ---------- dibujo ----------
// Todo en coordenadas normalizadas (-0.5 .. 0.5) para que sea independiente
// del tamano. Se muestrea 4x4 por pixel para que los bordes salgan suaves.
const MUESTRAS = 4;
const ANGULO = -Math.PI / 9;   // balon ligeramente inclinado
const COS = Math.cos(-ANGULO), SIN = Math.sin(-ANGULO);
const EJE_LARGO = 0.30, EJE_CORTO = 0.185;

function colorEn(nx, ny) {
  // rotar al sistema del balon
  const bx = nx * COS - ny * SIN;
  const by = nx * SIN + ny * COS;
  const dentro = (bx / EJE_LARGO) ** 2 + (by / EJE_CORTO) ** 2 <= 1;
  if (!dentro) return AZUL;

  // costura central + agujetas, en blanco
  const costura = Math.abs(by) < 0.011 && Math.abs(bx) < 0.155;
  let agujeta = false;
  for (const cx of [-0.093, -0.031, 0.031, 0.093]) {
    if (Math.abs(bx - cx) < 0.011 && Math.abs(by) < 0.048) agujeta = true;
  }
  return costura || agujeta ? BLANCO : DORADO;
}

function generar(tam) {
  const rgba = Buffer.alloc(tam * tam * 4);
  const paso = 1 / (tam * MUESTRAS);
  for (let y = 0; y < tam; y++) {
    for (let x = 0; x < tam; x++) {
      let r = 0, g = 0, b = 0;
      for (let sy = 0; sy < MUESTRAS; sy++) {
        for (let sx = 0; sx < MUESTRAS; sx++) {
          const nx = (x + (sx + 0.5) / MUESTRAS) / tam - 0.5;
          const ny = (y + (sy + 0.5) / MUESTRAS) / tam - 0.5;
          const c = colorEn(nx, ny);
          r += c[0]; g += c[1]; b += c[2];
        }
      }
      const n = MUESTRAS * MUESTRAS, i = (y * tam + x) * 4;
      rgba[i]     = Math.round(r / n);
      rgba[i + 1] = Math.round(g / n);
      rgba[i + 2] = Math.round(b / n);
      rgba[i + 3] = 255;
    }
  }
  return png(tam, tam, rgba);
}

const base = new URL('.', import.meta.url);
for (const [archivo, tam] of [['icon-192.png', 192], ['icon-512.png', 512], ['apple-touch-icon.png', 180]]) {
  writeFileSync(new URL(archivo, base), generar(tam));
  console.log(`  ${archivo}  ${tam}x${tam}`);
}
