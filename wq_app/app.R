library("shiny")
library("tidyverse")
library("shinythemes")
library("ggplot2")
# library("scales")
# library("gridExtra")
library("lubridate")

#Make sure to be on the project directory before starting the Shiny App

wq <- read.csv("data/wq.csv", header= T) %>%
  filter(Site != 0)

lab <- read.csv("data/lab.csv", header= T) 

wq$Date<- ymd_hms(wq$Date, tz="UTC") %>%
  round_date("hour")

# Version 1
#lab$Date <- lab$Date %>% ymd_hms(tz="EST")

# Version 2
# lab$Date <- lab$Date %>%
#   ymd_hms() %>%
#   date() %>%
#   paste("12:00:00") %>%
#   ymd_hms(tz="EST") # Assume all data taken midday regardless of recorded time

lab$Date <- lab$Date %>%
  ymd_hms() %>%
  date() %>%
  paste("12:00:00") %>%
  ymd_hms(tz="UTC")

# Function to make factors with levels based on site input and not numerical
# so that ggplot facet display the sequence correctly.
factor_site_seq <- function (vec, site1, site2) {
  # The condition is required such that you don't declare levels of same values
  # or when they pick "none"
  if (site2 != 0 & site1 != site2) {
    f <- factor(vec, levels = c(site1, site2))
  } else f <- vec
  return(f)
}

#### Front 

ui <- fluidPage(
  
  theme = shinytheme("yeti"),
  
  sidebarLayout(
    sidebarPanel(
      
      width = 3,
      
      h3("Continuous Data"),
      
      selectInput("site1", label= h4("Site"), 
                  choices=c(unique(wq$Site) %>% sort()), selected = 1),
      
      selectInput("site2", label=h4("Comparison"), 
                  choices=c("None" = 0, unique(wq$Site) %>% sort()), selected = 6),
      
      dateRangeInput("date",
                     label =h4('Date range'),
                     start = "2017-01-01" , end = Sys.Date() + 7),
      
      checkboxInput("overlay", 
                    label = "Overlay point sample data?",
                    value = T),
      
      radioButtons("variable",
                   label = h4("Observations"),
                   choices = list("Salinity (ppt)" = "Salinity",
                                  "Conductivity (mS/cm)"= "Conductivity",
                                  "Temperature (C)" = "Temperature"),
                   selected = "Salinity"),
      
      radioButtons("temp_res",
                   label = "Temporal resolution",
                   choices = list("Hourly" = "Hourly",
                                  "Daily Mean" = "Daily"),
                   selected = "Hourly"),
      
      h3("Discrete Data"),
      
      
      #selectInput("site3", label= h4("Site"), 
      #            choices=unique(lab$Site)),
      
      #selectInput("site4", label=h4("Comparison"), 
      #            choices=c("None" = 0,unique(lab$Site))),
      
      radioButtons("variable2",
                   label = h4("Observations"),
                   choices = list("Salinity (ppt)" = "Salinity",
                                  "Conductivity (mS/cm)"= "Conductivity",
                                  "Temperature (C)" = "Temperature",
                                  "Phosphorus (ug/L)" = "Phosphorus",
                                  "Nitrogen (ug/L)" = "Nitrogen",
                                  "Color (Pt-Co Units)" = "Color",
                                  "Secchi (m)" = "Secchi"),
                   selected = c("Salinity"))),
    
    
    
    mainPanel(
      width = 9,
      h1("Continuous monitoring data"),
      plotOutput("sensorplot", height = "600px"),
      h1("Point sampling data"),
      plotOutput("labplot", height = "600px"))
    
  )
)

#Debug
# input <- list()
# input$date <- c("2017-01-01", "2018-07-01")
# input$variable <- "Salinity"
# input$site1 <- 1
# input$site2 <- 6

