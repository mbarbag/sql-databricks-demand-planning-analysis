-- Databricks notebook source
-- MAGIC %md
-- MAGIC ### El área de Demand Planning requiere información con mayor frecuencia de las transacciones de venta y movimientos de mercadería realizadas. Para ello genera reportes  comerciales  a  través  del  área  de Reporting  con  diversos  KPIs,  indicadores segmentando por distintas categorías
-- MAGIC
-- MAGIC ##### [Link al modelo de datos](https://drive.google.com/file/d/1NNaDbxox1cj3vgA6THKbSNgf6pLe7ES-/view)
-- MAGIC
-- MAGIC ###### El modelo cuenta con las siguientes tablas:
-- MAGIC - Clientes: Listado de los clientes dados de alta en el sistema de ventas.
-- MAGIC - Empleados: Maestro de empleados, el mismo esta compuesto por el identificador, nombre, apellido y sucursal en la que trabaja.
-- MAGIC - Locales: Maestro de sucursales compuesta por el identificador, nombre y tipo de local.
-- MAGIC - Productos: Maestro de productos con su precio agrupados por familia de producto.
-- MAGIC - Facturas: Tabla que registra todas las transacciones (ventas). Además contiene, la fecha de en que se realizó la operación, el empleado que hizo la venta, el cliente y la cantidad de productos vendidos
-- MAGIC
-- MAGIC INTEGRANTES:
-- MAGIC
-- MAGIC MANUELA GUERRA
-- MAGIC   

-- COMMAND ----------

USE lab.ventas

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 1. Generar un listado de la cantidad de productos vendidos por año de manera descendente.

-- COMMAND ----------

SELECT 
  EXTRACT(YEAR FROM fecha_venta) as anio,
  SUM(cantidad) AS cantidad
FROM facturas
GROUP BY anio
ORDER BY cantidad DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 2. Top-5 de los empleados que menos vendieron según cantidad vendida, indicando apellido y nombre en un sólo campo. 

-- COMMAND ----------

SELECT
  id_vendedor,
  CASE 
    WHEN apellido ILIKE '%null%' THEN initcap(trim(nombre)) -- Limpiando los nombres con apellido 'null'.
    ELSE initcap(concat(trim(nombre),' ',trim(apellido)))
  END AS nombre_completo,
  SUM(cantidad) AS cantidad_vendida
FROM empleados
  LEFT JOIN facturas ON empleados.id_vendedor = facturas.vendedor -- Usé LEFT JOIN para incluir a todos los empleados, en caso de que existan empleados sin ventas, y así poder mostrarlos en el ranking. 
GROUP BY id_vendedor, nombre_completo
ORDER BY cantidad_vendida -- Muestro en primer lugar el empleado que MENOS vendió.
LIMIT 5;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC  3. ¿Cuántos clientes compraron mes anterior ?

-- COMMAND ----------

/* 
  Mes calendario inmediatamente anterior al mes actual.
  Ejemplo:
  - Fecha actual: Agosto 2025
  - Mes anterior: Julio 2025
  Clientes a contar: los que realizaron al menos una compra en todo el mes de julio.
*/

SELECT 
  COUNT(DISTINCT cliente) -- Para contar solo una vez a cada cliente que haya comprado al menos una vez en el mes anterior
FROM facturas
WHERE EXTRACT(MONTH FROM fecha_venta) = EXTRACT(MONTH FROM current_date()) - 1
  AND EXTRACT(YEAR FROM fecha_venta) = EXTRACT(YEAR FROM (current_date() - INTERVAL '1 month')); -- En caso de que el current_date sea enero, el mes anterior será diciembre del año anterior.

-- COMMAND ----------

-- EXPLORACIÓN: para conocer la fecha de la última venta facturada.
SELECT fecha_venta AS fecha_ultima_venta FROM facturas ORDER BY fecha_venta DESC LIMIT 1;

-- COMMAND ----------

-- Considerando que la última venta facturada corresponde al '2023-09-17', para fines educativos asumiremos el mes anterior a esa fecha. i.e. Agosto de 2023.

SELECT 
  (SELECT fecha_venta AS fecha_ultima_venta FROM facturas ORDER BY fecha_venta DESC LIMIT 1) AS fecha_ultima_venta,
  COUNT(DISTINCT cliente) AS cantidad_clientes_compraron_mes_anterior
