# Programación Vectorial en Ensamblador x86-64 (NASM/Linux)
### Normalizador estadístico vectorizado: comparación escalar vs. AVX2

**Autor:** Ana Cristina Fallas Quirós
**Curso:** Arquitectura de Computadores
**Fecha de entrega:** 06/10/2026

---

## Descripción

Este proyecto implementa un **normalizador estadístico** (z-score) para arreglos grandes de
números en punto flotante de precisión simple: dado un arreglo `x`, calcula su suma, media,
varianza, desviación estándar, mínimo y máximo, y produce la versión normalizada

```
y[i] = (x[i] - mean) / stddev
```

El núcleo de cómputo (`sum_array`, `compute_stats`, `normalize_array`) está escrito **dos veces**
en ensamblador NASM x86-64, siguiendo la convención de llamada System V AMD64 ABI:

- **Versión escalar**: instrucciones SSE escalares (`movss`, `addss`, `subss`, `mulss`, `divss`,
  `comiss`), procesando un `float` por iteración.
- **Versión vectorial**: instrucciones AVX2 (`vmovups`/`vmovaps`, `vaddps`, `vsubps`, `vmulps`,
  `vminps`, `vmaxps`, `vbroadcastss`, reducción horizontal con `vextractf128`/`vhaddps`),
  procesando **8 floats por iteración**, con manejo explícito del remanente (`n % 8`).

El objetivo no es el cálculo estadístico en sí, sino medir y explicar cuantitativamente la
diferencia de rendimiento entre el modelo de ejecución escalar (SISD) y el vectorial (SIMD).

El driver (lectura de archivo, reserva de memoria alineada, medición de tiempo e impresión de
resultados) está escrito en C y es **el mismo** para ambas versiones; solo cambia el `.o` del
kernel con el que se enlaza.

---

## Estructura del repositorio

```
.
├── asm/
│   ├── scalar/stats_scalar.asm      # Kernel escalar (SSE)
│   └── vector/stats_vector.asm      # Kernel vectorial (AVX2)
├── include/
│   └── stats.h                      # Firmas compartidas por ambas versiones
├── src/
│   └── driver.c                     # Programa principal (E/S, timing, impresión)
├── tools/
│   ├── gen_input.py                 # Genera archivos de entrada de prueba
│   ├── verify_reference.py          # Verifica resultados contra referencia en Python/NumPy
│   └── summarize_bench.py           # Calcula promedio/desviación estándar/speedup del benchmark
├── test/                            # Casos de prueba auxiliares
├── data/                            # Entradas/salidas .dat generadas (no versionadas en su mayoría)
├── results/                         # CSV de tiempos y gráfico de speedup generados por bench.sh
├── bin/                             # Ejecutables compilados (norm_scalar, norm_vector)
├── obj/                             # Archivos objeto (.o) intermedios de la compilación
├── Makefile
├── bench.sh                         # Benchmark de rendimiento (30 reps × 4 tamaños)
├── plot_speedup.py                  # Genera results/speedup_vs_n.png
├── test_scalar.sh                   # Corre y verifica solo la versión escalar
├── test_vector.sh                   # Corre y verifica solo la versión vectorial
├── test_all.sh                      # Corre y verifica ambas versiones + comparación cruzada
├── resultados_casos_borde.txt       # Salida guardada de test_all.sh (evidencia casos borde)
├── sesion_gdb_n16.txt               # Transcripción de la sesión de GDB con N=16
├── diagrama_arquitectura.drawio.pdf # Diagrama de arquitectura (entregable, 4 piezas de la sec. 3.a)
├── diagrama_arquitectura.drawio.html
├── Proyecto1_Informe_Ana_Fallas.pdf # Informe técnico completo
└── README.md                        # Este archivo
```

---

## Requisitos

- Linux (probado en Ubuntu 24.04.4 LTS)
- CPU con soporte AVX2 (verificar con `lscpu | grep avx2`)
- `nasm` ≥ 2.15, `gcc`, `make`, `python3`
- `gdb` ≥ 10 (para la sección de depuración)
- `perf` / paquete `linux-tools` (para las métricas de rendimiento)
- `python3-matplotlib` (para el gráfico de speedup)

### Entorno de pruebas utilizado

