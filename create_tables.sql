CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE addresses (
    gid SERIAL PRIMARY KEY,
    address VARCHAR NOT NULL,
    geom GEOMETRY NOT NULL
);

CREATE TABLE streets (
    gid SERIAL PRIMARY KEY,
    street_name VARCHAR NOT NULL,
    geom GEOMETRY NOT NULL
);

CREATE TABLE neighborhoods (
    gid SERIAL PRIMARY KEY,
    hood_name VARCHAR NOT NULL UNIQUE,
    geom GEOMETRY,
    finished BOOLEAN
);

CREATE TABLE buildings (
    gid SERIAL PRIMARY KEY,
    geom GEOMETRY NOT NULL
);

CREATE TABLE pano_metadata (
    gid SERIAL PRIMARY KEY,
    pano_id VARCHAR NOT NULL UNIQUE,
    capture_date VARCHAR,
    geom GEOMETRY NOT NULL,
    heading NUMERIC(7,4),
    downloaded BOOLEAN 
);

CREATE TABLE request_points (
    gid SERIAL PRIMARY KEY,
    street_gid INT NOT NULL,
    pano_gid INT,
    geom GEOMETRY NOT NULL,
    requested BOOLEAN,
    CONSTRAINT fk_street
        FOREIGN KEY(street_gid)
            REFERENCES streets(gid)
            ON DELETE SET NULL
            ON UPDATE CASCADE,
    CONSTRAINT fk_pano
        FOREIGN KEY(pano_gid)
            REFERENCES pano_metadata(gid)
            ON DELETE SET NULL
            ON UPDATE CASCADE
);

CREATE TABLE screenshots(
    id SERIAL PRIMARY KEY,
    addr_gid INT,
    pano_gid INT,
    distress_class VARCHAR,
    patch_distress NUMERIC(7,4),
    veg_distress NUMERIC(7,4),
    board_prob NUMERIC(7,4),
    tarp_prob NUMERIC(7,4),
    CONSTRAINT fk_shot_addr
        FOREIGN KEY (addr_gid)
            REFERENCES addresses(gid)
            ON DELETE SET NULL
            ON UPDATE CASCADE,
    CONSTRAINT fk_shot_pano
        FOREIGN KEY (pano_gid)
            REFERENCES pano_metadata(gid)
            ON DELETE SET NULL
            ON UPDATE CASCADE
);