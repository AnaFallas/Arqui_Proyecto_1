import sys
import csv
import statistics
from collections import defaultdict

if len(sys.argv) != 3:
    print("Uso: python3 summarize_bench.py <tiempos.csv> <resumen.csv>")
    sys.exit(1)

entrada, salida = sys.argv[1], sys.argv[2]

data = defaultdict(list)
with open(entrada) as f:
    r = csv.DictReader(f)
    for row in r:
        data[(row["n"], row["version"])].append(float(row["ms"]))

resumen = []
for (n, version), vals in data.items():
    avg = statistics.mean(vals)
    sd = statistics.pstdev(vals)
    resumen.append((n, version, avg, sd))

with open(salida, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["n", "version", "avg_ms", "std_ms"])
    for row in resumen:
        w.writerow(row)

print(f"{'N':>8} {'t_escalar (ms)':>16} {'t_vectorial (ms)':>18} {'Speedup':>10}")
por_n = defaultdict(dict)
for n, version, avg, sd in resumen:
    por_n[n][version] = (avg, sd)

orden = {"1e3": 1e3, "1e5": 1e5, "1e6": 1e6, "5e7": 5e7}
for n in sorted(por_n, key=lambda k: orden.get(k, 0)):
    d = por_n[n]
    if "scalar" in d and "vector" in d:
        ts, sds = d["scalar"]
        tv, sdv = d["vector"]
        speedup = ts / tv if tv > 0 else float("nan")
        print(f"{n:>8} {ts:>10.4f}±{sds:<5.4f} {tv:>10.4f}±{sdv:<6.4f} {speedup:>10.3f}")

print(f"\nResumen guardado en: {salida}")