| Ítem | Valor |
|---|---|
| CPU | Intel(R) Core(TM) i5-1135G7 @ 2.40GHz (Tiger Lake) |
| Soporte AVX2 | Sí |
| NASM | 2.16.01 |
| GCC | 13.3.0 (Ubuntu 13.3.0-6ubuntu2~24.04.1) |
| GDB | 15.1 (Ubuntu 15.1-1ubuntu1~24.04.1) |
| SO | Ubuntu 24.04.4 LTS (noble) |

---

## Compilación

```bash
make
```

Genera `bin/norm_scalar` y `bin/norm_vector`: dos ejecutables que comparten el mismo `driver.c`
pero enlazan con kernels distintos (`obj/stats_scalar.o` u `obj/stats_vector.o`).

```bash
make clean && make   # recompilar desde cero
```

---

## Generar datos de prueba

```bash
python3 tools/gen_input.py 1000000 data/input.dat random
python3 tools/gen_input.py 16 data/test_16.dat random
python3 tools/gen_input.py 1000 data/test_constant.dat constant
python3 tools/gen_input.py 0 data/test_0.dat random
```

Formato binario (little endian): `int32 N` seguido de `N` floats de 32 bits.

---

## Ejecutar

```bash
./bin/norm_scalar data/input.dat data/output_scalar.dat 30
./bin/norm_vector data/input.dat data/output_vector.dat 30
```

El tercer argumento es el número de repeticiones del kernel (promedia el tiempo medido con
`clock_gettime`). Cada corrida también escribe `data/output_*.dat.stats.txt` con un resumen en
texto plano de los estadísticos y el tiempo del kernel, usado por `verify_reference.py`.

---

## Pruebas de correctud

```bash
./test_scalar.sh   # solo escalar, 9 casos borde, contra referencia Python
./test_vector.sh   # solo vectorial, 9 casos borde, contra referencia Python
./test_all.sh       # ambas versiones + comparación cruzada escalar/vectorial
```

Casos borde cubiertos: `N=0`, `N=1`, `N=7` y `N=15` (no múltiplos de 8), `N=8` y `N=16`
(múltiplos exactos), `N=1000` aleatorio, `N=1000` constante (σ=0), `N=100` valores extremos.

**Resultado actual: 9/9 casos pasan contra la referencia y 9/9 coinciden entre escalar y
vectorial.** Ver `resultados_casos_borde.txt` para la salida completa.

| N | Caso | Error rel. máx. | Escalar | Vectorial | Cruzada |
|---|---|---|---|---|---|
| 0 | vacío | 0 | PASA | PASA | PASA |
| 1 | un elemento | 2.06e-10 | PASA | PASA | PASA |
| 7 | no múltiplo de 8 | 9.34e-8 | PASA | PASA | PASA |
| 8 | múltiplo exacto | 7.08e-7 | PASA | PASA | PASA |
| 15 | no múltiplo de 8 | 1.09e-6 | PASA | PASA | PASA |
| 16 | múltiplo exacto | 5.12e-8 | PASA | PASA | PASA |
| 1000 | valores aleatorios | 2.43e-7 | PASA | PASA | PASA |
| 1000 | valores constantes (σ=0) | 0 | PASA | PASA | PASA |
| 100 | valores extremos | 1.57e-7 | PASA | PASA | PASA |

---

## Benchmark de rendimiento

```bash
chmod +x bench.sh
./bench.sh
```

Genera entradas de `N = 10³, 10⁵, 10⁶, 5×10⁷`, corre cada binario **30 veces por tamaño**, y
calcula promedio ± desviación estándar y speedup (`tools/summarize_bench.py`). Resultados en
`results/tiempos.csv` y `results/resumen.csv`.

```bash
python3 plot_speedup.py results/resumen.csv results/speedup_vs_n.png
```

### Resultados obtenidos

| N | t_escalar (ms) ± σ | t_vectorial (ms) ± σ | Speedup |
|---|---|---|---|
| 10³ | 0.0080 ± 0.0008 | 0.0014 ± 0.0001 | 5.842 |
| 10⁵ | 0.7417 ± 0.0193 | 0.1095 ± 0.0068 | 6.772 |
| 10⁶ | 7.3074 ± 0.0808 | 1.3820 ± 0.0761 | 5.288 |
| 5×10⁷ | 252.1542 ± 5.3312 | 79.3056 ± 3.8826 | 3.180 |

