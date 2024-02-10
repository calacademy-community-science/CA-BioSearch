#
# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.
#
# Find out more about building applications with Shiny here:
#
#    http://shiny.rstudio.com/
#

library(shiny)
# library(TheOpenAIR)
library(chatgpt)
library(RPostgreSQL)
library(shinycssloaders)
library(sf)
library(leaflet)
library(tidyverse)
library(shinyjs)

con <- dbConnect(RPostgreSQL::PostgreSQL(),
                 dbname = "postgres",
                 host = "rosalindf",
                 port = 5432,
                 user = "unprivileged",
                 password = "unprivileged"
)

# Set chatGPT to 4
Sys.setenv(OPENAI_MODEL = "gpt-4")

ui <- fluidPage(
    
    # Application title
    titlePanel("Bio explorer"),
    
    # Sidebar with a slider input for number of bins
    sidebarLayout(
        sidebarPanel(
            useShinyjs(),
            textAreaInput(
                inputId = "userquery",
                label = "Write a question!",
                value = "",
                placeholder = 'Where are all the records of "Pinus ponderosa" species in the counties of "San Francisco", "Napa", and "Sonoma" in the years since 1999?',
                width = "100%",
                rows = 4
            ),
            actionButton(inputId = "submitquery", label = "Submit Query"),
            actionButton(inputId = "startGPT", label = "Start chatGPT"),
            shinyjs::hidden(downloadButton("download1", label = "Download results")),
            # I use htmlOutput and shinyjs because it updates as it happens
            # otherwise, renderText won't update until the end
            htmlOutput("progress_update"),
            h3("Response from chatGPT"),
            # wellPanel(verbatimTextOutput(outputId = "raw_response") %>% withSpinner(color = "#0dc5c1")),
            wellPanel(htmlOutput("raw_response")),
            h3("Table returned from database"),
            "First 100 rows",
            wellPanel(
                style = "padding: 20px 20px 1px 20px;
                overflow-y:scroll;
                overflow-x:scroll;
                content: 'x';",
                tableOutput("postgis_results_always") %>% withSpinner(color = "#0dc5c1")
            )
        ),
        
        # Show a plot of the generated distribution
        mainPanel(
            # This is either a map or a table
            leafletOutput("basemap", height = "85vh") %>%
                withSpinner(type = 7, color = "#024b6c"),
            # uiOutput("condPanel") %>% withSpinner(color = "#0dc5c1")
            
            
            # Hidden species list pop-up
            hidden(
                div(id = "table_div",
                    fluidRow(
                        absolutePanel(
                            id = "cond_panel",
                            class = "panel panel-default",
                            fixed = TRUE, 
                            top = "auto", left = "auto", 
                            right = "0", bottom = 0,
                            draggable = T,
                            height = "90vh",
                            style = "padding: 20px 20px 1px 20px;
                background-color: rgba(255, 255, 255, 0.9);
                overflow-y:scroll;
                content: 'x';",
                            fluidRow(
                                column(width = 2,
                                       tableOutput("postgis_results"))
                            )
                        )
                    )
                ))
        )
    )
)

