# gis_db_scripts

## Downloading GIS Data

### Download from city/state GIS source

To begin crawling a new city, you need the following GIS datasets of the region:
- Neighborhood boundaries (optional, helps divide region into segments)
- Building geometries
- Street network lines
- Address points

**If neighborhood data is not provided, create desired polygons in QGIS** 

## Create a new database

Make the name be city\_state ex: detroit\_mi\_ai)
- Connect to postgres database (psql postgres;) 
- Create a new database (CREATE DATABASE detroit\_mi;)
- Add PostGIS extension (CREATE EXTENSION POSTGIS;)

### Import to Postgres

Import the following shapefiles into the db:
    - Addresses
    - Buildings
    - Streets
    - Neighborhoods (optional)
    - Land Use (optional)

 **ALWAYS STORE IN SRID 4326 THEN TRANFORM TO LOCAL SRID**
```
shp2pgsql -I -s <base SRID>:SRID place_addrs.shp addresses_raw | psql -U user -d db
```
**You need to project from the base SRID specified in .prj file to 4326 if it is not already 4326**

Find SRID for distance calculations in the location you are situated using the following link: https://epsg.io **(make sure unit is feet)**

If the file is an ESRI geodb:
```
	ogr2ogr \
		-f "PostgreSQL" \
		PG:"host=localhost port=5432 dbname=db user=colet password=pass" \ 
		<directory name>.gdb \
		 -overwrite -progress --config PG_USE_COPY YES
```
## Cleaning GIS Data
Connect to the previously created database.

Execute script create\_tables.sql to create necessary tables.
We will begin by getting all data from the shapefiles into the previously created tables.

This involves two steps:
    - Find all columns of the shapefile that have the data necessary for the columns of the preconfigured tables.
    - Insert the columns into the the table while filtering based on if the given geometry intersects any of the neighborhood boundaries.

Do this for the following tables:
    - addresses
    - streets
    - buildings

### Insert Neighborhoods
No filtering is required for this. Choose the correct columns then insert into neighborhoods. Delete the raw table after.

Then create the index again with:
```
CREATE INDEX neighborhood_geom_idx ON neighborhoods USING GIST (geom);
```
### Insert Addresses, Buildings, Streets
Use example statement:
```
INSERT INTO addresses (address, geom)
SELECT concat(addr_num, ' ', str_name, ' ', str_suffix), geom 
FROM addresses_raw as ar
JOIN neighborhoods as n
ON ST_Intersects(ar.geom, n.geom);

DELETE FROM addresses
WHERE address LIKE '0 %';
```

## Delete Unecessary Geometries

### Check for Overlapping Buildings
Sometimes buildings polygons can have copies of themselves on top of each other.
This will prevent them from being screenshotted since their inclusion depends on the line of sight intersecting only one building.

```
SELECT * FROM buildings as b
JOIN buildings as b2
ON ST_Intersects(b.geom, b2.geom)
WHERE b.gid != b2.gid;
```

### Delete All Non-Residential Properties 
Since we are only concerned with residential properties, we need to delete any commercial properties.
This can be done using either using a land use or building footprint shapefile that signify the purpose of the entity.
This can only be done by hand since there are many naming conventions for indicating residential properties. 

Example:
```
SELECT DISTINCT use_class FROM landuse_raw; -- View different labels  

DELETE FROM addresses AS a
USING landuse_raw AS lr
WHERE ST_Intersects(a.geom, lr.geom)
AND use_class_ NOT IN ('APARTMENT', 'RESIDENTIAL', 'SENIOR HOUSING'); 
```

### Delete Addresses W/Out Coresponding Building
This one can be tricky. From the GIS data I've seen, the buildings floor prints are normally much more accurate than the address points.
This means we would like the addresses points to be positioned as the centroid of the building.
The tough part comes when address points don't fall within building polygons. 
If it doesn't fall within a polygon, it could mean the buildings was demolished, or that the point is poorly positioned.
In order to include as many address points as you can, you need to set a good distance that represents the difference between a poorly positioned point and the point of a demolished building.

```
-- This statement deletes any addresses not intersecting a building
WITH addr_builds AS (
    SELECT a.gid as addr_gid, b.gid as build_gid FROM addresses AS a
    LEFT JOIN buildings as b
    ON ST_Intersects(b.geom, a.geom)
    WHERE b.gid is null
)
DELETE FROM addresses as a
USING addr_builds as ab
WHERE a.gid = ab.addr_gid; 
```

### Set the Address = Building Centroid Then Delete Overlapping Addresses
Since the building polygon is more accurate, we want the set the address to the center of its corresponding buildings.

```
UPDATE addresses as a
SET geom = ST_Centroid(b.geom)
FROM buildings as b
WHERE ST_Intersects(b.geom, a.geom) 
```

We'd like only a single representative address for each building.
Since multifamily buildings (and apartments) can have more than one
address/unit we want to combine the addresses into a single one that represents the building.
This avoids getting many unnecessary screenshots for multifamily buildings.

Delete overlapping addresses by:

```
WITH intersecting_addrs AS
(
    SELECT a.gid, a2.gid as delete_gid FROM addresses as a
    JOIN addresses as a2
    ON ST_Intersects(a.geom, a2.geom)
    WHERE a.gid != a2.gid
    AND a.gid > a2.gid
)
DELETE FROM addresses as a
USING intersecting_addrs as ia
WHERE a.gid = ia.delete_gid
```

## Create Request Points