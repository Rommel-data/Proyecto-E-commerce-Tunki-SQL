-- =====================================================================
-- 03_analisis.sql · Proyecto SQL Tunki · Databricks SQL
-- Catálogo: bd_e_commerce_tunki · Esquema: default
--
-- Entrada : orders_clean y customers_clean (ver 02_limpieza.sql), order_items y products
-- Salida  : las 7 preguntas del equipo comercial, de lo general a lo particular
--
-- Definición de venta : pedidos COMPLETED, medidos con merchandise_value (sin envío)
-- Período             : enero 2024 a enero 2026 (febrero 2026 está incompleto)
-- Comparación         : siempre contra el MISMO mes del año anterior (las ventas son estacionales)
--
-- Cada consulta abre con el mismo bloque:
--   Pregunta · Pide · Universo · KPI · Apoyo · Conceptos (lógica de los datos y control)
--
-- Convención de nombres:
--   _aa = mismo período del año anterior · diferencia_ = cambio absoluto (S/ o pedidos)
--   var_..._pct = cambio relativo (%) · _pp = diferencia entre dos porcentajes
--   participacion_..._pct = parte de un total · efecto_ = parte de una diferencia, en S/
-- =====================================================================

USE CATALOG bd_e_commerce_tunki;
USE SCHEMA default;

/* =====================================================================
   P1 · ¿Cómo evolucionan las ventas, los pedidos y el ticket promedio cada mes?
   Pide      : Gerente comercial · mide el fenómeno (sin hipótesis)
   Universo  : pedidos COMPLETED, enero 2024 a enero 2026
   KPI       : ventas → ventas completadas del mes
   Apoyo     : pedidos · ticket_venta (ventas = pedidos × ticket)
   Conceptos :
     - 1.1: una fila = un mes · 1.2: una fila = un mes del año, un año por columna.
     - ticket_venta = ventas ÷ pedidos (ponderado, no promedio de tickets).
     - 1.2 pivota con agregación condicional: SUM(CASE WHEN anio = ... ), portable a
       cualquier motor. Databricks también tiene PIVOT.
     - Control: ventas 2025 = 3.016.514,59.
   ===================================================================== */

-- 1 RA forma (una serie mensual con todos los meses de cada año en las filas)

SELECT 
    DATE_FORMAT(order_datetime, 'yyyy-MM')                         AS anio_mes,
    count(*)                                                       AS pedidos,          -- pedidos completados
    ROUND(SUM(merchandise_value), 2)                               AS ventas,           -- ventas completadas
    ROUND(SUM(merchandise_value) / count(*), 2)                    AS ticket_venta
FROM orders_clean
WHERE order_datetime < '2026-02-01' AND order_status = 'COMPLETED'
GROUP BY anio_mes
ORDER BY anio_mes;

-- 2 DA forma (un año por columna, para comparar la forma de cada año)
WITH evolucion_ventas_mes AS (
    SELECT
        DATE_TRUNC('MONTH', order_datetime)          AS fecha_mes,
        COUNT(*)                                     AS pedidos,        -- pedidos completados
        SUM(merchandise_value)                       AS ventas          -- ventas completadas
    FROM orders_clean
    WHERE order_status = 'COMPLETED'
      AND order_datetime < '2026-02-01'
    GROUP BY fecha_mes
)
SELECT
    MONTH(fecha_mes)                                                                AS num_mes,
    ELT(MONTH(fecha_mes), 'Ene','Feb','Mar','Abr','May','Jun',
                          'Jul','Ago','Sep','Oct','Nov','Dic')                      AS mes,
    -- Ventas por año
    ROUND(SUM(CASE WHEN YEAR(fecha_mes) = 2024 THEN ventas END), 2)                 AS ventas_2024,
    ROUND(SUM(CASE WHEN YEAR(fecha_mes) = 2025 THEN ventas END), 2)                 AS ventas_2025,
    ROUND(SUM(CASE WHEN YEAR(fecha_mes) = 2026 THEN ventas END), 2)                 AS ventas_2026,
    -- Ticket por año = ventas ÷ pedidos
    ROUND(SUM(CASE WHEN YEAR(fecha_mes) = 2024 THEN ventas END)
        / SUM(CASE WHEN YEAR(fecha_mes) = 2024 THEN pedidos END), 2)                AS ticket_2024,
    ROUND(SUM(CASE WHEN YEAR(fecha_mes) = 2025 THEN ventas END)
        / SUM(CASE WHEN YEAR(fecha_mes) = 2025 THEN pedidos END), 2)                AS ticket_2025,
    ROUND(SUM(CASE WHEN YEAR(fecha_mes) = 2026 THEN ventas END)
        / SUM(CASE WHEN YEAR(fecha_mes) = 2026 THEN pedidos END), 2)                AS ticket_2026
