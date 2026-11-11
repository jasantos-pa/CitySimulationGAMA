# Variantes y procedencia

Inventario de lectura del workspace de investigación, contrastado el 10 de noviembre de 2026. Las fechas de edición no certifican estabilidad ni identifican por sí solas el código de una ejecución. Esta página describe archivos observados; no convierte las diferencias textuales en una genealogía demostrada.

El registro legible por herramientas está en `research/variants/catalog.json`: 26 archivos GAML, con SHA-256 de bytes originales, hash de blob normalizado a LF, tamaño, líneas, fecha observada y estado de seguimiento por Git. No contiene conversaciones, rutas personales ni resultados de simulación.

## Referencias verificadas

- GitHub `main`: `2541627cbdd321fea91f0b6502206ed6e8f2eb68`, merge del PR #2, 29 de abril de 2026.
- Rama publicada `feature/production-updated-model`: `1c93303dd990366a2f5d77ca682726eb7c3d3a92`. Su árbol coincide con el de ese `main`.
- El workspace original seguía en esa rama, con modificaciones sin commit en `CitySimulation-updated.gaml`, `CitySimulation-updated-activities.gaml` y `todo.txt`.
- Solo esos dos modelos GAML están versionados en el árbol publicado. La regla `/models/*` excluye las demás variantes y numerosas herramientas/resultados locales.
- No había tags ni releases publicados al realizar la revisión.

El punto de partida de este PR es el `main` publicado y limpio. Los modelos científicos no se modifican ni sustituyen. Los archivos locales ignorados permanecen en su ubicación original; este inventario **no es una copia de seguridad** de ellos.

## Comparación de variantes

Todos los nombres de la tabla pertenecen a `models/` y terminan en `.gaml`. Son observaciones del código local, no una afirmación de que cada fila descienda de la anterior.

| Archivo o familia | Diferencias observadas y utilidad |
| --- | --- |
| `CitySimulation-MVP`, `CitySimulation-MVP2` | Primeros modelos de movilidad; MVP2 integra registro de eventos/viajes y control de prioridades adicional. |
| `CitySimulation` | Añade comparación población/referencias, horarios y métricas demográficas frente a MVP2. |
| `population` | Alternativa de generación de población: normalización de sexo/tamaño de hogar y reparto por restos mayores. |
| `CitySimulation-population` | Planes demográficos y de hogares, grupos de candidatos, relaciones familiares y exportación del registro de hogares. |
| `CitySimulation-population-modal` | Probabilidades modales y diferencias de edad en parejas, gestión de flota y recuperación de viajes fallidos. |
| `CitySimulation-population-modal2` | Asignación explícita de parejas, familias monoparentales, hijos y restricciones entre hermanos. |
| `CitySimulation-population-modal3` | Restricciones familiares duras, relajación gradual, sesgos de edad y alternativas cuando no se consigue un hogar válido. |
| `CitySimulation-population-modal4` | Cuotas para diferencias de edad en parejas y tratamiento de intervalos de edad. |
| `CitySimulation-population-modal5` | Añade balance de rangos de edad frente a modal4. Su nombre no demuestra que sea sucesor cronológico de todos los modal4. |
| `CitySimulation-population-modal4clean` | Carga cartografía limpia, añade sondas de rutas y CSV de pares origen/destino fallidos. |
| `CitySimulation-population-modal4cleanHEADLESS` | Añade experimento `RouteProbe` y configuración utilizable por los planes XML de sondas existentes. |
| `CitySimulation-population-modal4cleanWOF` | Añade abortos explícitos sin ruta y diagnósticos de conectividad; elimina algunas recuperaciones forzadas frente a clean. No equivale a ausencia de todos los fallbacks. |
| `CitySimulation-population-modal6` | Revisa planificación de coches: recuperación por radio y límite de intentos frente a WOF. |
| `CitySimulation-updated`, `CitySimulation-updated2` | Línea simplificada respecto a modal6. La copia local de updated incluye cambios en trenes, carga de taxis y acompañantes; updated2 carece de parte de esas correcciones locales. |
| `CitySimulation-updated-activities copy` | Alternativa conservadora con cierre de estado de viaje; no incorpora toda la planificación alternativa ni coordinación grupal del archivo activities. |
| `CitySimulation-updated-activities` | Coordinación de acompañantes y retorno de actividades, candidatos alternativos de ruta. La copia local difiere del blob publicado `53f43a0d56c1d4404ab612e146ed98b14fcf1232`. |
| `CitySimulation-updated-activities2` | Tiempos de actividad continuos, identificación del día con año/mes/día y revisión de clasificación de viajes largos. |
| `CitySimulation-updated-activities2-solvingStuck` | Instrumentación detallada de coches parados, razones estimadas y CSV específico. Una razón estimada no demuestra causalidad. |
| `CitySimulation-updated-activities2-solvingStuck copy` | Añade ventana de aristas/nodos, sincronización de acompañantes al llegar, liberación de pasos de cebra y cartografía `Leganes_clean/definitivo`. |
| `gorrion` | Variante de integración con `Leganes_gorrion`, interruptores de logging y experimentos de rendimiento/mapa. Tiene mejoras propias; no es equivalente a solvingStuck copy. |
| `Logger` | Componente auxiliar de registro histórico, no simulador completo. |
| `GAMA_Graph_Validation/*` | Tres modelos de validación de grafos/conducción, separados del simulador poblacional. |

