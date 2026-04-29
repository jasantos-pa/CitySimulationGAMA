# Objetivo del proyecto

El objetivo de este proyecto es desarrollar un simulador de movilidad urbana capaz de reproducir de manera realista los desplazamientos de la población y la dinámica del tráfico en un entorno urbano.

El modelo se basa en un enfoque de simulación basada en agentes (ABM) utilizando GAMA Platform e integra los principales procesos que intervienen en la movilidad:

- Generación sintética de la población, incluyendo la creación de individuos y hogares a partir de características sociodemográficas
- Asignación de actividades diarias (trabajo, educación, ocio, etc.) en función de variables como la edad u otros atributos
- Generación de flujos de movilidad asociados a dichas actividades
- Elección modal de los desplazamientos
- Interacción entre peatones, vehículos y transporte público dentro de la red urbana

Esto permite analizar el comportamiento emergente del sistema y evaluar el impacto de distintos escenarios de movilidad sobre:

- La congestión del tráfico
- Los tiempos de viaje
- La accesibilidad del sistema de transporte
- Consideración de distintos modos de transporte, incluyendo el transporte público, el vehículo privado y, potencialmente, servicios de taxi como alternativa modal adicional

La red de transporte y el entorno urbano se construyen a partir de datos reales, como OpenStreetMap (OSM), lo que permite dotar al modelo de un alto grado de realismo espacial. Las datos socieconómicos utilizados para la generación de la población y su agrupación en hogares han sido obtenidos de diversas fuentes públicas.
