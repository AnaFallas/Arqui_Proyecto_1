#!/bin/bash
set -e

DATA=data
RESULTS=results
REPS=30

SIZES=(1000 100000 1000000 50000000)
LABELS=(1e3 1e5 1e6 5e7)

mkdir -p "$RESULTS"

echo "Generando entradas grandes (puede tardar con 5e7)..."
for i in "${!SIZES[@]}"; do
    n=${SIZES[$i]}
    label=${LABELS[$i]}
    python3 tools/gen_input.py "$n" "$DATA/perf_${label}.dat" random
done

echo "Compilando..."
make > /dev/null

csv="$RESULTS/tiempos.csv"
echo "n,version,rep,ms" > "$csv"

for i in "${!SIZES[@]}"; do
    label=${LABELS[$i]}
    input="$DATA/perf_${label}.dat"
    for version in scalar vector; do
        bin="./bin/norm_${version}"
        out="$DATA/perf_${label}_${version}.out"
        echo "N=${label}  version=${version}  (${REPS} repeticiones)"
        for rep in $(seq 1 $REPS); do
            "$bin" "$input" "$out" 1 > /tmp/bench_run.log 2>&1
            ms=$(grep -oE '[0-9]+\.[0-9]+' /tmp/bench_run.log | tail -1)
            echo "${label},${version},${rep},${ms}" >> "$csv"
        done
    done
done

echo ""
echo "Calculando promedio, desviación estándar y speedup..."
python3 tools/summarize_bench.py "$csv" "$RESULTS/resumen.csv"