# Define server logic required to draw a histogram
server <- function(input, output) {
    # This is going to keep track of progress messages
    messager <- reactiveValues(outputText = "")
    
    
    # Load all the gpt initial prompt with a button so it doesn't just load every
    # time I start the app
    observeEvent(input$startGPT, {
        source("gpt-initial-prompt.R")
        messager$outputText <- paste0(messager$outputText, "ChatGPT Ready!", "<br>")
        shinyjs::html(id = "progress_update", messager$outputText)

    })
    
    
    # Adds more specifics to the user query
    full_query <- eventReactive(input$submitquery, {
        if (input$userquery == "") {
            print("Print a longer query")
            return()
        }
        
        # Reset progress updater
        messager$outputText <- ""
        shinyjs::html(id = "progress_update", messager$outputText)
        
        # Make sure overlay table is hidden
        shinyjs::hide(id = "table_div")
        
        # Make sure download button is hidden
        shinyjs::hide("download1")
        
        # Reset query box
        gpt_query$outputText <- ""
        shinyjs::html(id = "raw_response", gpt_query$outputText)
        
        paste(
            # "Write an SQL Query (using PL/pgSQL for PostgreSQL syntax) that returns year, ca_core.geom, ca_species.* and all records that answers the following question:",
            "Write an SQL Query (using PL/pgSQL for PostgreSQL syntax) that returns all columns (e.g. SELECT *) and all records that answers the following question:",
            input$userquery,
            "Limit to 500 records. Return only the SQL query with no explanation or other text.",
            collapse = " "
        )
    })
    
    
    
    # Submit full query to chatGPT
    chatGPT_response <- eventReactive(full_query(), {

        messager$outputText <- paste0(messager$outputText, "Sending query to chatGPT...", "<br>")
        shinyjs::html(id = "progress_update", messager$outputText)
        
        direct_response <- full_query() %>%
            ask_chatgpt()
        print(paste("Direct response:", direct_response))
        
        if (direct_response == "") {
            print("chatGPT error")
            return()
        } else {
            direct_response %>%
                # If it says other junk this extracts from SELECT to first ;
                str_extract("SELECT([^;]+);")
        }
    })

    gpt_query <- reactiveValues(outputText = "")
    observe({
        gpt_query$outputText <- chatGPT_response() %>% str_replace_all("\n", "<br>")
        shinyjs::html(id = "raw_response", gpt_query$outputText)
    })
    
    # Query observations from the postGIS database
    observations.sf <- eventReactive(chatGPT_response(), {
        
        # Update htmloutput to show progress
        messager$outputText <- paste0(messager$outputText, "Querying the database...", "<br>")
        shinyjs::html(id = "progress_update", messager$outputText)
        
        # try(result <- con %>% st_read(query = chatGPT_response()))
        # This is not st_read() anymore so that we can separate out the other geom columns
        try(result <- con %>% dbGetQuery(chatGPT_response()))
        
        # If it doesn't exist just stop here
        if (!exists("result") | is.null(result)) {
            messager$outputText <- paste0(messager$outputText, "Database query failed", "<br>")
            shinyjs::html(id = "progress_update", messager$outputText)
            return()
        }
        
        # If the result has more than two columns named 'geom',
        # then we probably just want species points. So lets separate the columns
        # out and then slap the one back on that's a POINT geometry
        if (names(result) %>% str_detect("geom") %>% sum() == 2) {
            
            # This gives all duplicate columns unique names
            renamed <- result %>% tibble(.name_repair = "unique")
            
            # Convert all 'geom' columns to sf geometry
            geoms.df <- renamed %>% 
                select(geom=contains("geom")) %>% 
                mutate(across(contains("geom"), 
                              ~ st_as_sfc(structure(.x, class = "WKB"), 
                                          EWKB = TRUE)))
        
            renamed_clean <- renamed %>% select(-contains("geom"))
            
            # Weed out non-point geometry
            point_geom.df <- geoms.df %>% mutate(across(contains("geom"), 
                                       ~ if(all(st_geometry_type(.) == "POINT")) 
                                           . else NA_real_)) %>% 
                # This works because turning the whole column NA makes it double
                select_if(~!is.double(.))
            
            # Slap on the geometry that is composed of points
            fixed_df <- renamed_clean %>% bind_cols(point_geom.df) %>% st_as_sf()
            
            return(fixed_df)
        } else if(names(result) %>% str_detect("geom") %>% sum() == 1){
            
            # Otherwise just return the object with as an sf
            result_singlegeom <- result %>%
                as_tibble(.name_repair = "unique") %>%
                # This makes sure that if there isn't geom, it doesn't break
                mutate(across(contains("geom"), 
                              ~ st_as_sfc(structure(.x, class = "WKB"), 
                                          EWKB = TRUE))) %>% 
                st_as_sf()
            
            return(result_singlegeom)
        } else {
            # No geometry column
            result_nogeom <- result %>%
                as_tibble(.name_repair = "unique")
                
            return(result_nogeom)
        }
        
        messager$outputText <- paste0(messager$outputText, 
                                      "Query operation complete.", "<br>")
        shinyjs::html(id = "progress_update", messager$outputText)
    })
    
    # Put The table in the main part if there's no map
    output$postgis_results <- renderTable({
        req(observations.sf())
        
        observations.sf() %>%
            tibble() %>%
            select(-contains("geom")) %>%
            slice_head(n = 100)
    })
    
    # Put a sample of the postgis table in the sidebar
    output$postgis_results_always <- renderTable({
        req(observations.sf())
        # print("heres the table!")
        observations.sf() %>%
            tibble() %>%
            select(-contains("geom")) %>%
            slice_head(n = 100)
    })
    
    # Now map!
    output$basemap <- renderLeaflet({
        leaflet() %>%
            addProviderTiles("CartoDB.Positron") %>%
            # California bounds
            fitBounds(-124.24, 32.5, -114.8, 42)
    })
    
    observeEvent(observations.sf(), {
        print("Mapping...")
        # If it's not spatial then don't map
        if (!"sf" %in% class(observations.sf())) {
            print("Not spatial")
            shinyjs::show(id = "table_div")
            leafletProxy("basemap") %>% clearShapes()
            return()
        }
        
        observations.sf <- observations.sf() %>%
            # Warning! This is to make it so even if it's a huge query it still
            # maps
            slice_sample(n = 1000)
        
        # Get bounding box for zoom
        bbox <- observations.sf %>%
            st_bbox() %>%
            as.vector()
        
        # If it has year and species, add them to the popup
        if("year" %in% names(observations.sf) & 
           "species" %in% names(observations.sf)) {
            
            leafletProxy("basemap") %>%
                clearShapes() %>%
                clearControls() %>%
                addCircles(
                    data = observations.sf[st_geometry_type(observations.sf) == "POINT", ],
                    fillOpacity = .8,
                    radius = 1,
                    # need to make sure that the data has these columns
                    popup = ~ sprintf(
                        "<b>Species:<br>
                               </b> %s <br>
                               <b>Year:</b> %s <br>",
                        species,
                        year
                    )
                ) %>%
                addPolygons(data = observations.sf[st_geometry_type(observations.sf) != "POINT", ]) %>%
                fitBounds(bbox[1], bbox[2], bbox[3], bbox[4])
            
        } else {
            # Otherwise just throw up whatever
            
            leafletProxy("basemap") %>%
                clearShapes() %>%
                clearControls() %>%
                addCircles(
                    data = observations.sf[st_geometry_type(observations.sf) == "POINT", ],
                    fillOpacity = .8,
                    radius = 1,
                ) %>%
                addPolygons(data = observations.sf[st_geometry_type(observations.sf) != "POINT", ]) %>%
                fitBounds(bbox[1], bbox[2], bbox[3], bbox[4])
        }
        
    })
    
    
    # Download button
    observeEvent(observations.sf(), {
        print("show")
        shinyjs::show("download1")
    })
    
    
    output$download1 <- downloadHandler(
        filename = function() {
            paste0("query_results", ".csv")
        },
        content = function(file) {
            write.csv(observations.sf(), file)
        }
    )
}

# Disconnect from DB
onStop(function() {
    dbDisconnect(con)
    reset_chat_session()
})

# Run the application
shinyApp(ui = ui, server = server, options = list(launch.browser = T))
