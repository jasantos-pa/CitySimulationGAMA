# Ejecuciones trazables

## Problemas comprobados

En la variante local `solvingStuck copy`, `SimulationLogger` inicia los CSV con `rewrite: true` y nombres compartidos (`trips.csv`, `events.csv`, diagnósticos y población). Se vacían buffers de eventos/viajes cada diez ciclos. Una interrupción puede dejar un final incompleto. Los CSV no incluyen un identificador global de ejecución, commit, hash de modelo ni semilla.

Las carpetas históricas `3days`, `4days` y `last` contienen selecciones distintas de archivos; el nombre no demuestra duración ni procedencia. No reconstruir una correspondencia inequívoca usando solo fechas. Registrar la procedencia desconocida como tal.

Hay varias fuentes de configuración:

- `Leganes` expone paso, flota, probabilidades modales, horarios, velocidades y radio de búsqueda.
- Su `_init_` crea una simulación con 10.000 personas y 15 taxis, mientras el parámetro de taxis declara inicialmente 1. Hay que distinguir valor solicitado de valor efectivo.
- La flota puede cambiar durante una ejecución; existe `TAXI_FLEET_SYNC`, pero no un historial general de todos los parámetros.
- En la variante candidata el paso inicial es `3 * 0.016` minutos (2,88 segundos), y la fecha simulada inicial es 12/06/2024 06:59:59. No confundirla con la fecha real de ejecución.
- No se fija ni registra `seed`/`rng` en el modelo candidato. Las sondas XML existentes sí especifican semilla 1.
- `ORDER BY RANDOM()` selecciona vehículos en SQLite. Esa aleatoriedad no queda gobernada por la semilla GAMA. Una semilla fija no basta para asegurar igualdad exacta.
- Los analizadores y dashboards existentes leen CSV junto a su propio script; aún necesitan aceptar `--run-dir` para consultar las nuevas ejecuciones.