FROM evolucion_ventas_mes
GROUP BY num_mes, mes
ORDER BY num_mes, mes;
-- Resultado: 2025 vendió más que 2024 los 12 meses (+19,2 % en el año), el ticket se mueve
-- entre S/ 147 y S/ 161. Las ventas se mueven por pedidos, no por ticket.

/* =====================================================================
   P2 · ¿Cómo crece cada mes frente al mismo mes del año anterior?
   Pide      : Gerente comercial · H1: la caída de enero es estacional
   Universo  : pedidos COMPLETED, hasta enero 2026
   KPI       : var_ventas_pct → variación interanual de ventas
   Apoyo     : var_pedidos_pct · var_ticket_pct · efecto_pedidos · efecto_ticket
               referencia: promedio 2025 de var_pedidos_pct (16,9 %)
   Conceptos :
     - Una fila = un mes, desde enero 2025 (el primero que tiene año anterior).
     - LAG(...) OVER (PARTITION BY MONTH(fecha_mes) ORDER BY fecha_mes):
       PARTITION BY lo que debe ser igual (el mes), ORDER BY lo que cambia (el año).
       LAG(x, 12) también funciona, pero se rompe si falta un mes.
     - efecto_pedidos = (pedidos − pedidos_aa) × ticket_aa
       efecto_ticket  = (ticket − ticket_aa) × pedidos
     - Control: efecto_pedidos + efecto_ticket = diferencia_ventas, en cada fila.
   ===================================================================== */

WITH evolucion_ventas_mensual as (
    SELECT 
        DATE_TRUNC('MONTH', order_datetime)                             AS fecha_mes,
        COUNT(*)                                                        AS pedidos, -- pedidos completados
        SUM(merchandise_value)                                          AS ventas   -- ventas completadas
    FROM orders_clean
    WHERE order_datetime < '2026-02-01' AND order_status = 'COMPLETED'
    GROUP BY fecha_mes
), comparacion_anio_anterior AS (
    SELECT
        fecha_mes,
        pedidos,
        ventas,
        -- Ticket de venta
        (ventas/pedidos)                                                                AS ticket_venta,
        -- Anio anterior
        LAG(pedidos) OVER(PARTITION BY MONTH(fecha_mes) ORDER BY fecha_mes)             AS pedidos_aa,
        LAG(ventas) OVER(PARTITION BY MONTH(fecha_mes) ORDER BY fecha_mes)              AS ventas_aa,
        LAG(ventas/pedidos) OVER(PARTITION BY MONTH(fecha_mes) ORDER BY fecha_mes)      AS ticket_venta_aa
    FROM evolucion_ventas_mensual
)
SELECT
    DATE_FORMAT(fecha_mes, 'yyyy-MM')                                                       AS anio_mes,
    -- Ventas                                                                               
    ROUND(ventas, 2)                                                                        AS ventas,
    ROUND(ventas_aa, 2)                                                                     AS ventas_anio_anterior,
    ROUND(ventas - ventas_aa, 2)                                                            AS diferencia_ventas,
    -- KPI: Variacion internanual de ventas
    ROUND((ventas - ventas_aa)/ventas_aa * 100, 1)                                          AS var_ventas_anio,
    -- ¿Por que cambio?: pedidos y ticket                                                                  
    ROUND((pedidos - pedidos_aa) / pedidos_aa * 100, 1)                                       AS var_pedidos_anio,
    ROUND((ticket_venta - ticket_venta_aa) / ticket_venta_aa * 100, 1)                        AS var_ticket_anio,
    ROUND((pedidos - pedidos_aa) * ticket_venta_aa, 2)                                        AS  efecto_pedidos,                                                                         
    ROUND((ticket_venta - ticket_venta_aa) * pedidos, 2)                                      AS efecto_ticket
FROM comparacion_anio_anterior
WHERE ventas_aa IS NOT NULL
ORDER BY anio_mes;
-- Resultado: 12 meses entre +9,3 % y +25 %, enero 2026 = −9,4 % (−S/ 14.461,28).
-- Pedidos −13,2 % (efecto −S/ 20.344,10) y ticket +4,4 % (efecto +S/ 5.882,82). H1 refutada.


/* =====================================================================
   P3 · ¿Subieron las cancelaciones o devoluciones en enero 2026?
   Pide      : Gerente comercial · a descartar: la caída es operativa
   Universo  : TODOS los estados (COMPLETED, CANCELLED, RETURNED): la tasa necesita
               el total de pedidos como denominador
   KPI       : tasa_pedidos_perdidos_pct → pedidos cancelados o devueltos ÷ pedidos totales
   Apoyo     : tasa_valor_perdido_pct · ticket_pedido_perdido · diferencia_valor_perdido
               efecto_volumen · efecto_tasa · efecto_ticket
               referencia: rango mensual 3,19 % a 5,81 % · umbral de alerta 5,81 %
   Conceptos :
     - 3.1 = todo el período · 3.2 = un mes por fila · 3.3 = un enero por fila.
     - La tasa se mide en pedidos porque el proceso falla de a un pedido,
       los soles solo dimensionan el impacto.
     - Una diferencia de tasas se expresa en pp, no en %.
     - valor_perdido = pedidos_totales × tasa × ticket_pedido_perdido.
     - Control 3.3: efecto_volumen + efecto_tasa + efecto_ticket = diferencia_valor_perdido.
   ===================================================================== */

