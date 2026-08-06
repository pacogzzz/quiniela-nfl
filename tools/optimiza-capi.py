# Prepara el arte de El Capi para la web.
#
# POR QUE EXISTE ESTE ARCHIVO
# ===========================
# Los PNG que salen de Canva pesan entre 440 KB y 1.1 MB cada uno (8.3 MB los
# doce) y miden ~1100 px de alto. En la app el Capi se ve a 100-150 px. Subir
# los originales seria gastarse el plan de datos de 200 personas que entran
# desde el telefono para mostrar una imagen 10 veces mas grande de lo que cabe.
#
# Este script recorta el margen transparente, escala a 400 px de alto (el doble
# de lo que se ve, para pantallas retina) y guarda WebP con transparencia.
# Resultado: 8.3 MB -> 313 KB, sin diferencia visible.
#
# COMO SE USA (cuando Oscar exporte poses nuevas)
# ===============================================
#   pip install pillow
#   python tools/optimiza-capi.py <carpeta-con-los-png>
#
# El nombre de salida sale de NOMBRES: describe el MOMENTO, no el numero de
# lamina, porque asi lo usa capiSrc() en index.html. Una pose nueva se agrega
# aqui y en la lista CAPI_POSES del index.

import sys
from pathlib import Path

from PIL import Image

DESTINO = Path(__file__).resolve().parent.parent / "icons" / "capi"
ALTO = 400

# lamina de Canva -> momento en la app
NOMBRES = {
    "01_BIENVENIDA":          "bienvenida",
    "02_REGISTRATE":          "registrate",
    "03_LLENA_TUS_DATOS":     "datos",
    "04_ELIGE_TU_PARTIDO":    "calendario",
    "05_ELIGE_AL_GANADOR":    "ganador",
    "06_USA_TU_CONFIANZA":    "confianza",
    "07_GUARDA_PREDICCIONES": "guardar",
    "08_VE_EL_RANKING":       "ranking",
    "09_PUNTOS_POR_CONSUMO":  "consumo",
    "10_PRIMER_ANOTADOR":     "anotador",
    "11_UNDERDOG":            "underdog",
    "12_TERMINASTE_TUTORIAL": "listo",
}


def main(origen: Path) -> None:
    DESTINO.mkdir(parents=True, exist_ok=True)
    antes = despues = 0

    for png in sorted(origen.glob("*.png")):
        slug = NOMBRES.get(png.stem)
        if not slug:
            print(f"  (salto {png.name}: no esta en NOMBRES)")
            continue

        im = Image.open(png).convert("RGBA")
        peso = png.stat().st_size

        # Varias laminas traen mucho aire alrededor del personaje.
        im = im.crop(im.getbbox())

        escala = ALTO / im.height
        if escala < 1:
            im = im.resize((max(1, round(im.width * escala)), ALTO), Image.LANCZOS)

        salida = DESTINO / f"{slug}.webp"
        im.save(salida, "WEBP", quality=82, method=6)

        antes += peso
        despues += salida.stat().st_size
        print(f"  {slug:12} {im.width:4}x{im.height}  {peso/1024:7.0f} KB -> {salida.stat().st_size/1024:6.1f} KB")

    if antes:
        print(f"\n  TOTAL {antes/1024/1024:.1f} MB -> {despues/1024:.0f} KB")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("uso: python tools/optimiza-capi.py <carpeta-con-los-png>")
    main(Path(sys.argv[1]))