GAMA permite fijar semillas al crear simulaciones y elegir el generador; hay que registrar los valores efectivos, no solo la solicitud. Véase [semillas y simulaciones en GAMA](https://gama-platform.org/wiki/RunSeveralSimulations). El azar de SQL procede de [SQLite random()](https://www.sqlite.org/lang_corefunc.html#random).

## Herramienta incorporada

`tools/run_archive.py` utiliza solo la biblioteca estándar de Python 3.9 o posterior y no cambia los modelos, la población ni la movilidad. `prepare` **no ejecuta GAMA**:

1. Comprueba modelo, experimento, semilla explícita no nula e instalación GAMA.
2. Copia los bytes actuales del modelo y sus imports, aunque estén ignorados o modificados sin commit.
3. Copia las entradas literales `../includes/`, los componentes del shapefile y entradas adicionales declaradas con `--input`.
4. Compara hashes antes/después para detectar cambios durante la copia; rechaza bases con WAL/journal activo.
5. Guarda commit, rama, estado dirty, fuentes no versionadas, diff de fuentes versionadas, hashes, parámetros solicitados, semilla, límite de pasos, versión declarada de GAMA y plan XML.
6. Reserva una carpeta exclusiva: nunca reutiliza ni sobrescribe otra ejecución.

La captura exacta de fuentes es la referencia principal: un diff no conserva por sí solo archivos ignorados. La marca dirty de Git tampoco detecta todos los ignorados. Los manifiestos locales contienen rutas de la máquina; no publicarlos sin revisión.

Si Git no puede leer el repositorio (incluido un propietario distinto), la preparación se detiene: no se presenta un archivo sin commit como trazabilidad completa. Ejecutar con la cuenta propietaria. `--allow-no-git` es una excepción explícita para fuentes sin versionar; queda marcada en el manifiesto y no recupera el historial que falta.

Ejemplo PowerShell, reemplazando rutas por las de la máquina:

```powershell
python tools/run_archive.py prepare `
  --project 'C:\ruta\CitySimulator' `
  --model 'models/CitySimulation-updated-activities2-solvingStuck copy.gaml' `
  --experiment Leganes --seed 42 --steps 100 `
  --gama-home 'C:\ruta\Gama' `
  --output-root 'D:\investigacion\city-runs'
```

El clon publicado no contiene todas las entradas actuales: ejecutar contra un workspace completo o restaurar primero el conjunto de datos correcto. Ante dependencias ausentes, la herramienta falla explícitamente; no sustituye datos silenciosamente.

`--parameters configuracion.json` admite un objeto de variables expuestas y valores escalares, por ejemplo `{"initialSearchRadius": 500.0}`. No expone `numPeople` por arte de magia ni corrige las asignaciones de `_init_`. Las unidades numéricas son las que interpreta GAMA; no deducirlas de la etiqueta de pantalla. Los valores efectivos se mantienen como desconocidos hasta añadir instrumentación validada.

La carpeta creada contiene:

```text
<run_id>/
  manifest.json          procedencia y solicitud original
  source.patch           cambios de fuentes versionadas respecto a HEAD
  run_archive.py         herramienta exacta usada
  plan.xml               solicitud para GAMA headless
  project/models/        código congelado; CSV relativos tras la ejecución
  project/includes/      entradas congeladas con estructura original
  gama-workspace/        workspace de ejecución, al lanzarla
  headless/              salidas del lanzador, al ejecutarlo
  results.json           inventario de CSV tras finalize
```

Usar únicamente la copia dentro de `project/`. El manifiesto proporciona `launch.argv` y `launch.cwd`. Para ejecutar deliberadamente el plan preparado, en PowerShell:

```powershell
$runDir = 'D:\investigacion\city-runs\ID_DEVUELTO'
$manifest = Get-Content -Raw -LiteralPath "$runDir\manifest.json" | ConvertFrom-Json
$arguments = @($manifest.launch.argv)
Push-Location -LiteralPath $manifest.launch.cwd
try {
  & $arguments[0] @($arguments[1..($arguments.Count - 1)]) *> "$runDir\console.log"
  $gamaExitCode = $LASTEXITCODE
} finally {
  Pop-Location
}
python tools/run_archive.py finalize --run-dir $runDir --exit-code $gamaExitCode
```

No relanzar una carpeta: crear otra réplica con otro ID. Para interfaz gráfica, abrir la copia aislada; si se cambian parámetros manualmente el plan ya no describe la solicitud real. Por ahora reservar comparaciones formales para planes controlados y anotar cualquier intervención.

El plan contiene rutas absolutas a la instantánea: conservar la carpeta en su ubicación original. Si se traslada, preparar una ejecución nueva desde la copia conservada; no editar silenciosamente el plan. Si falla la preparación, puede quedar una carpeta parcial sin manifiesto: conservarla para inspección y usar un ID nuevo al reintentar.

`finalize` se utiliza después de detener GAMA. Verifica fuentes, entradas y plan; registra cabeceras, tamaños y SHA-256 de los CSV. No modifica los CSV ni el manifiesto inicial. Rechaza una captura sin CSV o una segunda finalización. El estado es `outputs_archived_unvalidated`: ni un CSV existente ni un código de salida aportado por el usuario prueban que se alcanzó la duración prevista.

## Alcance y siguiente validación

La preparación y finalización se prueban con fixtures, sin lanzar la simulación científica. El plan real y sus parámetros efectivos siguen pendientes de una corrida corta en GAMA. La detección de dependencias es deliberadamente limitada: literales `../includes/` e imports. Declarar dependencias adicionales con `--input`; expresiones dinámicas, plugins, rutas externas y bases activas requieren una estrategia explícita. No usar este archivador como sandbox para modelos arbitrarios.

Para cerrar la reproducibilidad habrá que registrar desde GAMA: semilla/RNG efectivos antes de sortear población, parámetros efectivos, cambios por ciclo, número de personas/coches/taxis creado, instante/ciclo final y motivo de parada. Añadir un `run_id` a cada tabla permitirá unir exportaciones sin depender de la carpeta. Conservar también versión de Java/plugins y configuración de paralelismo cuando se validen comparaciones entre máquinas.

La selección SQL aleatoria necesita una modificación científica revisada: seleccionar con el RNG controlado o congelar y reutilizar la población/flota generada. No se ha cambiado aquí. Comparar variantes con varias semillas y entradas idénticas; si cambian los consumos de azar, compartir una semilla no garantiza los mismos individuos.

Antes de promover una variante: prueba corta de arranque; conservación de población/hogares; balance de viajes abiertos/cerrados por modo; abortos separados de llegadas reales; eventos de stuck y recuperación; ausencia de peatones que dejan cruces ocupados; duración/tiempo final. Los estados de llegada por fallback o sincronización deben distinguirse de recorridos realizados. No evaluar realismo solo por el porcentaje de viajes cerrados.

## Qué conservar en Git

Versionar GAML, herramientas, pruebas, configuraciones pequeñas, esquemas de CSV/manifiestos, documentación e índices de datasets/runs que no expongan información privada. Conservar fuera los CSV completos, copias de bases/cartografía por ejecución, entornos y caches. Los runs necesitan copia de seguridad independiente: `.gitignore` evita subirlos, no los protege.

Ya hay eventos de unos 244 y 280 MB y un `report.json` de unos 105 MB. GitHub [bloquea archivos superiores a 100 MiB](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github). No hacer `git add .` sobre el workspace histórico.

Para empezar, basta Git más archivos de ejecución inmutables, hashes y almacenamiento respaldado. Si se necesitan datasets binarios compartidos en el flujo Git, valorar Git LFS. Si varias personas necesitan recuperar automáticamente versiones de datos y pipelines, valorar [DVC](https://doc.dvc.org/start). Este PR no añade ninguno: no resuelven por sí solos parámetros efectivos desconocidos ni azar SQL.

Pruebas del archivador:

```powershell
python -B -m unittest discover -s tools -p 'test_run_archive.py' -v
```
