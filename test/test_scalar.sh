#!/bin/bash

echo "========================================="
echo "PRUEBAS VERSIÓN ESCALAR"
echo "========================================="
echo ""

# Crear directorio de datos si no existe
mkdir -p data

# Generar todos los casos de prueba
echo "Generando casos de prueba..."
python3 ../tools/gen_input.py 0 ../data/test_0.dat random
python3 ../tools/gen_input.py 1 ../data/test_1.dat random
python3 ../tools/gen_input.py 7 ../data/test_7.dat random
python3 ../tools/gen_input.py 8 ../data/test_8.dat random
python3 ../tools/gen_input.py 15 ../data/test_15.dat random
python3 ../tools/gen_input.py 16 ../data/test_16.dat random
python3 ../tools/gen_input.py 1000 ../data/test_1000.dat random
python3 ../tools/gen_input.py 1000 ../data/test_constant.dat constant
python3 ../tools/gen_input.py 100 ../data/test_edge.dat edge
echo ""

# Compilar
echo "Compilando versión escalar..."
make -C .. bin/norm_scalar
echo ""

if [ $? -ne 0 ]; then
    echo " Error al compilar"
    exit 1
fi

echo " Compilación exitosa"
echo ""

# Ejecutar pruebas
for test in 0 1 7 8 15 16 constant edge 1000; do
    echo "========================================="
    echo "PRUEBA: test_$test.dat"
    echo "========================================="
    
    # Ejecutar (1 repetición para pruebas de correctud)
    ../bin/norm_scalar data/test_$test.dat data/out_$test.dat 1
    
    # Verificar resultados
    if [ -f "data/out_$test.dat.stats.txt" ]; then
        echo ""
        echo "--- Verificando con referencia ---"
        python3 tools/verify_reference.py data/test_$test.dat data/out_$test.dat.stats.txt
    fi
    
    echo ""
done

echo "========================================="
echo " PRUEBAS COMPLETADAS"
echo "========================================="