-- 3.1 · Resumen del período
-- → ¿Cuánto se pierde normalmente?

SELECT
    COUNT(*)                                                                         AS pedidos_totlaes,   
    ROUND(SUM(merchandise_value), 2)                                                 AS valor_pedidos,  
    -- Perdidas
    COUNT_IF(order_status IN ('CANCELLED', 'RETURNED'))                              AS pedidos_perdidos,
    ROUND(SUM(CASE WHEN order_status IN ('CANCELLED', 'RETURNED')
                   THEN merchandise_value ELSE 0 END), 2)                            AS valor_perdido,
    -- Tasas de perdida
    ROUND(COUNT_IF(order_status IN ('CANCELLED', 'RETURNED')) * 100.0 / COUNT(*), 2) AS tasa_pedidos_perdidos,
    ROUND(SUM(CASE WHEN order_status IN ('CANCELLED', 'RETURNED')
                   THEN merchandise_value ELSE 0 END) * 100
          / SUM(merchandise_value), 2)                                               AS tasa_valor_perdido,
    -- Tickets: ¿se pierden pedidos más caros que el promedio?
    ROUND(SUM(CASE WHEN order_status IN ('CANCELLED', 'RETURNED')
                   THEN merchandise_value ELSE 0 END)
          / COUNT_IF(order_status IN ('CANCELLED', 'RETURNED')), 2)                  AS ticket_pedido_perdido,
    ROUND(SUM(merchandise_value) / COUNT(*), 2)                                      AS ticket_pedido
FROM orders_clean
WHERE order_datetime < '2026-02-01';
-- Resultado: 4,48 % de los pedidos se pierden, el pedido perdido vale S/ 155,04,
-- casi lo mismo que el promedio (S/ 153,22): se pierden pedidos de valor típico.

-- 3.2. Reporte mensual (mes a mes)
-- -> ¿Las pérdidas se mantienen en el tiempo?

WITH evolucion_perdidas_mensual AS (
    SELECT 
        DATE_TRUNC('MONTH', order_datetime)                                                          AS fecha_mes,    
        COUNT(*)                                                                                     AS pedidos_totales,
        SUM(merchandise_value)                                                                       AS valor_pedidos,
        -- Perdidas                                                                                     
        COUNT_IF(order_status IN ('CANCELLED', 'RETURNED'))                                          AS pedidos_perdidos,
        SUM(CASE WHEN order_status IN ('CANCELLED', 'RETURNED') THEN merchandise_value ELSE 0 END)   AS valor_perdido
    FROM orders_clean
    WHERE order_datetime < '2026-02-01'
    GROUP BY fecha_mes
)
SELECT 
    DATE_FORMAT(fecha_mes, 'yyyy-MM')                                                                AS anio_mes,
    -- Tasas de perdidas                                                                             
    ROUND((valor_perdido / valor_pedidos) * 100 , 2)                                                 AS tasa_valor_perdido,
    ROUND((pedidos_perdidos / pedidos_totales) * 100, 2)                                             AS tasa_pedidos_perdidos,
    -- Tickets                                                                                     
    ROUND(valor_perdido / pedidos_perdidos, 2)                                                       AS ticket_pedido_perdido,
    ROUND(valor_pedidos / pedidos_totales, 2)                                                        AS ticket_pedido
FROM evolucion_perdidas_mensual
ORDER BY anio_mes;
-- Resultado: la tasa de pedidos perdidos mueve entre 3,19 % (abr-2025) y 5,81 % (jun-2025), sin tendencia.


-- 3.3 · Enero 2026 frente a enero 2025 (un enero por fila), valorizado
-- → ¿Qué parte del cambio es operativo?

