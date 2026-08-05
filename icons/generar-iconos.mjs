/* =====================================================================
   Genera los iconos de la PWA a partir del logo real, sin dependencias.

     node icons/generar-iconos.mjs

   Entrada : icons/logo-fuente.png   (el logo de La Corte, vertical)
   Salida  : icon-192.png · icon-512.png · apple-touch-icon.png

   El logo es vertical y los iconos tienen que ser CUADRADOS, asi que se
   recorta un cuadro centrado en la corona y el balon (la parte de arriba),
   dejando fuera el texto de abajo: a 192 px no se alcanzaria a leer y solo
   ensuciaria el icono.
   ===================================================================== */
import { deflateSync, inflateSync } from 'node:zlib';
import { readFileSync, writeFileSync } from 'node:fs';

// Que tanto del alto se salta desde arriba para centrar corona+balon.
const RECORTE_ARRIBA = 0.08;

// ---------- CRC32, comun a leer y escribir ----------
const TABLA_CRC = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();
const crc32 = (buf) => {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = TABLA_CRC[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
};

// ---------- LECTOR PNG (8 bits, RGB o RGBA, sin entrelazar) ----------
function leerPng(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error('no es un PNG');
  let p = 8, ancho = 0, alto = 0, canales = 0;
  const trozos = [];

  while (p < buf.length) {
    const largo = buf.readUInt32BE(p);
    const tipo = buf.toString('ascii', p + 4, p + 8);
    const datos = buf.subarray(p + 8, p + 8 + largo);
    if (tipo === 'IHDR') {
      ancho = datos.readUInt32BE(0);
      alto = datos.readUInt32BE(4);
      const bits = datos[8], tipoColor = datos[9], entrelazado = datos[12];
      if (bits !== 8) throw new Error(`solo 8 bits por canal (este trae ${bits})`);
      if (entrelazado !== 0) throw new Error('PNG entrelazado no soportado');
      if (tipoColor === 2) canales = 3;
      else if (tipoColor === 6) canales = 4;
      else throw new Error(`tipo de color ${tipoColor} no soportado (usa RGB o RGBA)`);
    } else if (tipo === 'IDAT') trozos.push(datos);
    else if (tipo === 'IEND') break;
    p += 12 + largo;
  }

  const crudo = inflateSync(Buffer.concat(trozos));
  const anchoFila = ancho * canales;
  const salida = Buffer.alloc(ancho * alto * 4);
  let previa = Buffer.alloc(anchoFila);

  for (let y = 0; y < alto; y++) {
    const filtro = crudo[y * (anchoFila + 1)];
    const fila = Buffer.from(crudo.subarray(y * (anchoFila + 1) + 1, (y + 1) * (anchoFila + 1)));
    // Deshacer el filtro de la fila (los 5 tipos del estandar PNG)
    for (let i = 0; i < anchoFila; i++) {
      const a = i >= canales ? fila[i - canales] : 0;   // pixel de la izquierda
      const b = previa[i];                              // pixel de arriba
      const c = i >= canales ? previa[i - canales] : 0; // arriba-izquierda
      let v = fila[i];
      if (filtro === 1) v += a;
      else if (filtro === 2) v += b;
      else if (filtro === 3) v += (a + b) >> 1;
      else if (filtro === 4) {
        const q = a + b - c, pa = Math.abs(q - a), pb = Math.abs(q - b), pc = Math.abs(q - c);
        v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
      }
      fila[i] = v & 0xff;
    }
    previa = fila;
    for (let x = 0; x < ancho; x++) {
      const o = (y * ancho + x) * 4, i = x * canales;
      salida[o] = fila[i]; salida[o + 1] = fila[i + 1]; salida[o + 2] = fila[i + 2];
      salida[o + 3] = canales === 4 ? fila[i + 3] : 255;
    }
  }
  return { ancho, alto, pixeles: salida };
}

// ---------- ESCRITOR PNG ----------
function chunk(tipo, datos) {
  const largo = Buffer.alloc(4); largo.writeUInt32BE(datos.length);
  const cuerpo = Buffer.concat([Buffer.from(tipo, 'ascii'), datos]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(cuerpo));
  return Buffer.concat([largo, cuerpo, crc]);
}
function escribirPng(lado, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(lado, 0); ihdr.writeUInt32BE(lado, 4);
  ihdr[8] = 8; ihdr[9] = 6;
  const crudo = Buffer.alloc(lado * (lado * 4 + 1));
  for (let y = 0; y < lado; y++) {
    crudo[y * (lado * 4 + 1)] = 0;
    rgba.copy(crudo, y * (lado * 4 + 1) + 1, y * lado * 4, (y + 1) * lado * 4);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x08 + 2]),
    chunk('IHDR', ihdr), chunk('IDAT', deflateSync(crudo, { level: 9 })), chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ---------- Recortar cuadrado y reescalar promediando ----------
function iconoDe(src, lado) {
  const cuadro = Math.min(src.ancho, src.alto);
  const x0 = Math.round((src.ancho - cuadro) / 2);
  const y0 = Math.min(Math.round(src.alto * RECORTE_ARRIBA), src.alto - cuadro);
  const paso = cuadro / lado;
  const out = Buffer.alloc(lado * lado * 4);

  for (let y = 0; y < lado; y++) {
    for (let x = 0; x < lado; x++) {
      // Promedia el bloque de origen: reescalar tomando un solo pixel
      // deja los bordes dentados y el logo tiene mucho detalle fino.
      const sx0 = x0 + Math.floor(x * paso), sx1 = x0 + Math.floor((x + 1) * paso);
      const sy0 = y0 + Math.floor(y * paso), sy1 = y0 + Math.floor((y + 1) * paso);
      let r = 0, g = 0, b = 0, n = 0;
      for (let sy = sy0; sy < sy1; sy++) {
        for (let sx = sx0; sx < sx1; sx++) {
          const o = (sy * src.ancho + sx) * 4;
          r += src.pixeles[o]; g += src.pixeles[o + 1]; b += src.pixeles[o + 2]; n++;
        }
      }
      const o = (y * lado + x) * 4;
      out[o] = Math.round(r / n); out[o + 1] = Math.round(g / n);
      out[o + 2] = Math.round(b / n); out[o + 3] = 255;
    }
  }
  return escribirPng(lado, out);
}

const base = new URL('.', import.meta.url);
const src = leerPng(readFileSync(new URL('logo-fuente.png', base)));
console.log(`logo de origen: ${src.ancho}x${src.alto}`);
for (const [archivo, lado] of [['icon-192.png', 192], ['icon-512.png', 512], ['apple-touch-icon.png', 180]]) {
  writeFileSync(new URL(archivo, base), iconoDe(src, lado));
  console.log(`  ${archivo}  ${lado}x${lado}`);
}
