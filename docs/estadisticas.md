# Fuentes estadísticas empleadas en el modelo

La construcción de la población sintética y de sus patrones de comportamiento se ha basado en la integración de distintas fuentes estadísticas oficiales, con el objetivo de garantizar la coherencia y el realismo del modelo.

En particular, se han utilizado datos procedentes del Instituto Nacional de Estadística (INE) y de estudios regionales, que permiten caracterizar tanto la estructura demográfica y social de la población como sus dinámicas familiares y de movilidad.

A continuación, se describen las principales fuentes empleadas y su contribución específica dentro del modelo.


- **Censos de población y viviendas 2021 – Hogares (INE)**  
  Proporciona información sobre el tamaño y la estructura de los hogares a nivel municipal.  
  Permite definir la organización de la población en unidades de convivencia, siendo clave para generar una población sintética realista en términos de composición familiar.

- **Censo anual de población 2021–2023 – Distribución por edad (INE)**  
  Ofrece la distribución de la población por grupos de edad quinquenales.  
  Se utiliza para asignar edades a los agentes de forma coherente, influyendo directamente en sus comportamientos y patrones de actividad.

- **Censo anual de población 2021–2023 – Distribución por sexo (INE)**  
  Proporciona la proporción de hombres y mujeres por territorio.  
  Permite reproducir una distribución realista por sexo, con impacto en la estructura de los hogares y las relaciones entre agentes.

- **Censos de población y viviendas 2021 – Tipo de pareja (INE)**  
  Recoge la distribución de parejas según su tipología.  
  Permite reflejar la diversidad en las estructuras familiares.

- **Movimiento Natural de la Población – Nacimientos (INE)**  
  Proporciona información sobre nacimientos en función de la edad de la madre.  
  Se utiliza para estimar la edad de los progenitores y reconstruir relaciones familiares coherentes.

- **Indicadores de fecundidad – Edad media a la maternidad (INE)**  
  Aporta referencias sobre la edad media a la maternidad.  
  Se emplea como apoyo para estimar diferencias de edad entre hermanos y mejorar la consistencia familiar.

- **Estadística de matrimonios – Diferencia de edad en parejas (INE)**  
  Proporciona información sobre la diferencia de edad entre cónyuges.  
  Permite generar relaciones de pareja más realistas dentro del modelo.

- **Atlas de la movilidad residencia-trabajo de la Comunidad de Madrid (2024)**  
  Analiza los desplazamientos entre lugar de residencia y trabajo.  
  Permite modelar flujos de movilidad intermunicipal, especialmente relevantes en entornos metropolitanos.

- **Encuesta de Movilidad de la Comunidad de Madrid (edM2018)**  
  Proporciona información detallada sobre patrones de movilidad y distribución modal.  
  Se utiliza para modelar la elección modal de los agentes en función de variables como la distancia.

- **Datos del Ayuntamiento de Leganés – Distribución residencial**  
  Proporcionan información sobre la distribución espacial de la población en el municipio.  
  Permiten asignar probabilidades de residencia y ubicar a los agentes de forma coherente con la realidad urbana.

## Escalabilidad

Todas las estadísticas utilizadas en el modelo se almacenan en una base de datos estructurada que recoge, para cada fuente, distribuciones porcentuales asociadas a distintos ámbitos territoriales de España (principalmente a nivel municipal o de comunidad autónoma, según la disponibilidad de los datos del INE).

Este enfoque permite adaptar el sistema a diferentes ciudades o regiones. Gracias a esta organización, el proceso de generación de la población sintética y de los patrones de movilidad es reproducible y escalable.