server <- shinyServer(function(input, output) {
  
  # Can directly use renderPlot instead of having reactive first
  output$sensorplot <- renderPlot({
    site1 <- as.numeric(input$site1)
    site2 <- as.numeric(input$site2)
    startDate <- paste(input$date[1], "00:00:00") %>% ymd_hms(tz="UTC")
    endDate <- paste(input$date[2], "23:00:00") %>% ymd_hms(tz="UTC")
    
    ### sensorplot
    # Filter WQ table
    wq1 <- wq %>% 
      filter(Site == site1 | Site == site2,
             Date >= startDate & Date <= endDate) %>% 
      select(Site, Date, Measure = input$variable)
    
    # Build a data table based on input daterange and temporal resolution
    # Note: We're building a table with all possible times first and merge it with
    # WQ table so that NAs and daterange of plot is preserved.
    # NAs are required for line plot
    if (input$temp_res == "Hourly") {
      d <- seq(startDate, endDate, by = "hour")
      df <- data.frame(Site = rep(c(site1, site2), each = length(d)),
                       Date = rep(d, 2)) %>%
        distinct() %>% 
        left_join(wq1)
    } else if (input$temp_res == "Daily") {
      
      # Need to convert WQ from hourly to daily
      wq2 <- wq1 %>%
        mutate(Date1 = date(Date)) %>%
        group_by(Site, Date1) %>%
        summarise(Measure = mean(Measure)) %>%
        select(Site, Date=Date1, Measure)
      
      d <- seq(startDate, endDate, by = "day") %>% date
      df <- data.frame(Site = rep(c(site1, site2), each = length(d)),
                       Date = rep(d, 2)) %>%
        distinct() %>%
        left_join(wq2)
    }
    
    # Remove Site 0 from the df we built
    df <- df %>%
      filter(Site != 0)
    
    # Adjusting Site's levels such that site1 goes before site2 regardless of
    # numerical order.
    df$Site <- factor_site_seq(df$Site, site1, site2)
    
    # Base version of the plot
    sensorplot <- ggplot(df, aes(x = Date, y = Measure)) +
      geom_line() +
      # scale_x_date(
        # breaks = date_breaks("month") ,
        # labels = date_format("%m/%Y")) +
      theme_gray(base_size = 14) +
      theme(panel.border = element_rect(color = "black", size = 0.5, fill = NA, linetype="solid")) +
      facet_wrap(~Site, ncol = 1) +
      ylab(input$variable)
    
    # Add feature if we want to overlay the point sample data
    if (input$overlay) {
      lab1 <- lab %>% 
        filter(Site == site1 | Site == site2,
               Date >= startDate & Date <= endDate) %>% 
        select(Site, Date, Measure = input$variable, Sensor_Type)
      
      # Same thing as we did for df$Site
      lab1$Site <- factor_site_seq(lab1$Site, site1, site2)

      if (input$temp_res == "Hourly") {
        sensorplot <- sensorplot + 
          geom_point(data = lab1, aes(x = Date, y = Measure, colour = Sensor_Type), shape = 17, size = 3) +
          scale_color_manual(name = "Method", values = c("red", "blue"))
      } else if (input$temp_res == "Daily") {
        sensorplot <- sensorplot + 
          geom_point(data = lab1, aes(x = date(Date), y = Measure, colour = Sensor_Type), shape = 17, size = 3) +
          scale_color_manual(name = "Method", values = c("red", "blue"))
      }
      
    }
    
    sensorplot
})
  
  output$labplot<-renderPlot({
    site1 <- as.numeric(input$site1)
    site2 <- as.numeric(input$site2)
    startDate <- paste(input$date[1], "00:00:00") %>% ymd_hms(tz="UTC")
    endDate <- paste(input$date[2], "23:00:00") %>% ymd_hms(tz="UTC")
    
    lab1 <- lab %>% 
      filter(Site == site1 | Site == site2,
             Date >= startDate & Date <= endDate) %>% 
      select(Site, Date, Measure = input$variable2, Sensor_Type)
    
    # Same thing as we did for sensorplot to force sequence of display
    lab1$Site <- factor_site_seq(lab1$Site, site1, site2)
    
    # Use similar trick as we did in sensorplot (e.g. build a df)
    labplot <- ggplot(lab1, aes(x = Date, y = Measure, colour = Sensor_Type)) +
      geom_point(shape = 17, size = 3) +
      scale_color_manual(name = "Method", values = c("red", "blue")) +
      scale_x_datetime(
        #   breaks = date_breaks("month") ,
        #   labels = date_format("%m/%Y")
        limits = c(startDate, endDate)) +
      theme_gray(base_size = 14) +
      theme(panel.border = element_rect(color = "black", size = 0.5, fill = NA, linetype="solid")) +
      facet_wrap(~ Site, ncol = 1) +
      ylab(input$variable2)
    
    labplot
  })
  
})

# Run the application 
shinyApp(ui = ui, server = server)