FROM facturas
WHERE EXTRACT(MONTH FROM fecha_venta) = EXTRACT(MONTH FROM (SELECT fecha_venta AS fecha_ultima_venta FROM facturas ORDER BY fecha_venta DESC LIMIT 1)) - 1
  AND EXTRACT(YEAR FROM fecha_venta) = EXTRACT(YEAR FROM ((SELECT fecha_venta AS fecha_ultima_venta FROM facturas ORDER BY fecha_venta DESC LIMIT 1) - INTERVAL '1 month'));

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 4. ¿Cuál fue el producto que se vendió mas en el año 2022? ¿A qué familia de producto pertenece?

-- COMMAND ----------

SELECT
  producto,
  nombre,
  familia,
  SUM(cantidad) AS cantidad_total
FROM facturas INNER JOIN productos ON facturas.producto = productos.id_producto
WHERE fecha_venta ILIKE '%2022%'
GROUP BY producto, nombre, familia
ORDER BY cantidad_total DESC
LIMIT 1;

-- COMMAND ----------

-- En caso de que haya más de un producto con la misma cantidad máxima y quiera mostrarlos todos:

SELECT
  producto,
  nombre,
  familia,
  SUM(cantidad) AS cantidad_total
FROM facturas INNER JOIN productos ON facturas.producto = productos.id_producto
WHERE fecha_venta ILIKE '%2022%'
GROUP BY producto, nombre, familia
HAVING cantidad_total = ( -- En caso de que haya un empate en la cantidad total y quiera mostrar todos los productos con la máxima cantidad.
  SELECT MAX(cantidad_total_x_producto)
  FROM (
    SELECT SUM(cantidad) AS cantidad_total_x_producto
    FROM facturas
    WHERE fecha_venta ILIKE '%2022%'
    GROUP BY producto
  )
);


-- COMMAND ----------

-- MAGIC %md
-- MAGIC 5. Siguiendo con el punto anterior ¿Y cuál fue el más rentable?

-- COMMAND ----------

-- La rentabilidad se miden segun las ganancias totales =  precio_unitario x cantidad_total

SELECT
  producto,
  nombre,
  SUM(cantidad) AS cantidad_total_anio_2022,
  precio_unitario,
  cantidad_total_anio_2022 * precio_unitario AS ganancias
FROM facturas INNER JOIN productos ON facturas.producto = productos.id_producto
WHERE fecha_venta ILIKE '%2022%'
GROUP BY producto, nombre, precio_unitario
HAVING ganancias = ( -- En caso de que haya un empate en las ganancias y quiera mostrar todos los productos con la máxima ganancia.
  SELECT MAX(ganancias_x_producto)
  FROM (
    SELECT 
      SUM(cantidad) AS cantidad_total_anio_2022,
      precio_unitario,
      cantidad_total_anio_2022 * precio_unitario AS ganancias_x_producto
    FROM facturas INNER JOIN productos ON facturas.producto = productos.id_producto
    WHERE fecha_venta ILIKE '%2022%'
    GROUP BY producto, precio_unitario
  )
);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 6. Top-10 de sucursales según monto vendido, indicando el monto, ordenado de mayor a menor. El informe debe mostrar:
-- MAGIC - Tipo de local
-- MAGIC - Nombre del local
-- MAGIC - Monto vendido

-- COMMAND ----------

-- EXPLORACIÓN: para notar que el resultado del INNER JOIN múltiple generaba filas repetidas por sucursal según los productos.

SELECT 
  id_sucursal,
  locales.nombre AS nombre_local,
  productos.nombre AS nombre_producto,
  productos.precio_unitario,
  facturas.cantidad
FROM facturas -- Usé INNER JOINs porque sólo me interesan los locales que cuentan con ventas, en caso de que existan locales que NO hayan vendido.
  INNER JOIN productos ON facturas.producto = productos.id_producto
  INNER JOIN empleados ON facturas.vendedor = empleados.id_vendedor
  INNER JOIN locales ON empleados.sucursal = locales.id_sucursal
ORDER BY id_sucursal;

-- COMMAND ----------

-- CONSULTA FINAL: la solución consiste en multiplicar precio_unitario por cantidad y sumar el monto vendido por sucursal.
SELECT
  id_sucursal,
  locales.nombre AS nombre_local,
  locales.tipo AS tipo_local,
  SUM(productos.precio_unitario*facturas.cantidad) AS monto_vendido
FROM facturas -- Usé INNER JOINs porque sólo me interesan los locales que cuentan con ventas, en caso de que existan locales que NO hayan vendido.
  INNER JOIN productos ON facturas.producto = productos.id_producto
  INNER JOIN empleados ON facturas.vendedor = empleados.id_vendedor
  INNER JOIN locales ON empleados.sucursal = locales.id_sucursal
