-- Create indexes AFTER inserting initial datasets
-- so indexes don't update for each insert
CREATE EXTENSION IF NOT EXISTS postgis;
-- Unprojected spacial indexes (SRID 4326)
CREATE INDEX address_geom_idx ON addresses USING GIST(geom);
CREATE INDEX building_geom_idx ON buildings USING GIST(geom);
CREATE INDEX request_point_geom_idx ON request_points USING GIST(geom);
CREATE INDEX building_geom_idx on buildings USING GIST(geom);

-- Projected spacial indexes (Local SRID) here 3747 is used for Cleveland
CREATE INDEX request_point_projected_geom_idx ON request_points USING GIST(st_transform(geom, 3734))

-- Index for streetname/address regex
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX addresses_name_trgm ON addresses USING GIN (regexp_replace(address, '^[0-9]+ ', '') gin_trgm_ops);