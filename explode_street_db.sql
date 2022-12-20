CREATE TABLE IF NOT EXISTS request_points (
	id serial PRIMARY KEY,
	street_id integer,
	geom geometry UNIQUE
);

-- Any multistrings that are disjoint, all sub linestrings
-- are individually added to table with new gid, but same street name
CREATE OR REPLACE FUNCTION fix_disjoint_multilines()
    RETURNS void AS $$
    WITH sub_strings as (
        SELECT gid, (st_dump(geom)).geom as geom FROM test_streets
        WHERE ST_geometrytype(st_linemerge(geom)) = 'ST_MultiLineString' ),
    insert_subs as (
        INSERT INTO test_streets (street_name, geom)
        SELECT street_name, st_multi(ss.geom)
        FROM sub_strings as ss
        JOIN test_streets as ass
        ON ass.gid = ss.gid
    )
    DELETE FROM test_streets WHERE gid IN (SELECT gid FROM sub_strings);
$$ LANGUAGE SQL;

-- geom must be of type linestring or multilinestring
-- where the lines are connected. fix_disconnected_lines should
-- be called to break any multiline strings that are disjoint
CREATE OR REPLACE FUNCTION explode_street(
    street_id integer, 
    street_geom geometry,
    distance numeric) 
    RETURNS void AS $$
	INSERT INTO request_points (street_id, geom)
	SELECT street_id,
     ST_Transform(ST_LineInterpolatePoint(
        ST_linemerge(street_geom), 
        LEAST(n*(distance/ST_Length(street_geom)), 1.0)), ST_SRID(street_geom))
        FROM (VALUES (street_geom)) as geom -- Not used, needed from clause to cross join
	CROSS JOIN
		Generate_Series(0, CEIL(ST_Length(street_geom)/distance)::INT) AS n
    ON CONFLICT DO NOTHING;
$$ LANGUAGE SQL;