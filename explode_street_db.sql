CREATE TABLE IF NOT EXISTS request_points (
	id serial PRIMARY KEY,
	street_id integer,
	geom geometry UNIQUE
);

CREATE OR REPLACE FUNCTION explode_street(
    street_id integer, 
    street_geom geometry,
    distance numeric) 
    RETURNS void AS $$
	INSERT INTO request_points (street_id, geom)
	SELECT street_id,
     ST_Transform(ST_LineInterpolatePoint(
        st_linemerge(street_geom), 
        LEAST(n*(distance/ST_Length(street_geom)), 1.0)), ST_SRID(street_geom))
        FROM (VALUES (street_geom)) as geom -- Not used, needed from clause to cross join
	CROSS JOIN
		Generate_Series(0, CEIL(ST_Length(street_geom)/distance)::INT) AS n
    ON CONFLICT DO NOTHING;
$$ LANGUAGE SQL;