WITH enero AS (
    SELECT
        YEAR(order_datetime)                                                                       AS anio,
        -- Pedidos
        COUNT(*)                                                                                   AS pedidos_totales,
        COUNT_IF(order_status IN ('CANCELLED', 'RETURNED'))                                        AS pedidos_perdidos,
        -- Ventas
        SUM(CASE WHEN order_status IN ('CANCELLED', 'RETURNED') THEN merchandise_value ELSE 0 END) AS valor_perdido
    FROM orders_clean
    WHERE MONTH(order_datetime) = 1            -- solo eneros: el LAG compara enero contra enero
    GROUP BY YEAR(order_datetime)
), comparacion_anio_anterior AS (
    SELECT
        *,
        -- Tasa de pedidos perdidos
        (pedidos_perdidos / pedidos_totales)                                                        AS tasa_pedidos_perdidos,
        -- Ticket de perdidas                                                                       
        (valor_perdido / pedidos_perdidos)                                                          AS ticket_pedido_perdido,
        -- Anio anterior (aa)                                                                            
        LAG(pedidos_totales) OVER (ORDER BY anio)                                                   AS pedidos_totales_aa,
        LAG(valor_perdido) OVER (ORDER BY anio)                                                     AS valor_perdido_aa,
        LAG(pedidos_perdidos / pedidos_totales) OVER (ORDER BY anio)                                AS tasa_pedidos_perdidos_aa,
        LAG(valor_perdido / pedidos_perdidos) OVER (ORDER BY anio)                                  AS ticket_pedido_perdido_aa
    FROM enero
)
SELECT
    CONCAT('Enero ', anio)                                                                          AS mes,
    -- Niveles
    pedidos_totales,
    pedidos_perdidos,
    ROUND(tasa_pedidos_perdidos * 100, 2)                                                           AS tasa_pedidos_perdidos_pct,
    ROUND(valor_perdido, 2)                                                                         AS valor_perdido,
    ROUND(ticket_pedido_perdido, 2)                                                                 AS ticket_pedido_perdido,
    -- Cambio contra el enero anterior
    pedidos_totales - pedidos_totales_aa                                                            AS diferencia_pedidos_totales, -- absoluto (pedidos)
    ROUND((pedidos_totales - pedidos_totales_aa) * 100 / pedidos_totales_aa, 2)                     AS var_pedidos_totales_pct,    -- relativo (pedidos %)
    ROUND((tasa_pedidos_perdidos - tasa_pedidos_perdidos_aa) * 100, 2)                              AS diferencia_tasas_pedidos_perdidos_pp,  -- absoluto (tasas pp)
    ROUND(valor_perdido - valor_perdido_aa, 2)                                                      AS diferencia_valor_perdido,    -- absoluto (valor perdido)
    -- Por qué cambió el valor perdido
    ROUND((pedidos_totales - pedidos_totales_aa) * tasa_pedidos_perdidos_aa * ticket_pedido_perdido_aa, 2)       AS efecto_volumen, -- cuanto entro                                                                                                      
    ROUND((tasa_pedidos_perdidos - tasa_pedidos_perdidos_aa) * pedidos_totales * ticket_pedido_perdido_aa, 2)    AS efecto_tasa,    -- qué proporcion se perdió
    ROUND((ticket_pedido_perdido - ticket_pedido_perdido_aa) * pedidos_perdidos, 2)                              AS efecto_ticket   -- cuanto valia lo perdido 
FROM comparacion_anio_anterior 
ORDER BY anio;
-- Resultado: la tasa BAJÓ de 5,39 % a 4,23 % (−1,16 pp, efecto −S/ 1.440,11). Se descarta
-- la causa operativa: la caída nació antes, en la entrada de pedidos (−14,22 %).


/* =====================================================================
   P4 · ¿Cuánto vendió cada categoría en enero 2026 frente a enero 2025?
   Pide      : Supervisores · H2: la caída se concentra en algunas categorías
   Universo  : pedidos COMPLETED de enero 2025 y enero 2026 · ventas = quantity × unit_price
   KPI       : var_ventas_pct → variación interanual de ventas de la categoría
   Apoyo     : diferencia_ventas (S/) · participacion_caida_pct · var_total_pct
               referencia: var_total_pct = −9,36 (variación del total, ponderada)
   Conceptos :
     - Una fila = una categoría (7).
     - Se puede usar LAG: las 7 categorías venden todos los meses, no hay huecos.
     - LAG particiona por categoría Y mes: solo por categoría compararía contra diciembre.
     - Referencia ponderada (total), no promedio simple de las 7 variaciones (−11,8 %).
     - Las 7 categorías cayeron: aquí caída neta = caída bruta.
     - Control: SUM(diferencia_ventas) = −14.461,28 · SUM(participacion_caida_pct) = 100.
   ===================================================================== */