GROUP BY id_sucursal,locales.nombre, locales.tipo
ORDER BY monto_vendido DESC
LIMIT 10;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 7. Se detectaron ventas (facturas) realizadas por vendedores que no estan mas en la compañia (no estan en el maestro de empleados). Por lo tanto, nos solicitan un listado de dichos empleados con la cantidad de ventas (facturas). ¿Cuántos empleados son?

-- COMMAND ----------

SELECT
  vendedor,
  COUNT(num_factura) AS cantidad_ventas
FROM facturas LEFT JOIN empleados ON facturas.vendedor = empleados.id_vendedor
WHERE empleados.id_vendedor IS NULL
GROUP BY vendedor;

-- COMMAND ----------

-- Cantidad de ex-empleados:
SELECT
  COUNT(DISTINCT vendedor) AS numero_ex_empleados
FROM facturas LEFT JOIN empleados ON facturas.vendedor = empleados.id_vendedor
WHERE empleados.id_vendedor IS NULL;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 8. Nos piden clasificar a los vendedores en funcion de su rendimiento (facturación) para el año actual.
-- MAGIC - "Excelente" si el vendedor ha vendido por más de 10 millones de pesos en total.
-- MAGIC - "Bueno" si el vendedor ha vendido entre 5 y 10 millones de pesos en total.
-- MAGIC - "Regular" si el vendedor ha vendido menos de 5 millones de pesos en total.

-- COMMAND ----------

-- EXPLORACIÓN: para conocer el año de la última venta facturada.
SELECT EXTRACT(YEAR FROM fecha_venta) AS anio_ultima_venta FROM facturas ORDER BY fecha_venta DESC LIMIT 1;

-- COMMAND ----------

-- Considerando que la última venta facturada corresponde al año 2023, para fines educativos asumiremos que el año actual es 2023 y no 2025.

SELECT
  vendedor,
  SUM(cantidad*precio_unitario) AS monto_total_2023,
  CASE
    WHEN monto_total_2023 > 10000000 THEN 'Excelente'
    WHEN monto_total_2023 >= 5000000 THEN 'Bueno'
    ELSE 'Regular'
  END AS rendimiento
FROM facturas INNER JOIN productos ON facturas.producto = productos.id_producto
WHERE EXTRACT(YEAR FROM fecha_venta) = 2023
GROUP BY vendedor;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 9. Muestra el número total de facturas para cada vendedor que haya realizado más de 100 ventas el año anterior. Incluye el nombre del vendedor y la cantidad de facturas.

-- COMMAND ----------

-- Considerando que la última venta registrada corresponde al año 2023, para fines educativos asumiremos que el año anterior es 2022.

SELECT
  vendedor,
   CASE 
    WHEN apellido ILIKE '%null%' THEN initcap(trim(nombre)) -- Limpiando los apellidos 'Null'.
    ELSE COALESCE(INITCAP(CONCAT(TRIM(nombre),' ',TRIM(apellido))),'EX-EMPLEADO')
  END AS nombre_completo,
  COUNT(num_factura) AS numero_facturas
FROM facturas LEFT JOIN empleados ON facturas.vendedor = empleados.id_vendedor -- LEFT JOIN para incluir los ex-empleados.
WHERE EXTRACT(YEAR FROM fecha_venta) = 2022
GROUP BY vendedor, nombre_completo
HAVING numero_facturas > 100;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 10. Generar un listado de los clientes que realizaron mas de 50 compras y que su edad sea mayor al premedio de edad del total de nuestra base de clientes. Ordenar el listado por edad de manera ascendente

-- COMMAND ----------

-- EXPLORACIÓN: para conocer la edad promedio de los clientes
SELECT FLOOR(AVG(FLOOR(CAST(current_date() - fecha_nacimiento AS INT) / 365.25))) AS edad_promedio FROM clientes

-- COMMAND ----------

-- CONSULTA FINAL:
SELECT
  cliente,
  nombre,
  apellido,
  fecha_nacimiento,
  FLOOR(CAST(current_date() - fecha_nacimiento AS INT) / 365.25) AS edad, -- Incluye años bisiestos.
  COUNT(num_factura) AS total_compras
FROM facturas INNER JOIN clientes ON facturas.cliente = clientes.id_cliente
GROUP BY cliente, nombre, apellido, fecha_nacimiento
HAVING total_compras > 50
  AND edad > (SELECT FLOOR(AVG(FLOOR(CAST(current_date() - fecha_nacimiento AS INT) / 365.25))) FROM clientes)
ORDER BY edad;
