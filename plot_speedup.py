import csv
import sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

resumen_csv = sys.argv[1] if len(sys.argv) > 1 else "results/resumen.csv"
salida_png = sys.argv[2] if len(sys.argv) > 2 else "results/speedup_vs_n.png"

data = {}
with open(resumen_csv) as f:
    r = csv.DictReader(f)
    for row in r:
        data.setdefault(row["n"], {})[row["version"]] = float(row["avg_ms"])

etiqueta_a_numero = {"1e3": 1e3, "1e5": 1e5, "1e6": 1e6, "5e7": 5e7}
items = sorted(data.items(), key=lambda kv: etiqueta_a_numero.get(kv[0], 0))

ns, speedups = [], []
for n, d in items:
    if "scalar" in d and "vector" in d and d["vector"] > 0:
        ns.append(etiqueta_a_numero.get(n, n))
        speedups.append(d["scalar"] / d["vector"])

plt.figure(figsize=(6, 4))
plt.plot(ns, speedups, marker="o")
plt.xscale("log")
plt.xlabel("N (escala logarítmica)")
plt.ylabel("Speedup (t_escalar / t_vectorial)")
plt.title("Speedup escalar vs. vectorial (AVX2)")
plt.grid(True, which="both", ls="--", alpha=0.5)
plt.tight_layout()
plt.savefig(salida_png, dpi=150)
print(f"Guardado: {salida_png}")