WITH evolucion_categorias_ventas AS (
    SELECT
        DATE_TRUNC('MONTH', o.order_datetime)              AS fecha_mes,           -- En funcion de MES
        p.category                                         AS categoria,                                          
        SUM(oi.quantity*oi.unit_price)                     AS ventas               -- Ventas completadas              
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
    JOIN orders_clean o ON o.order_id = oi.order_id
    WHERE o.order_datetime < '2026-02-01' AND o.order_status = 'COMPLETED'
    GROUP BY fecha_mes, categoria
    ORDER BY fecha_mes
), comparacion_anio_anterior AS (
    SELECT
        fecha_mes,
        categoria,
        ventas,
        -- Mismo mes del anio anterior, misma categoria
        -- PARTITION BY lo que debe ser igual (categoria y mes) · ORDER BY lo que cambia (año)
        LAG(ventas) OVER (PARTITION BY categoria,MONTH(fecha_mes) ORDER BY fecha_mes) ventas_aa
    FROM evolucion_categorias_ventas
), enero_2026 AS (
    SELECT 
        DATE_FORMAT(fecha_mes, 'yyyy-MM')                                     AS anio_mes,
        categoria,                                                            
        ventas,                                                                
        ventas_aa,                                                            
        ventas - ventas_aa                                                    AS diferencia_ventas,
        (ventas - ventas_aa) / ventas_aa * 100                                AS var_ventas_pct,
        -- Las ventanas se calculan DESPUÉS del WHERE: suman solo las 7 categorías de enero 2026
        (ventas - ventas_aa) * 100 / (SUM(ventas - ventas_aa) OVER ())        AS participacion_caida_pct,
        ((SUM(ventas) OVER ()) / (SUM(ventas_aa) OVER ()) - 1) * 100          AS var_total_prom_pct
    FROM comparacion_anio_anterior
    WHERE fecha_mes = '2026-01-01'
    ORDER BY diferencia_ventas   
)
SELECT
    categoria,
    ROUND(ventas, 2)                                 AS ventas,                   -- nivel (S/)
    ROUND(ventas * 100 /(SUM(ventas) OVER()), 2)     AS prop_ventas,              -- proporción (%)
    ROUND(ventas_aa, 2)                              AS ventas_aa,                -- nivel (S/)
    ROUND(diferencia_ventas, 2)                      AS diferencia_ventas,        -- absoluta (S/)
    ROUND(var_ventas_pct, 2)                         AS var_ventas_pct,           -- relativa (%) · KPI
    ROUND(participacion_caida_pct, 2)                AS participacion_caida_pct,  -- participación (%)
    ROUND(var_total_prom_pct, 2)                     AS var_total_prom_pct,       -- referencia (%)
    ROUND(var_ventas_pct - var_total_prom_pct, 2)    AS diferencia_vs_total_pp    -- absoluta (pp)
FROM enero_2026
ORDER BY diferencia_ventas;
-- Resultado: menaje, decoración y muebles explican el 79,4 % de la caída (S/ 11.482,56).
-- Muebles (−27,3 %) y cocina_electro (−26,6 %) caen casi 3 veces más que el total.

/* =====================================================================
   P5 · ¿Qué productos perdieron más ventas entre enero 2025 y enero 2026?
   Pide      : Supervisores · H2: ¿la caída de las categorías se concentra en pocos productos?
   Universo  : solo los 132 productos que cayeron (diferencia_ventas < 0)
   KPI       : participacion_caida_bruta_acum_pct → ¿cuántos productos explican el 80 % de la caida?
   Apoyo     : participacion_caida_bruta_pct · diferencia_ventas (S/)
               referencias: reparto parejo 0,76 % (100 ÷ 132) · umbral de concentración 80 %
   Conceptos :
     - Una fila = un producto, por product_id: 400 IDs y solo 208 nombres.
     - Sin LAG: 51 productos vendieron en enero 2025 y nada en enero 2026, no tienen
       fila ese mes y LAG los pierde. Con SUM(CASE ...) + COALESCE aparecen con 0.
     - Los denominadores se calculan en el CTE ranking, ANTES del WHERE: las ventanas
       corren después del WHERE de su propio nivel.
     - Se excluyen las subidas: mezclar signos invalida la participación.
       diferencia_neta = Σ (ventas − ventas_aa) de todos          → −14.461,28
       caida_bruta     = Σ (ventas − ventas_aa) de los que cayeron → −40.189,02
     - Control: la acumulada del último puesto = 100,
       cayeron −40.189,02 + subieron +25.727,74 = −14.461,28.
   ===================================================================== */

