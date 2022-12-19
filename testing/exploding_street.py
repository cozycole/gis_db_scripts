import math
import os
import unittest
import psycopg2 as pg
from dotenv import load_dotenv

load_dotenv()



class TestStreetExplode(unittest.TestCase):
    conn = pg.connect(
        user=os.getenv("POSTGRES_USER"),
        password=os.getenv("POSTGRES_PASSWORD"),
        host="localhost",
        database="postgres"
    )
    conn.autocommit = True
    @classmethod
    def setUpClass(cls) -> None: 
        # Set up database and tables
        cursor = cls.conn.cursor()
        cursor.execute("""DROP DATABASE IF EXISTS test;""")
        cursor.execute("""CREATE DATABASE test;""")
        cls.conn = pg.connect(
            user=os.getenv("POSTGRES_USER"),
            password=os.getenv("POSTGRES_PASSWORD"),
            host="localhost",
            database="test"
        )
        create_street_table = """
            CREATE TABLE IF NOT EXISTS test_streets(
            gid serial PRIMARY KEY,
            geom geometry UNIQUE
        );        
        """
        create_points_table = """
            CREATE TABLE IF NOT EXISTS request_points (
            id serial PRIMARY KEY,
            street_id integer,
            geom geometry UNIQUE
        );        
        """
        cls.cursor = cls.conn.cursor()
        cls.cursor.execute("""CREATE EXTENSION postgis;""")
        cls.cursor.execute(create_street_table)
        cls.cursor.execute(create_points_table)

    def test_street_explode(self):
        # single linestring
        sql_file = open("explode_street_db.sql", "r")
        self.cursor.execute(sql_file.read())
        sql_file.close()
        # transformed to ESPG:2270 for measure in ft
        create_linestring_query = """
            INSERT INTO test_streets (geom)
            VALUES (ST_Transform(ST_MakeLine(
                ST_SetSRID(ST_Point(-123.06976962, 44.033450161), 4326),
                ST_SetSRID(ST_Point(-123.06979683, 44.032173712),4326)
                ),2270))
        """
        point_distance = 30 
        self.cursor.execute(create_linestring_query)
        self.cursor.execute("SELECT st_length(geom) FROM test_streets where gid = 1;")
        line_length = self.cursor.fetchall()[0][0]
        self.cursor.execute(f"""
            SELECT explode_street(1, (SELECT geom from test_streets where gid=1), {point_distance});""")
        self.cursor.execute("""SELECT count(*) FROM request_points;""")
        point_count = self.cursor.fetchall()[0][0]
        self.assertEqual(point_count, math.ceil(line_length / point_distance) + 1) 