Los cuatro ejemplos GAML de la raíz y `models.zip` son material auxiliar/histórico. El ZIP contiene MVP, MVP2, CitySimulation y Logger antiguos, no la última línea de investigación.

## Candidato local y divergencias

La referencia recomendada para **reanudar la investigación local**, pendiente de validación, es `models/CitySimulation-updated-activities2-solvingStuck copy.gaml`: 8.255 líneas, edición observada el 6 de junio de 2026 a las 23:52:37, SHA-256 `1caf33774258da4600382293dafe68403f54cfbdc63290f9be2ff3e6630392ba`. La selección combina cambios de código, contexto histórico de trabajo y presencia en los archivos recientes de GAMA. No se declara versión estable.

Frente a `solvingStuck.gaml` presenta 160 líneas añadidas y 33 eliminadas en el diff de Git. Usa carreteras y cruces de `Leganes_clean/definitivo`, calles del directorio superior, edificios, ferrocarril y `SimuCityDB_en_clean.db`. Las seis referencias existían localmente.

`gorrion.gaml`, editado el 3 de junio, tiene SHA-256 `edbfe22bb26b91a343ec7b00f578f9c9632315c4c8f864374a42052cc8a01ba0`. Contiene experimentos `Leganes_perf_probe` y `Leganes_debug_map` y desactiva por defecto varios registros costosos. La copia solvingStuck contiene acciones de sincronización grupal y liberación de cruces que gorrion no contiene con esos nombres. Se deben comparar mejoras por separado, no reemplazar automáticamente un archivo por otro.

La cartografía limpia y la base `SimuCityDB_en_clean.db` no estaban versionadas; GitHub conserva `Maps/Leganes` y `SimuCityDB.db`. Por tanto, un clon limpio no reúne las entradas que piden los modelos publicados. Hace falta un conjunto de entradas identificado y distribuible para reproducirlos.

## Organización propuesta, sin migración automática

Mantener un repositorio del simulador y otro futuro para generación de redes. El simulador consumirá versiones identificadas de las redes, con hashes y referencia al commit productor. La transformación de redes no se incorpora a este PR.

- `models/`: modelo base y componentes compartidos cuando exista una refactorización validada.
- `research/`: variantes científicas realmente distintas y fichas de hipótesis, comparación y estado. Antes de trasladar nada, preservar todas las copias y su cartografía.
- `experiments/`: configuraciones de escenarios, semillas y criterios de parada; cambiar parámetros no exige duplicar todo el GAML.
- `data/manifest.json`: catálogo propuesto de entradas, procedencia, hashes y forma de obtenerlas. Los datos grandes se conservan en almacenamiento apropiado.
- `tools/`: preparación, archivado y análisis; este PR añade únicamente el archivador.
- `runs/<run_id>/`: instantánea ejecutable y resultados aislados, fuera de Git.
- `docs/`: métodos, decisiones y limitaciones. Los informes científicos pequeños pueden versionarse sin incluir CSV masivos.

Usar `main` como baseline revisado; ramas temporales por mejora y PRs sin mezclar hipótesis. Una configuración/semilla identifica un escenario/réplica; un commit identifica código, no una ejecución. Las variantes experimentales de larga duración necesitan nombre y documentación, no sucesivas copias ambiguas.

Primero: copia de seguridad verificada de todo el workspace, incluidos ignorados; después catalogar y conservar variantes. Incorporar cada mejora con comparación de métricas y revisión. No reescribir el historial existente ni atribuir retrospectivamente parámetros desconocidos a resultados antiguos.
