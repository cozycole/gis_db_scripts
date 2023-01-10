-- Cole T. 1/10/23
-- Following functions are used after creating the tmp_close_req_points table (see sql file with same name)

CREATE OR REPLACE FUNCTION insert_addr_req_pairings(srid int, distance numeric)
	RETURNS void AS $$
	BEGIN
		EXECUTE 
			'INSERT INTO addr_req_point_join(req_gid, addr_gid)
			WITH closest_addr_reqs as (
				SELECT gid as addr_gid, req_gid
				FROM tmp_closest_req_points
				UNION
				SELECT gid as addr_gid, req_gid_on_st
				FROM tmp_closest_req_points
			)
			SELECT distinct rp_radial.gid, car.addr_gid
			FROM closest_addr_reqs as car
			JOIN request_points as rp
			ON rp.gid = car.req_gid
			JOIN request_points as rp_radial
			ON st_dwithin(st_transform(rp.geom, $1), st_transform(rp_radial.geom, $1), $2);'
			USING srid, distance;
	END;
$$ LANGUAGE plpgsql;

-- Filters too distant req_point:addr pairings
CREATE OR REPLACE FUNCTION delete_distant_pairs(srid int, distance numeric)
	RETURNS void AS $$
	BEGIN
		EXECUTE
			'WITH too_distant_pairs as (
				select arpj.*, st_length(st_makeline(st_transform(a.geom, $1), st_transform(rp.geom, $1))) as len 
				from addr_req_point_join as arpj
				join addresses as a
				on a.gid = arpj.addr_gid
				join request_points as rp
				on rp.gid = arpj.req_gid
				where st_length(st_makeline(st_transform(a.geom, $1), st_transform(rp.geom, $1))) > $2
			)
			DELETE FROM addr_req_point_join as arpj
			USING too_distant_pairs as tdp
			WHERE tdp.addr_gid = arpj.addr_gid
			AND tdp.req_gid = arpj.req_gid;'
			USING srid, distance;
	END;
$$ LANGUAGE plpgsql;

-- Delete any addr:req pairings where the line between the two points
-- intersects multiple buildings (i.e. the line of sight is blocked by another building)
CREATE OR REPLACE FUNCTION delete_double_intersect()
	RETURNS void AS $$
	WITH addr_req_intersects as (
		SELECT addr_gid, req_gid, count(*) 
		FROM addr_req_point_join as arpj
		JOIN request_points as rp
		ON rp.gid = arpj.req_gid
		JOIN addresses as a
		ON a.gid = arpj.addr_gid
		JOIN buildings as b
		ON ST_Intersects(b.geom, ST_MakeLine(a.geom, rp.geom))
		GROUP BY addr_gid, req_gid
		HAVING count(*) > 1
	)
	DELETE FROM addr_req_point_join as arpj
	USING addr_req_intersects as ari
	WHERE (ari.addr_gid = arpj.addr_gid AND ari.req_gid = arpj.req_gid);
$$ LANGUAGE SQL;

-- We are deleting all req_points that do not have a pairing to address
-- in addr_req_pont_join
CREATE OR REPLACE FUNCTION delete_non_paired_reqs()
	RETURNS void AS $$
		WITH req_points_to_delete AS (
			SELECT * 
			FROM request_points as rp
			LEFT JOIN (SELECT DISTINCT req_gid FROM addr_req_point_join) as reqs
			ON rp.gid = reqs.req_gid
			WHERE reqs.req_gid is null
		)
		DELETE FROM request_points as rp
		USING req_points_to_delete as rpd
		WHERE rpd.gid = rp.gid;
$$ LANGUAGE SQL;