El speedup sube hasta `N=10⁵` (el cómputo aún domina) y luego cae conforme el arreglo deja de
caber en las cachés L1/L2/L3: a partir de ahí el kernel queda limitado por el ancho de banda de
memoria, no por el cómputo, por lo que el speedup nunca se acerca al 8× teórico de AVX2.

### `perf stat` (N = 5×10⁷)

```bash
perf stat -e cycles,instructions,cache-misses ./bin/norm_scalar data/perf_5e7.dat data/out.dat 1
perf stat -e cycles,instructions,cache-misses ./bin/norm_vector data/perf_5e7.dat data/out.dat 1
```

| Métrica | Escalar | Vectorial |
|---|---|---|
| Ciclos | 1 472 905 572 | 865 568 521 |
| Instrucciones | 2 276 627 435 | 914 737 716 |
| IPC | 1.546 | 1.057 |
| Cache-misses | 24 200 085 | 31 813 733 |

El IPC vectorial es *menor* que el escalar pese a ejecutar 2.49× menos instrucciones, y los
cache-misses no bajan con la vectorización: firma característica de un kernel memory-bound (ver
interpretación completa en el informe, sección 6.4).

---

## Depuración con GDB

Sesión documentada con `N=16`, inspeccionando el registro `ymm0` tras `vaddps` en `sum_array` y
la memoria del arreglo de salida tras `normalize_array`. Transcripción completa en
`sesion_gdb_n16.txt`.

```bash
gdb --args ./bin/norm_vector data/test_16.dat data/out16.dat 1
(gdb) break stats_vector.asm:34
(gdb) run
(gdb) next
(gdb) p $ymm0.v8_float
```

Esta misma herramienta se usó para diagnosticar y confirmar el bug de corrupción de acumulador
descrito abajo.

---

## Caso de estudio: bug de corrupción de acumulador

Durante el desarrollo se detectó que `var` y `stddev` fallaban sistemáticamente en la versión
vectorial (mientras que `sum`, `mean`, `min` y `max` eran correctos). La causa: en
`compute_stats`, el registro `xmm4` (usado para guardar `(float)n`) era pisado por
`vbroadcastss ymm4, xmm6` al calcular el broadcast de la media, ya que `xmm4` es la mitad baja de
`ymm4`. La división final `var = sum_sq / n` terminaba dividiendo por la media en vez de por `n`.

**Corrección:** usar `ymm7` (no `ymm4`) para el broadcast de la media, dejando `xmm4` intacto
hasta la división final. Documentado en detalle, con la sesión de GDB que lo confirmó, en la
sección 4.7 del informe técnico.

---

## Documentación completa

- **[Proyecto1_Informe_Ana_Fallas.pdf](./Proyecto1_Informe_Ana_Fallas.pdf)** — informe técnico
  completo: introducción y objetivos, implementación escalar y vectorial comentada línea por
  línea, justificación de AVX2, estrategia de reducción horizontal, caso de estudio del bug de
  corrupción de acumulador, casos de prueba, resultados de rendimiento con interpretación, y
  evidencia completa de la sesión de GDB.
- **[diagrama_arquitectura.drawio.pdf](./diagrama_arquitectura.drawio.pdf)** — diagrama de
  bloques, flujo de control de cada kernel, tabla de asignación de registros y mapa de memoria,
  según lo pedido en la sección 3.a del enunciado original (`README_pdf.pdf`).

---

## Conclusiones (resumen)

La versión AVX2 es entre 5× y 7× más rápida que la escalar en tamaños medianos
(`N = 10³` a `10⁵`), cayendo a ~3× en `N = 5×10⁷` por saturación del ancho de banda de memoria.
Los cuatro objetivos prácticos del proyecto se cumplieron: (i) kernels SIMD en NASM respetando la
ABI System V; (ii) manejo correcto del remanente con bucle escalar de cierre; (iii) depuración de
errores de bajo nivel con GDB; (iv) interpretación cuantitativa del rendimiento a la luz de la Ley
de Amdahl y el ancho de banda de memoria.

**Trabajo futuro:** múltiples acumuladores (unrolling) para romper la cadena de dependencias de
`vaddps`; usar FMA (`vfmadd231ps`) en la segunda pasada de `compute_stats`; portar a AVX-512 en
CPUs compatibles.
