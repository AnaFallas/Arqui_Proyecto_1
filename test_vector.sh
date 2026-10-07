#!/bin/bash

# ==========================================
# CONFIGURACIÓN
# ==========================================
BIN=./bin/norm_vector
TOOLS=tools
DATA=data
TOL=1e-4  # Tolerancia para la verificación
REPS=1    # Repeticiones del kernel (para timing; 1 basta para verificar correctud)

# Lista de todos los archivos .dat que quieres probar
# (Los mismos que generaste con gen_input.py)
FILES=("test_0.dat" "test_1.dat" "test_7.dat" "test_8.dat" "test_15.dat" "test_16.dat" "test_1000.dat" "test_constant.dat" "test_edge.dat")

echo "================================"
echo "PRUEBAS VERSIÓN VECTORIAL (GENERAL)"
echo "================================"

# 1. Generar todos los datos de entrada
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

# 2. Compilar (si es necesario)
echo "Compilando versión escalar..."
make bin/norm_vector > /dev/null 2>&1 || make  # Si no encuentra la regla específica, compila todo

# 3. Bucle para ejecutar y verificar
echo "================================="
total=0
pasan=0
for file in "${FILES[@]}"; do

    # Obtener el nombre base sin extensión (ej: test_7)
    base_name="${file%.dat}"

    # Definir rutas
    input_file="$DATA/$file"
    output_bin="$DATA/${base_name}.out"
    # Este es el archivo que el DRIVER genera automáticamente:
    #   write_stats_summary(path = "<output_bin>.stats.txt", ...)
    # NO se debe redirigir el stdout del programa hacia este mismo nombre,
    # porque el printf de consola usa otro formato ("N = 7") y pisaría
    # el archivo real que necesita verify_reference.py ("n=7").
    stats_file="${output_bin}.stats.txt"

    echo "---------------------------------"
    echo "Probando: $file"

    # Ejecutar el binario. Su salida por consola solo se muestra en pantalla
    # (útil para ver a simple vista N, suma, media, etc.); el archivo de
    # stats para verificación lo escribe el propio driver.c.
    "$BIN" "$input_file" "$output_bin" "$REPS"

    total=$((total + 1))

    if [ ! -f "$stats_file" ]; then
        echo " Resultado: INCORRECTO (no se generó $stats_file; ¿el programa terminó con error?)"
        continue
    fi

    # Verificar con Python
    python3 $TOOLS/verify_reference.py "$input_file" "$stats_file" $TOL

    # Comprobar el código de salida de Python (0 = PASA, distinto de 0 = FALLA)
    if [ $? -eq 0 ]; then
        echo " Resultado: CORRECTO"
        pasan=$((pasan + 1))
    else
        echo " Resultado: INCORRECTO"
        # exit 1  # Descomenta esta línea si quieres que el script se detenga ante el primer error
    fi
done

echo "================================="
echo "Resumen: $pasan / $total casos pasaron."
echo "Todas las pruebas han finalizado."
