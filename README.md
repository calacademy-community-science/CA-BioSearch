# Motivation
I wanted to make a front-end for my postGIS database using chatGPT, to make complex queries of biodiversity accessible from natural language prompts and then display the resulting data in an exploratory map.

# Background
I've been working on building a local postgis database to hold biodiversity data from [GBIF](https://gbif.org). I've been learning `SQL` in the process and ended up using chatGPT quite a bit to help me write complex SQL queries. I realized that chatGPT is quite good at generating SQL queries, and wondered if I could stand up a `shiny` webapp that utilized a LLM (e.g. ChatGPT) to generate SQL queries and display the results on a map or in a table so that the data could be explored further.

The result here is a proof-of-concept, that ended up surprising me with how well it works after about a week of development

# Demo
[![IMAGE ALT TEXT](http://img.youtube.com/vi/zK9ZWllSGEI/0.jpg)](http://www.youtube.com/watch?v=zK9ZWllSGEI "Video Title")

Unfortunately because I have this spun up on a private network I don't have a demo that we can actually mess around with. 

# Why I'm excited
This is able to produce results for somewhat complex questions about biodiversity data using natural language, that would take a significant amount of time for people that do not have a local GBIF database of all CA records and do not know SQL. A year ago it would have taken me a significant amount of time to answer the question: which county in CA has the most records of [*Darlingtonia californica*](https://en.wikipedia.org/wiki/Darlingtonia_californica)? With this it takes the time to write out the prompt + the few minutes of waiting while the database query runs.

The webapp is able to generate complex SQL queries using relatively little information about the tables (see below). To me, this suggests that there is little overhead to adding additional data to the database. Conceivably, if I wanted to add a wildfire perimeter dataset like [FRAP](https://www.fire.ca.gov/what-we-do/fire-resource-assessment-program) I would add a new table to the postgis database, add the table description to the initial chatGPT prompt, and run from there (and probably adding a few notes to the initial prompt as it tries the first few queries). This presents a number of opportunities for exploring complex relationships between biodiversity and environmental data that I would have had a hard time imagining before learning SQL.

# How it works
1. At the start of the session, we call an inital prompt to chatGPT using the `chatgpt` R package. This prompt is in `gpt-initial-prompt.R`
    - This prompt contains information about a brief pre-amble about generating SQL queries and the purpose of the webapp
    - A description of the tables (verbatim output of `\d table` in `psql`)
    - A few additional notes per table (e.g. county names are capitalized)
2. A user then inputs a prompt and submits the prompt to chatGPT-4
3. chatGPT returns it's best guess of a SQL query and this passed directly to the postGIS database.
    - Because it's a persistent session with chatGPT you can tell it to correct any mistakes in the prompt
4. If data are returned, spatial data are mapped with `sf` and `leaflet` or rendered as a table if there isn't a geometry column.

## Tables
I'm not a database engineer so these tables might be pretty funky. But these are the ones I told chatGPT about:

### ca_core Table
  Column  |         Type         | Collation | Nullable | Default 
----------|----------------------|-----------|----------|---------
 gbifid   | bigint               |           | not null | 
 taxonkey | integer              |           |          | 
 year     | smallint             |           |          | 
 geom     | geometry(Point,4326) |           |          | 

### ca_species Table

Column        |  Type   | Collation | Nullable | Default 
----------------------|---------|-----------|----------|---------
 taxonkey             | integer |           | not null | 
 kingdom              | text    |           |          | 
 phylum               | text    |           |          | 
 class                | text    |           |          | 
 ordo                 | text    |           |          | 
 family               | text    |           |          | 
 genus                | text    |           |          | 
 species              | text    |           |          | 
 infraspecificepithet | text    |           |          | 
 taxonrank            | text    |           |          | 
 scientificname       | text    |           |          | 

### ca_layers Table
  Column  |        	Type         	      | Collation | Nullable |            	Default
----------|-----------------------------|-----------|----------|---------------------------------------
 id   	  | integer                 	  |       	  | not null | nextval("ca_layers_id_seq"::regclass)
 category | text                    	  |        	  |      	   |
 name 	  | text                    	  |       	  |      	   |
 geom 	  | geometry(MultiPolygon,4326) |       	  |      	   |

### ca_crosswalks Table

   Column   |  Type   | Collation | Nullable | Default
------------|---------|-----------|----------|---------
 gbifid 	  | bigint  |       	  |      	   |
 cwhr_type  | text	  |       	  |      	   |
 gap30x30id | integer |       	  |      	   |
 countyid   | integer |       	  |      	   |
