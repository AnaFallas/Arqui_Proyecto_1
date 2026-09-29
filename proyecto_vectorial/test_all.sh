#!/bin/bash

# ==========================================
# Corre las dos  versiones (escalar y vectorial) sobre los mismos casos
# de prueba, verifica cada una contra la referencia de Python y
# compara los dos resultados entre sí (media, varianza, min, max).
# ==========================================

TOOLS=tools
DATA=data
TOL=1e-4
REPS=1

FILES=("test_0.dat" "test_1.dat" "test_7.dat" "test_8.dat" "test_15.dat" "test_16.dat" "test_1000.dat" "test_constant.dat" "test_edge.dat")

echo "Generando casos de prueba..."
python3 $TOOLS/gen_input.py 0 $DATA/test_0.dat random
python3 $TOOLS/gen_input.py 1 $DATA/test_1.dat random
python3 $TOOLS/gen_input.py 7 $DATA/test_7.dat random
python3 $TOOLS/gen_input.py 8 $DATA/test_8.dat random
python3 $TOOLS/gen_input.py 15 $DATA/test_15.dat random
python3 $TOOLS/gen_input.py 16 $DATA/test_16.dat random
python3 $TOOLS/gen_input.py 1000 $DATA/test_1000.dat random
python3 $TOOLS/gen_input.py 1000 $DATA/test_constant.dat constant
python3 $TOOLS/gen_input.py 100 $DATA/test_edge.dat edge

echo "Compilando ambas versiones..."
make > /dev/null 2>&1 || make

pasan_ref=0
pasan_cruzado=0
total=0

for file in "${FILES[@]}"; do
    base_name="${file%.dat}"
    input_file="$DATA/$file"

    out_scalar="$DATA/${base_name}_scalar.out"
    out_vector="$DATA/${base_name}_vector.out"
    stats_scalar="${out_scalar}.stats.txt"
    stats_vector="${out_vector}.stats.txt"

    echo "==================================================="
    echo "Caso: $file"
    echo "---------------------------------------------------"

    ./bin/norm_scalar "$input_file" "$out_scalar" "$REPS" > /tmp/log_scalar.txt 2>&1
    ./bin/norm_vector "$input_file" "$out_vector" "$REPS" > /tmp/log_vector.txt 2>&1
    total=$((total + 1))

    ok_ref=1

    if [ -f "$stats_scalar" ]; then
        echo "[Escalar vs referencia]"
        python3 $TOOLS/verify_reference.py "$input_file" "$stats_scalar" $TOL
        [ $? -eq 0 ] || ok_ref=0
    else
        echo "[Escalar] No generó $stats_scalar (ver /tmp/log_scalar.txt)"
        ok_ref=0
    fi

    if [ -f "$stats_vector" ]; then
        echo "[Vectorial vs referencia]"
        python3 $TOOLS/verify_reference.py "$input_file" "$stats_vector" $TOL
        [ $? -eq 0 ] || ok_ref=0
    else
        echo "[Vectorial] No generó $stats_vector (ver /tmp/log_vector.txt)"
        ok_ref=0
    fi

    [ $ok_ref -eq 1 ] && pasan_ref=$((pasan_ref + 1))

    # --- Comparación cruzada: escalar vs vectorial, campo por campo ---
    if [ -f "$stats_scalar" ] && [ -f "$stats_vector" ]; then
        cmp_result=$(python3 - "$stats_scalar" "$stats_vector" "$TOL" <<'PYEOF'
import sys

def leer(path):
    d = {}
    with open(path) as f:
        for line in f:
            if "=" in line:
                k, v = line.strip().split("=", 1)
                d[k] = float(v)
    return d

a = leer(sys.argv[1])
b = leer(sys.argv[2])
tol = float(sys.argv[3])

ok = True
for campo in ("n", "sum", "mean", "var", "stddev", "min", "max"):
    va, vb = a.get(campo), b.get(campo)
    if va is None or vb is None:
        print(f"  {campo:8s}: falta en uno de los archivos -> FALLA")
        ok = False
        continue
    denom = max(abs(va), 1e-12)
    err = abs(va - vb) / denom
    estado = "OK" if err <= tol else "FALLA"
    if estado == "FALLA":
        ok = False
    print(f"  {campo:8s}: escalar={va:.6g}  vectorial={vb:.6g}  error_rel={err:.3e}  {estado}")

sys.exit(0 if ok else 1)
PYEOF
)
        cmp_status=$?          # capturado AQUÍ, justo tras el python, no tras el echo
        echo "[Escalar vs Vectorial, entre sí]"
        echo "$cmp_result"
        [ $cmp_status -eq 0 ] && pasan_cruzado=$((pasan_cruzado + 1))
    fi
done

echo "==================================================="
echo "RESUMEN"
echo "  Casos donde AMBAS versiones pasan contra la referencia: $pasan_ref / $total"
echo "  Casos donde escalar y vectorial coinciden ENTRE SÍ:      $pasan_cruzado / $total"
echo "==================================================="
