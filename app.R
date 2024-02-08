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
            # I use htmlOutput and shinyjs because it updates as it happens
            # otherwise, renderText won't update until the end
            htmlOutput("progress_update"),
            h3("Response from chatGPT"),
            wellPanel(verbatimTextOutput(outputId = "raw_response") %>% withSpinner(color = "#0dc5c1")),
            h3("Table returned from database"),
            wellPanel(
                style = "padding: 20px 20px 1px 20px;
                overflow-y:scroll;
                overflow-x:scroll;
                content: 'x';",
                tableOutput("postgis_results") %>% withSpinner(color = "#0dc5c1")
            )
        ),

        # Show a plot of the generated distribution
        mainPanel(
            leafletOutput("basemap", height = "85vh") %>%
                withSpinner(type = 7, color = "#024b6c")
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
        source("gpt-prep.R")
        messager$outputText <- paste0(messager$outputText, "ChatGPT Ready!", "<br>")
        shinyjs::html(id = "progress_update", messager$outputText)
        # output$ready <- renderText("ChatGPT Ready!")
    })


    # Adds more specifics to the user query
    full_query <- eventReactive(input$submitquery, {
        if (input$userquery == "") {
            print("Print a longer query")
            return()
        }

        messager$outputText <- ""
        shinyjs::html(id = "progress_update", messager$outputText)

        paste("Write an SQL Query (using PL/pgSQL for PostgreSQL syntax) that returns year, ca_core.geom, ca_species.* and all records that answers the following question:",
            input$userquery,
            "Limit to 500 records. Return only the SQL query with no explanation or other text.",
            collapse = " "
        )
    })



    # Submit full query to chatGPT
    chatGPT_response <- eventReactive(full_query(), {
        # shinyjs::html(id = "progress_update", "Sending query to chatGPT...")
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

    # Show chatGPT response in sidebar
    output$raw_response <- renderText({
        req(chatGPT_response())
        print(chatGPT_response())
        chatGPT_response()
    })

    # Query observations from the postGIS database
    observations.sf <- eventReactive(chatGPT_response(), {
        # shinyjs::html(id = "progress_update", "Querying the database...")
        messager$outputText <- paste0(messager$outputText, "Querying the database...", "<br>")
        shinyjs::html(id = "progress_update", messager$outputText)

        try(result <- con %>% st_read(query = chatGPT_response()))

        if (!exists("result")) {
            messager$outputText <- paste0(messager$outputText, "Database query failed", "<br>")
            shinyjs::html(id = "progress_update", messager$outputText)
            return()
        }

        if ("sf" %in% class(result)) { # & nrow(result) > 0
            prepped_result <- result %>%
                # Warning! This is to make it so even if it's a huge query it still
                # maps
                slice_sample(n = 1000)
            return(prepped_result)
        } else {
            print("Not ")
            return()
        }
    })

    # Put a sample of the postgis table in the sidebar
    output$postgis_results <- renderTable({
        req(observations.sf())
        # print("heres the table!")
        observations.sf() %>%
            tibble() %>%
            select(-contains("geom")) %>%
            head()
    })

    # Now map!
    output$basemap <- renderLeaflet({
        leaflet() %>%
            addProviderTiles("CartoDB.Positron") %>%
            # California bounds
            fitBounds(-124.24, 32.5, -114.8, 42)
    })

    observeEvent(observations.sf(), {
        # Make sure they are just POINT geometries
        observation_pts.sf <- observations.sf()[st_geometry_type(observations.sf()) == "POINT", ]
        # Get bounding box for zoom
        bbox <- observation_pts.sf %>%
            st_bbox() %>%
            as.vector()

        leafletProxy("basemap") %>%
            clearShapes() %>%
            clearControls() %>%
            addCircles(
                data = observation_pts.sf,
                # color = ~pal(count),
                # fillColor = ~pal(count),
                fillOpacity = .8,
                radius = 1
            ) %>%
            fitBounds(bbox[1], bbox[2], bbox[3], bbox[4])
    })
}

# Disconnect from DB
onStop(function() {
    dbDisconnect(con)
    reset_chat_session()
})

# Run the application
shinyApp(ui = ui, server = server)
