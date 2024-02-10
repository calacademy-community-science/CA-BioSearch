ask_chatgpt(
    'You are a database administrator, and expert in SQL. You will be helping me write complex SQL queries. I will explain you my needs, you will generate SQL queries against my database.

My application does: Geographic mapping of the point observations of species occurrence data.

The database is a POSTGIS Postgres database, please take it into consideration when generating PLSQL/SQL. Please avoid ST_Within queries if possible, because they are so slow.

I will provide you with a description of the structure of my tables. You must remember them and use them for generating SQL queries. Once you read them all, just answer OK, nothing else.

Here are the tables :

Table "ca_core"
  Column  |     	Type     	| Collation | Nullable | Default
----------+----------------------+-----------+----------+---------
 gbifid   | bigint           	|       	| not null |
 taxonkey | integer          	|       	|      	|
 year 	| smallint         	|       	|      	|
 geom 	| geometry(Point,4326) |       	|      	|
Indexes:
	"ca_core_pkey" PRIMARY KEY, btree (gbifid)
	"idx_core_year" btree (year)
	"idx_geom" gist (geom)
Foreign-key constraints:
	"ca_core_gbifid_fkey" FOREIGN KEY (gbifid) REFERENCES ca_extra(gbifid)
	"ca_core_taxonkey_fkey" FOREIGN KEY (taxonkey) REFERENCES ca_species(taxonkey)
Referenced by:
	TABLE "ca_crosswalks" CONSTRAINT "ca_pt_evt2_gbifid_fkey" FOREIGN KEY (gbifid) REFERENCES ca_core(gbifid)

Table "ca_species"
    	Column    	|  Type   | Collation | Nullable | Default
----------------------+---------+-----------+----------+---------
 taxonkey         	| integer |       	| not null |
 kingdom          	| text	|       	|      	|
 phylum           	| text	|       	|      	|
 class            	| text	|       	|      	|
 ordo             	| text	|       	|      	|
 family           	| text	|       	|      	|
 genus            	| text	|       	|      	|
 species          	| text	|       	|      	|
 infraspecificepithet | text	|       	|      	|
 taxonrank        	| text	|       	|      	|
Indexes:
	"ca_species_pkey" PRIMARY KEY, btree (taxonkey)
	"idx_species" btree (species)
Referenced by:
	TABLE "ca_core" CONSTRAINT "ca_core_taxonkey_fkey" FOREIGN KEY (taxonkey) REFERENCES ca_species(taxonkey)
*Note: Taxonomic information is always stored in scientific taxonomic nomenclature. Always translate common names to scientific names before building a query.
*Note: the "species" column contains scientific binomial nomenclature, so both genus and species should always be included when querying from the "species" column.

Table "ca_layers"
  Column  |        	Type         	| Collation | Nullable |            	Default
----------+-----------------------------+-----------+----------+---------------------------------------
 id   	| integer                 	|       	| not null | nextval("ca_layers_id_seq"::regclass)
 category | text                    	|       	|      	|
 name 	| text                    	|       	|      	|
 geom 	| geometry(MultiPolygon,4326) |       	|      	|
Indexes:
	"ca_layers_pkey" PRIMARY KEY, btree (id)
	"idx_layer_geom" gist (geom)
Referenced by:
	TABLE "ca_crosswalks" CONSTRAINT "ca_crosswalks_countyid_fkey" FOREIGN KEY (countyid) REFERENCES ca_layers(id)
	TABLE "ca_crosswalks" CONSTRAINT "ca_crosswalks_gap30x30id_fkey" FOREIGN KEY (gap30x30id) REFERENCES ca_layers(id)
*Note: The "ca_layers" table contains different categories of layers, specified under the "category" column, which include: "County", "30x30 GAP12"
*Note: When a county is specified, query using only the county name (Capitalized) without the word "county" included

Table "ca_crosswalks"
   Column   |  Type   | Collation | Nullable | Default
------------+---------+-----------+----------+---------
 gbifid 	| bigint  |       	|      	|
 cwhr_type  | text	|       	|      	|
 gap30x30id | integer |       	|      	|
 countyid   | integer |       	|      	|
Indexes:
	"idx_crosswalk_cwhr" btree (cwhr_type)
Foreign-key constraints:
	"ca_crosswalks_countyid_fkey" FOREIGN KEY (countyid) REFERENCES ca_layers(id)
	"ca_crosswalks_gap30x30id_fkey" FOREIGN KEY (gap30x30id) REFERENCES ca_layers(id)
	"ca_pt_evt2_gbifid_fkey" FOREIGN KEY (gbifid) REFERENCES ca_core(gbifid)'
)
