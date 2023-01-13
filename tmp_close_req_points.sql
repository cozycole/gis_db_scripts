-- Cole T. 1/8/2023
-- Functions for testing and creating a table that contains 
-- both the universal closest request point per address and
-- the closest point that resides on the same street name as the address' name.
--
-- This newly made table will be used to find all request points to be requested
-- by the crawler.
--
-- Function:
--      test_find_closest_points(hood_name, srid): for testing the indexes function correctly, 
--      (query should take no longer than a couple seconds to complete given a neighborhood name)
--      
--      create_closest_point_table(srid): creates the table containing closest points for all addresses in the table,
--      For reference, the city of Cleveland, 113,00 addresses took a little over 20s 

CREATE OR REPLACE FUNCTION create_closest_point_table(srid integer)
	RETURNS void AS $$
	BEGIN
		EXECUTE
			'CREATE TABLE tmp_closest_req_points AS
				WITH closest_req_points as (
					SELECT a.gid as addr_gid, 
							a.address, 
							a.geom as addr_geom, 
							req_points.gid as req_gid, 
							req_points.geom as req_geom, 
							req_points.dist
					FROM addresses as a
					CROSS JOIN LATERAL (
						SELECT rp.gid, 
								rp.geom, 
								st_transform(rp.geom, $1) <-> st_transform(a.geom, $1) as dist 
						FROM request_points as rp
						ORDER BY dist
						LIMIT 1
					) as req_points
				),
				closest_req_points_on_street as (
					SELECT a.gid as addr_gid, 
							a.address, 
							a.geom as addr_geom, 
							req_points.gid as req_gid, 
							req_points.street_name, 
							req_points.geom as req_geom, 
							req_points.dist
					FROM addresses as a
					CROSS JOIN LATERAL (
						SELECT rp.gid, 
								rp.geom, 
								st.street_name, 
								st_transform(rp.geom, $1) <-> st_transform(a.geom, $1) as dist 
						FROM request_points as rp
						JOIN streets as st
						ON st.gid = rp.street_gid
						WHERE regexp_replace(address, ''^[0-9]+ '', '''') = st.street_name
						ORDER BY dist
						LIMIT 1
					) as req_points
				),
				-- We then have to check both for double intersecting buildings.
				-- We select all addrs that do not have the line between the address
				-- and the closest request point intersect 2 buildings.
				crp_building_check as (
					SELECT cp.addr_gid,
							cp.address,
							cp.addr_geom,
							cp.req_gid,
							cp.req_geom,
							cp.dist
					FROM closest_req_points as cp
					-- NOTE: we LEFT JOIN since abnormaly shaped buildings may have a centroid that does not 
					-- lie within the polygon, so no intersection could take place to join it
					LEFT JOIN buildings as b
					ON st_intersects(st_makeline(cp.req_geom, cp.addr_geom), b.geom)
					GROUP BY cp.addr_gid,
							cp.address,
							cp.addr_geom,
							cp.req_gid,
							cp.req_geom,
							cp.dist
					HAVING count(*) = 1 -- this condition filters the double building intersect
				),
				crpos_building_check as (
					SELECT cp.addr_gid,
							cp.address,
							cp.addr_geom,
							cp.req_gid,
							cp.req_geom,
							cp.dist
					FROM closest_req_points_on_street as cp
					LEFT JOIN buildings as b
					ON st_intersects(st_makeline(cp.req_geom, cp.addr_geom), b.geom)
					GROUP BY cp.addr_gid,
							cp.address,
							cp.addr_geom,
							cp.req_gid,
							cp.req_geom,
							cp.dist
					HAVING count(*) = 1 
				)
				SELECT a.gid, 
						a.address, 
						crpbc.req_gid, 
						crpbc.dist, 
						crposbc.req_gid as req_gid_on_st, 
						crposbc.dist as dist_on_st
				FROM addresses as a
				LEFT JOIN crp_building_check as crpbc
				ON crpbc.addr_gid = a.gid
				LEFT JOIN crpos_building_check as crposbc
				ON crposbc.addr_gid = a.gid'
			USING srid;
	END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION test_find_closest_points(hood_name varchar, srid integer)
	RETURNS TABLE (addr_gid int, 
					address varchar, 
					req_gid int, 
					dist double precision, 
					req_gid_on_st int, 
					dist_on_st double precision) AS $$
	BEGIN
		RETURN QUERY EXECUTE 
		'WITH closest_req_points as (
			SELECT a.gid as addr_gid, 
					a.address, 
					a.geom as addr_geom, 
					req_points.gid as req_gid, 
					req_points.geom as req_geom, 
					req_points.dist
		FROM addresses as a
		JOIN neighborhoods as n
		ON st_intersects(n.geom, a.geom)
		CROSS JOIN LATERAL (
			SELECT rp.gid, 
					rp.geom, 
					st_transform(rp.geom, $1) <-> st_transform(a.geom, $1) as dist 
			FROM request_points as rp
			ORDER BY dist
			LIMIT 1
		) as req_points
		WHERE n.hood_name = $2
		),
		closest_req_points_on_street as (
			SELECT a.gid as addr_gid, 
					a.address, 
					a.geom as addr_geom, 
					req_points.gid as req_gid, 
					req_points.street_name, 
					req_points.geom as req_geom, 
					req_points.dist
			FROM addresses as a
			JOIN neighborhoods as n
			ON st_intersects(n.geom, a.geom)
			CROSS JOIN LATERAL (
				SELECT rp.gid, 
						rp.geom, 
						st.street_name, 
						st_transform(rp.geom, $1) <-> st_transform(a.geom, $1) as dist 
				FROM request_points as rp
				JOIN streets as st
				ON st.gid = rp.street_gid
				WHERE regexp_replace(address, ''^[0-9]+ '', '''') = st.street_name
				ORDER BY dist
				LIMIT 1
			) as req_points
			WHERE n.hood_name = $2
		),
		-- We then have to check both for double intersecting buildings.
		-- We select all addrs that do not have the line between the address
		-- and the closest request point intersect 2 buildings.
		crp_building_check as (
			SELECT cp.addr_gid,
					cp.address,
					cp.addr_geom,
					cp.req_gid,
					cp.req_geom,
					cp.dist
			FROM closest_req_points as cp
			-- NOTE: we LEFT JOIN since abnormaly shaped buildings may have a centroid that does not 
			-- lie within the polygon, so no intersection could take place to join it
			LEFT JOIN buildings as b
			ON st_intersects(st_makeline(cp.req_geom, cp.addr_geom), b.geom)
			GROUP BY cp.addr_gid,
					cp.address,
					cp.addr_geom,
					cp.req_gid,
					cp.req_geom,
					cp.dist
			HAVING count(*) = 1 -- this condition filters the double building intersect
		),
		crpos_building_check as (
			SELECT cp.addr_gid,
					cp.address,
					cp.addr_geom,
					cp.req_gid,
					cp.req_geom,
					cp.dist
			FROM closest_req_points_on_street as cp
			LEFT JOIN buildings as b
			ON st_intersects(st_makeline(cp.req_geom, cp.addr_geom), b.geom)
			GROUP BY cp.addr_gid,
					cp.address,
					cp.addr_geom,
					cp.req_gid,
					cp.req_geom,
					cp.dist
			HAVING count(*) = 1 
		)
		SELECT a.gid, 
				a.address, 
				crpbc.req_gid, 
				crpbc.dist, 
				crposbc.req_gid as req_gid_on_st, 
				crposbc.dist as dist_on_st
		FROM addresses as a
		JOIN neighborhoods as n
		ON st_intersects(a.geom, n.geom)
		LEFT JOIN crp_building_check as crpbc
		ON crpbc.addr_gid = a.gid
		LEFT JOIN crpos_building_check as crposbc
		ON crposbc.addr_gid = a.gid 
		WHERE n.hood_name = $2'
		USING srid, hood_name;
END;
$$ LANGUAGE plpgsql;