WITH comparacion_enero_anio_anterior AS (
    SELECT
        p.product_id                                          AS producto_id,
        p.product_name                                        AS producto,
        p.category                                            AS categoria,
        COALESCE( SUM( CASE WHEN YEAR(o.order_datetime) = 2026 THEN oi.quantity END), 0)    AS unidades,
        COALESCE( SUM( CASE WHEN YEAR(o.order_datetime) = 2025 THEN oi.quantity END), 0)    AS unidades_aa,
        COALESCE( SUM( CASE WHEN YEAR(o.order_datetime) = 2026 THEN oi.quantity*oi.unit_price END), 0) AS ventas,
        COALESCE( SUM( CASE WHEN YEAR(o.order_datetime) = 2025 THEN oi.quantity*oi.unit_price END), 0) AS ventas_aa
    FROM order_items oi
    JOIN products p     ON oi.product_id = p.product_id
    JOIN orders_clean o ON o.order_id = oi.order_id
    WHERE o.order_status = 'COMPLETED' AND MONTH(o.order_datetime) = 1 AND year(o.order_datetime) IN (2025, 2026)
    GROUP BY p.product_id, p.product_name, p.category
), ranking AS (
    SELECT
        *,
        ventas - ventas_aa                                  AS diferencia_ventas,
        ROW_NUMBER() OVER (ORDER BY ventas - ventas_aa)     AS puesto,
        SUM(LEAST(ventas - ventas_aa, 0)) OVER ()           AS caida_bruta      -- solo los que cayeron
    FROM comparacion_enero_anio_anterior
)
SELECT
    puesto,
    producto_id,
    producto,
    categoria,
    unidades,
    unidades_aa,
    ROUND(ventas, 2)                                                               AS ventas,
    ROUND(ventas_aa, 2)                                                            AS ventas_aa,
    ROUND(diferencia_ventas, 2)                                                    AS diferencia_ventas,
    ROUND(diferencia_ventas * 100 / caida_bruta, 2)                                AS participacion_caida_bruta_pct,
    ROUND((SUM(diferencia_ventas) OVER (ORDER BY puesto)) * 100 / caida_bruta, 2)  AS participacion_caida_bruta_acum_pct
FROM ranking
WHERE diferencia_ventas < 0
ORDER BY puesto;
-- Resultado: hacen falta 55 de 132 productos (41,7 %) para llegar al 80 % de la caída bruta,
-- el que más cae explica 5,32 %. La caída está repartida: H2 se cumple por categoría,
-- no por producto.

-- 5.1 · Puente: de la caída bruta a la caída neta (control contra la P2 y la P4)
WITH ventas_producto_enero AS (
    SELECT
        p.product_id,
        COALESCE(SUM(CASE WHEN YEAR(o.order_datetime) = 2026 THEN oi.quantity * oi.unit_price END), 0)  AS ventas,
        COALESCE(SUM(CASE WHEN YEAR(o.order_datetime) = 2025 THEN oi.quantity * oi.unit_price END), 0)  AS ventas_aa
    FROM order_items oi
    JOIN products p     ON p.product_id = oi.product_id
    JOIN orders_clean o ON o.order_id   = oi.order_id
    WHERE o.order_status = 'COMPLETED'
      AND MONTH(o.order_datetime) = 1
      AND YEAR(o.order_datetime) IN (2025, 2026)
    GROUP BY p.product_id
)
SELECT
    CASE WHEN ventas - ventas_aa < 0 THEN '1. Cayeron'
         WHEN ventas - ventas_aa > 0 THEN '2. Subieron'
         ELSE                             '3. Sin cambio' END    AS grupo,
    COUNT(*)                                                    AS productos,
    ROUND(SUM(ventas - ventas_aa), 2)                           AS diferencia_ventas
FROM ventas_producto_enero
GROUP BY grupo
ORDER BY grupo;
-- Resultado: cayeron 132 (−40.189,02) · subieron 147 (+25.727,74) · neto −14.461,28.

/* =====================================================================
   P6 · ¿En qué región y en qué rango de monto de pedido cayó enero 2026?
   Pide      : Supervisores · H3: la caída se concentra en una región
   Universo  : pedidos COMPLETED de enero 2025 y enero 2026
   KPI       : var_pedidos_pct → variación interanual de pedidos, por región y rango
   Apoyo     : diferencia_ventas (S/) · diferencia_region · participacion_en_region_pct
   Conceptos :
     - Una fila = región × rango de monto (2 × 2 = 4 filas).
     - Se trabaja con orders_clean (un pedido por fila): el monto y la región son del
       pedido. Unir con order_items repetiría el monto una vez por línea.
     - Corte de rango: S/ 79, el umbral de envío gratis vigente en 2025 en las dos
       regiones. Es la única política conocida antes de analizar enero 2026,
       la P7 muestra que en provincia el umbral cambió.
     - Sin LAG: los pedidos de 2026 no son los de 2025, SUM(CASE ...) pone los dos
       eneros en la misma fila.
     - Participación DENTRO de la región: Lima sube y provincia cae, mezclar signos
       invalida la participación.
     - Control: SUM(diferencia_ventas) = −14.461,28 = Lima +21.381,15 + provincia −35.842,43.
   ===================================================================== */

