# Prepara el arte de El Capi para la web.
#
# POR QUE EXISTE ESTE ARCHIVO
# ===========================
# Los PNG que salen de Canva pesan entre 640 KB y 1.6 MB cada uno (12 MB los
# doce) y miden ~1130 px de alto. En la app el Capi se ve a 100-150 px. Subir
# los originales seria gastarse el plan de datos de 200 personas que entran
# desde el telefono para mostrar una imagen 10 veces mas grande de lo que cabe.
#
# DOS SALIDAS POR LAMINA
# ======================
# Algunas laminas no son solo el personaje: traen un PIZARRON con texto que
# explica la mecanica (elige tu partido, puntos de confianza, ranking). Ese
# texto es ilegible a 100 px, asi que de esas se sacan dos archivos:
#
#   icons/capi/<momento>.webp        solo el personaje, recortado -> tarjetas
#   icons/capi/board-<momento>.webp  la lamina completa           -> modal
#
# De las demas solo sale la primera, porque el personaje ES toda la lamina.
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
ALTO_POSE = 400    # se ve a 150 px como mucho; 400 alcanza para pantallas retina
ANCHO_BOARD = 900  # el pizarron se abre grande: el texto tiene que leerse

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

# Laminas con pizarron. El valor es desde que fraccion del ancho empieza el
# personaje, para poder recortarlo del pizarron. Se saco a ojo mirando cada
# imagen; si Oscar reencuadra alguna, hay que revisarlo.
CON_PIZARRON = {
    "04_ELIGE_TU_PARTIDO": 0.52,
    "06_USA_TU_CONFIANZA": 0.66,
    "08_VE_EL_RANKING":    0.63,
}


def guarda(im, ruta, calidad=82):
    im.save(ruta, "WEBP", quality=calidad, method=6)
    return ruta.stat().st_size


def main(origen: Path) -> None:
    DESTINO.mkdir(parents=True, exist_ok=True)
    antes = despues = 0

    for png in sorted(origen.glob("*.png")):
        slug = NOMBRES.get(png.stem)
        if not slug:
            print(f"  (salto {png.name}: no esta en NOMBRES)")
            continue

        original = Image.open(png).convert("RGBA")
        peso = png.stat().st_size
        antes += peso

        # --- lamina completa, solo si trae pizarron ---
        if png.stem in CON_PIZARRON:
            board = original.crop(original.getbbox())
            if board.width > ANCHO_BOARD:
                escala = ANCHO_BOARD / board.width
                board = board.resize((ANCHO_BOARD, round(board.height * escala)), Image.LANCZOS)
            peso_b = guarda(board, DESTINO / f"board-{slug}.webp", 80)
            despues += peso_b
            print(f"  board-{slug:8} {board.width:4}x{board.height:<5} {peso_b/1024:6.1f} KB")

            # y el personaje solo, para la tarjeta chica
            corte = original.crop((round(original.width * CON_PIZARRON[png.stem]), 0,
                                   original.width, original.height))
        else:
            corte = original

        # --- personaje ---
        im = corte.crop(corte.getbbox())
        escala = ALTO_POSE / im.height
        if escala < 1:
            im = im.resize((max(1, round(im.width * escala)), ALTO_POSE), Image.LANCZOS)

        peso_p = guarda(im, DESTINO / f"{slug}.webp")
        despues += peso_p
        print(f"  {slug:14} {im.width:4}x{im.height:<5} {peso/1024:7.0f} KB -> {peso_p/1024:6.1f} KB")

    if antes:
        print(f"\n  TOTAL {antes/1024/1024:.1f} MB -> {despues/1024:.0f} KB")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("uso: python tools/optimiza-capi.py <carpeta-con-los-png>")
    main(Path(sys.argv[1]))