WITH pedidos_enero AS (                                 -- Paso 1: un pedido por fila, con su región y su rango
    SELECT
        o.order_id,
        c.shipping_region                                  AS region,
        YEAR(o.order_datetime)                             AS anio,
        o.merchandise_value                                AS ventas,
        CASE
            WHEN o.merchandise_value < 79  THEN '1. Menos de S/ 79'
            ELSE                                '2. S/ 79 a más'
        END                                                AS rango_monto
    FROM orders_clean o
    JOIN customers_clean c   ON o.customer_id = c.customer_id
    WHERE o.order_status = 'COMPLETED' AND MONTH(o.order_datetime) = 1 AND year(o.order_datetime) IN (2025, 2026)
    ORDER BY o.order_id, c.shipping_region, YEAR(o.order_datetime)
), region_rango_anio_anterior AS (           -- Paso 2: los dos eneros como columnas
    SELECT                                               
        region,
        rango_monto,
        count_if(anio = 2026)                                     AS pedidos,
        count_if(anio = 2025)                                     AS pedidos_aa,
        COALESCE(SUM(CASE WHEN anio = 2026 THEN ventas END), 0)   AS ventas,
        COALESCE(SUM(CASE WHEN anio = 2025 THEN ventas END), 0)   AS ventas_aa
    FROM pedidos_enero
    GROUP BY region, rango_monto
    ORDER BY region, rango_monto
), comparacion AS (                                 -- Paso 3: diferencias y totales con ventanas
    SELECT
        *,
        (ventas - ventas_aa)                                    AS diferencia_ventas,
        SUM(ventas - ventas_aa) OVER (PARTITION BY region)      AS diferencia_region  -- subtotal de su región
    FROM cregion_rango_anio_anterior
)
SELECT                                                     -- Paso 4: indicadores y redondeo final
    region,
    rango_monto,
    pedidos,
    pedidos_aa,
    ROUND((pedidos - pedidos_aa) * 100.0 / pedidos_aa, 2)       AS var_pedidos_pct,
    ROUND(ventas, 2)                                            AS ventas,
    ROUND(ventas_aa, 2)                                         AS ventas_aa,
    ROUND(diferencia_ventas, 2)                                 AS diferencia_ventas,
    ROUND(diferencia_region, 2)                                 AS diferencia_region,
    ROUND(diferencia_ventas * 100 / diferencia_region, 2)       AS participacion_en_region_pct
FROM comparacion
ORDER BY region, rango_monto;
-- Resultado: provincia pierde 56 % de sus pedidos (441 → 194) y S/ 35.842, Lima crece en
-- los dos rangos. El tramo de S/ 79 a más explica el 91,6 % de la caída de provincia. H3 confirmada.

/* =====================================================================
   P7 · ¿Qué cambió en esa región entre 2025 y enero 2026?
   Pide      : Gerente comercial · busca la causa de la caída de provincia (P6)
   Universo  : pedidos COMPLETED de enero 2025 y enero 2026, por región
   KPI       : 7.1 umbral y tarifa de envío por región y año   → ¿qué cambió?
               7.2 var_pedidos_pct por tramo de la política     → ¿a quién afectó?
               7.3 diferencia_margen_contribucion de provincia  → ¿cuánto le costó a Tunki?
   Apoyo     : efecto_margen_bruto · efecto_comision · efecto_subsidio_envio
               referencia: Lima, que no cambió su política (grupo de control)
   Conceptos :
     - La política de envío no está en ninguna tabla: se deduce de los datos.
       El pedido más caro que pagó envío y el más barato que no pagó marcan el umbral.
     - Los tramos de 7.2 salen de 7.1: S/ 79 (umbral de 2025) y S/ 150 (el nuevo umbral
       de provincia está entre S/ 147,84 y S/ 152,41). Con S/ 149 el resultado no cambia.
       El mismo corte se aplica a los dos años: compara el mismo grupo de pedidos
       antes y después del cambio.
     - subsidio_envio = costo real del envío − envío cobrado: lo que Tunki pone de su bolsillo.
     - margen_contribucion = margen bruto − comisión de pago − subsidio de envío.
       Se compara margen contra subsidio, no ventas contra subsidio: ventas es ingreso
       y el subsidio es costo.
     - Control 7.3: margen_contribucion_aa + los tres efectos = margen_contribucion.
   ===================================================================== */

-- 7.1 · ¿Qué cambió? Política de envío deducida por región y año
WITH pedidos_enero AS (
    SELECT
        c.shipping_region                AS region,
        YEAR(o.order_datetime)           AS anio,
        o.merchandise_value              AS ventas,
        o.shipping_fee_charged           AS envio_cobrado
    FROM orders_clean o
    JOIN customers_clean c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'COMPLETED' AND MONTH(o.order_datetime) = 1 AND YEAR(o.order_datetime) IN (2025, 2026)
    ORDER BY region, anio
)
SELECT
    region,
    anio,
    MAX(envio_cobrado)                                            AS tarifa_envio,
    ROUND(MAX(CASE WHEN envio_cobrado > 0 THEN ventas END), 2)    AS monto_max_con_envio,
    ROUND(MIN(CASE WHEN envio_cobrado = 0 THEN ventas END), 2)    AS monto_min_envio_gratis,
    count_if(envio_cobrado > 0)                                   AS pedidos_con_envio,
    count_if(envio_cobrado = 0)                                   AS pedidos_envio_gratis
FROM pedidos_enero
GROUP BY region, anio
ORDER BY region, anio;
-- Resultado: en provincia el envío gratis pasó de "desde S/ 79" a "desde ~S/ 150" y la tarifa
-- de S/ 19,90 a S/ 29,90. Los pedidos con envío gratis bajaron de 304 a 90. Lima, sin cambios.


-- 7.2 · ¿A quién afectó? Pedidos por tramo de la política
WITH pedidos_enero AS (
    SELECT
        DATE_FORMAT(o.order_datetime, 'yyyy-MM-dd')        AS fecha,    
        o.order_id                                         AS nro_pedido,
        c.shipping_region                                  AS region,
        YEAR(o.order_datetime)                             AS anio,
        o.merchandise_value                                AS ventas,
        CASE
            WHEN o.merchandise_value < 79  THEN '1. Menos de S/ 79'   -- siempre pagó envío
            WHEN o.merchandise_value < 150 THEN '2. S/ 79 a 149'      -- en provincia perdió el envío gratis
            ELSE                                '3. S/ 150 a más'     -- siempre tuvo envío gratis
        END                                                AS tramo
    FROM orders_clean o
    JOIN customers_clean c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'COMPLETED' AND MONTH(o.order_datetime) = 1 AND YEAR(o.order_datetime) IN (2025, 2026)
    ORDER BY fecha, nro_pedido, region, anio
), region_tramo AS (
    SELECT
        region,
        tramo,
        count_if(anio = 2026)                                   AS pedidos,
        count_if(anio = 2025)                                   AS pedidos_aa,
        COALESCE(SUM(CASE WHEN anio = 2026 THEN ventas END), 0) AS ventas,
        COALESCE(SUM(CASE WHEN anio = 2025 THEN ventas END), 0) AS ventas_aa
    FROM pedidos_enero
    GROUP BY region, tramo
)
SELECT
    region,
    tramo,
    pedidos,
    pedidos_aa,
    ROUND((pedidos - pedidos_aa) *100.0 / pedidos_aa, 2)                                                            AS var_pedidos_pct,
    ROUND(ventas - ventas_aa, 2)                                                                                    AS diferencia_ventas
FROM region_tramo
ORDER BY region, tramo;
-- Resultado: en provincia, el tramo que perdió el envío gratis cae −78,3 % (más que su región,
-- −56,0 %), los otros dos caen ≈ −46 %. En Lima los tres tramos crecen.


-- 7.3 · ¿Cuánto le costó? Margen de contribución de enero, de 2025 a 2026
WITH pedidos_enero AS (
    SELECT
        c.shipping_region                                       AS region,
        YEAR(o.order_datetime)                                  AS anio,
        o.merchandise_value - o.product_cost                    AS margen_bruto,
        o.payment_fee                                           AS comision_pago,
        o.shipping_cost_actual - o.shipping_fee_charged         AS subsidio_envio
    FROM orders_clean o
    JOIN customers_clean c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'COMPLETED' AND MONTH(o.order_datetime) = 1 AND YEAR(o.order_datetime) IN (2025, 2026)
), region_anio AS (
    SELECT
        region,
        SUM(CASE WHEN anio = 2025 THEN margen_bruto   END)      AS margen_bruto_aa,
        SUM(CASE WHEN anio = 2026 THEN margen_bruto   END)      AS margen_bruto,
        SUM(CASE WHEN anio = 2025 THEN comision_pago  END)      AS comision_pago_aa,
        SUM(CASE WHEN anio = 2026 THEN comision_pago  END)      AS comision_pago,
        SUM(CASE WHEN anio = 2025 THEN subsidio_envio END)      AS subsidio_envio_aa,
        SUM(CASE WHEN anio = 2026 THEN subsidio_envio END)      AS subsidio_envio
    FROM pedidos_enero
    GROUP BY region
)
SELECT
    region,
    ROUND(margen_bruto_aa - comision_pago_aa - subsidio_envio_aa, 2)     AS margen_contribucion_aa,
    ROUND(margen_bruto - margen_bruto_aa, 2)                             AS efecto_margen_bruto,    -- pedidos y ventas perdidos
    ROUND(comision_pago_aa - comision_pago, 2)                           AS efecto_comision,        -- menos comisión pagada
    ROUND(subsidio_envio_aa - subsidio_envio, 2)                         AS efecto_subsidio_envio,  -- flete que Tunki dejó de pagar
    ROUND(margen_bruto - comision_pago - subsidio_envio, 2)              AS margen_contribucion,
    ROUND((margen_bruto - comision_pago - subsidio_envio) - (margen_bruto_aa - comision_pago_aa - subsidio_envio_aa), 2)  AS diferencia_margen_contribucion
FROM region_anio
ORDER BY region;
-- Resultado: provincia ahorró S/ 6.837,98 de flete y perdió S/ 16.436,93 de margen bruto:
-- margen de contribución −S/ 8.283,70 en un mes. Lima, +S/ 8.882,77.