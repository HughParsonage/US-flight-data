## ----knitrOpts-----------------------------------------------------------
START.TIME <- Sys.time()
knitr::opts_chunk$set(fig.show = 'hide',
                      fig.width = 8.4, 
                      fig.height = 5,
                      out.width = "8.4in")

## ----loadPackages--------------------------------------------------------
library(data.table)
library(bit64)
library(dplyr)
library(magrittr)
library(ggplot2)
theme_update(text = element_text(family = "", 
                                 face = "plain", colour = "black", size = 20, lineheight = 0.9, 
                                 hjust = 0.5, vjust = 0.5, angle = 0, margin = margin(), 
                                 debug = FALSE))
library(nycflights13)  # for airports
nycflights.airports <- airports
library(fasttime)
library(grattan)

## ----originalloadData, eval=FALSE----------------------------------------
## pre2008_flights <-
##   rbindlist(lapply(list.files(path = "../flights/1987-2008/",
##                     pattern = "csv$",
##                     full.names = TRUE), fread))
## 
## pre2008.names <-
##   names(pre2008_flights)
## 
## read_and_report <-
##   function(filename){
##     year <- gsub("^.*(2[0-9]{3}).{3,4}csv$", "\\1", filename)
##     if(grepl("1.csv", filename, fixed = TRUE))
##       cat(year)
##     fread(filename, select = pre2008.names, showProgress = FALSE)
##   }
## 
## gc(1,1)
## post2008_flights <-
##   rbindlist(lapply(list.files(path = "../flights", recursive = TRUE, pattern = "2[0-9]{3}.{3,4}csv$",
##                               full.names = TRUE),
##                    read_and_report))
## 
## flights <- rbindlist(list(pre2008_flights, post2008_flights), use.names = TRUE)
## readr::write_csv(flights, path = "../1987-2015-On-Time-Performance.csv")

## ----loadData, cache=FALSE-----------------------------------------------
Sys.time()
flights <- fread("../1987-2015-On-Time-Performance.csv")
# flights <- readRDS("../1987-2015-On-Time-Performance.rds")

## ----sample--------------------------------------------------------------
flightsSanFran <- flights[Origin %in% c("SFO", "OAK") | Dest %in% c("SFO", "OAK")]
sample.frac = 0.2
sample.weight.int = as.integer(round(1/sample.frac))
flights <- flights[sample(.N, .N * sample.frac)]

## ----cleanse1------------------------------------------------------------
# First we want a time for each flight. This is more difficult that it might seem.
# We need to concatenate the Year, Month, and DayofMonth fields, but we also need 
# to take into account the various time zones of the airports in the database.
integer.cols <- grep("Time$", names(flights))

Sys.time()
for (j in integer.cols){
  set(flights, j = j, value = as.integer(flights[[j]]))
}
Sys.time()
# See stackoverflow: links and comments under my question
create_DepDateTime <- function(DT){
  setkey(DT, Year, Month, DayofMonth, DepTime)
  unique_dates <- unique(DT[,list(Year, Month, DayofMonth, DepTime)])
  unique_dates[,DepDateTime := fastPOSIXct(sprintf("%d-%02d-%02d %s", Year, Month, DayofMonth, 
                                                   sub("([0-9]{2})([0-9]{2})", "\\1:\\2:00", sprintf("%04d", DepTime), 
                                                       perl = TRUE)), 
                                           tz = "GMT")]
  DT[unique_dates]
}

create_ArrDateTime <- function(DT){
  setkey(DT, Year, Month, DayofMonth, ArrTime)
  unique_dates <- unique(DT[,list(Year, Month, DayofMonth, ArrTime)])
  unique_dates[,ArrDateTime := fastPOSIXct(sprintf("%d-%02d-%02d %s", Year, Month, DayofMonth, 
                                                   sub("([0-9]{2})([0-9]{2})", "\\1:\\2:00", sprintf("%04d", ArrTime), 
                                                       perl = TRUE)),
                                           tz = "GMT")]
  DT[unique_dates]
}
flights <- create_DepDateTime(flights)
flights <- create_ArrDateTime(flights)
#flights[,`:=`(Year = NULL, Month = NULL, DayofMonth = NULL, DepTime = NULL, ArrTime = NULL)]
Sys.time()

## ----Cleanse2------------------------------------------------------------
# Now we join it to the airports dataset from nycflights13 to obtain time zone information.
Sys.time()
airports <- as.data.table(airports)
airports <- airports[,list(faa, tz)]
gc(1,1)
setnames(airports, old = c("faa", "tz"), new = c("Origin", "tzOrigin"))
setkey(airports, Origin)
setkey(flights, Origin)
flights <- flights[airports]
setnames(airports, old = c("Origin", "tzOrigin"), new = c("Dest", "tzDest"))
setkey(flights, Dest)
flights <- flights[airports]
rm(airports)
gc(1,1)
# The joins produce NAs when the airports table isn't present in the flights table.
flights <- flights[!is.na(Origin)]
gc(1,1)
Sys.time()

## ----Cleanse3-timezones--------------------------------------------------
Sys.time()
# setting keys doesn't improve timing
flights[,`:=`(DepDateTimeZulu = DepDateTime - lubridate::hours(tzOrigin))]
flights[,`:=`(ArrDateTimeZulu = ArrDateTime - lubridate::hours(tzDest))]
Sys.time()

## ----Cleanse-weeks-------------------------------------------------------
# Flights typically follow a weekly cycle, so we should obtain the week in the dataset.
# Pretty quick!
Sys.time()
setkey(flights, Year, Month, DayofMonth)
unique_dates <- unique(flights)
unique_dates <- unique_dates[,list(Year, Month, DayofMonth)]
unique_dates[,Week := (Year - 1987L) * 52 + data.table::yday(sprintf("%d-%02d-%02d", Year, Month, DayofMonth)) %/% 7]
unique_dates[,Week := Week - min(Week)]
flights <- flights[unique_dates]
Sys.time()


## ----SanFran-------------------------------------------------------------
Sys.time()
setkey(flightsSanFran, Year, Month, DayofMonth)
unique_dates <- unique(flightsSanFran)
unique_dates <- unique_dates[,list(Year, Month, DayofMonth)]
unique_dates[,Week := (Year - 1987L) * 52 + data.table::yday(sprintf("%d-%02d-%02d", Year, Month, DayofMonth)) %/% 7]
unique_dates[,Week := Week - min(Week)]
flightsSanFran <- flightsSanFran[unique_dates]
Sys.time()

## ----SanFran_Flights_by_date, results = 'hide'---------------------------
maxN <- function(x, N=2){
  len <- length(x)
  if(N>len){
    warning('N greater than length(x).  Setting N=length(x)')
    N <- length(x)
  }
  sort(x,partial=len-N+1)[len-N+1]
}

setkey(unique_dates, Week)
flightsSanFran %>%
  filter(!(Origin %in% c("SFO", "OAK") & Dest %in% c("SFO", "OAK"))) %>%
  mutate(SF_airport = ifelse(Origin %in% c("SFO", "OAK"),
                             Origin, 
                             Dest)) %>%
  count(Week, SF_airport) %>%
  group_by(SF_airport) %>%
  mutate(label.text = ifelse(n == maxN(n), paste(" ", SF_airport), NA_character_)) %>%
  setkey(Week) %>%
  data.table:::merge.data.table(unique(unique_dates)) %>%
  mutate(Date = fastPOSIXct(sprintf("%d-%02d-%02d", Year, Month, DayofMonth), tz = "GMT"),
         n = n) %>%  # not a sample
  ggplot(aes(x = Date, y = n, color = SF_airport, group = SF_airport)) + 
  geom_point() + 
  geom_text(aes(label = label.text),
            nudge_y = 0.5,
            nudge_x = 1,
            hjust = 0,
            fontface = "bold",
            size = 5) + 
  theme(legend.position = "none") + 
  geom_line(size = 0.5) + 
  #
  geom_vline(xintercept = as.numeric(as.POSIXct("2001-09-11"))) + 
  scale_x_datetime(date_breaks = "5 years",
                   date_labels = "%Y",
                   minor_breaks = seq(as.POSIXct("1987-12-31"), as.POSIXct("2014-12-31"), by = "1 years"))

## ----SanFran_Flights_by_Carrier, fig.height = 9, outheight = "9in"-------
carriers <- as.data.table(airlines)
if("carrier" %in% names(carriers))
  setnames(carriers, old = "carrier", new = "UniqueCarrier")

setkey(carriers, UniqueCarrier)
set(carriers, j = 1L, value = as.character(carriers[[1L]]))
set(carriers, j = 2L, value = gsub("^([A-Za-z]+)\\s.*$", "\\1", carriers[[2L]]))

flightsSanFran %>% 
  filter(Origin %in% c("SFO", "OAK")) %>%
  count(Year, Month, Origin, UniqueCarrier) %>%
  group_by(UniqueCarrier) %>%
  filter(sum(n) > (2015 - 1987) * 12 * 30)  %>%
  mutate(Date = Year + (Month - 1)/12) %>%
  setkey(UniqueCarrier) %>%
  merge(carriers) %>%
  ggplot(aes(x = Date, y = n * sample.weight.int, color = name, group = interaction(name,Origin))) + ylab("Number of departures") +
  geom_smooth(span = 0.25, se = FALSE) + 
  geom_text(aes(label = ifelse(Date == max(Date),
                               name,
                               NA_character_),
                vjust = ifelse(name == "Southwest" & Origin == "SFO",
                                 -0.5,
                                 0.5)),
            nudge_x = 0.75,
            size = 5) + theme(legend.position = "none") + 
  annotate("blank", x = 2019, y = 0) + 
  facet_grid(Origin ~ .) + 
  theme(text = element_text(size = 16)) 

## ----Volume-by-Carrier---------------------------------------------------
top_5_carriers <- 
  flights %>%
  count(UniqueCarrier) %>%
  arrange(desc(n)) %>%
  mutate(TopN = 1:n() <= 5) %>%
  mutate(Carrier_other = ifelse(TopN, UniqueCarrier, "Other")) %>%
  select(-n) %>%
  setkey(UniqueCarrier)

flights %>%
  setkey(UniqueCarrier) %>%
  merge(top_5_carriers) %>%
  count(Carrier_other, Year) %>%
  ggplot(aes(x = Year, y = n * sample.weight.int, color = Carrier_other, group = Carrier_other)) + 
  geom_line() +
  scale_colour_brewer(palette = "Accent") + 
  scale_y_continuous(label = scales::comma)

## ----Volume-by-major-airports--------------------------------------------
majorAirportThreshold = 10

major_airports <- 
  flights[ ,.(n = .N), by = Dest][order(-n)] %>% # flights %>% count(Dest) %>% arrange(desc(n))
  mutate(TopN = 1:n() <= majorAirportThreshold) %>%
  mutate(AirportOther = ifelse(TopN, Dest, "Other_airport")) %>%
  select(-n) %>%
  setkey(Dest) 

airports_by_volume_by_year <- flights[major_airports][ ,.(n = .N * sample.weight.int), by = list(Year, AirportOther)] 

airports_by_volume_by_2014 <- 
  airports_by_volume_by_year %>%
  filter(Year == 2014) %>%
  filter(AirportOther != "AirportOther") %>%
  merge(select(nycflights.airports, faa, name), by.x = "AirportOther", by.y = "faa") %>%
  arrange(desc(n))
gc(0,1)

setkey(flights, Dest)
gc(0,1)
airports_by_volume_by_year %>%
  filter(AirportOther != "Other_airport", Year > 1987L, Year < 2015L)  %>%
  merge(select(nycflights.airports, faa, name), by.x = "AirportOther", by.y = "faa") %>%
  mutate(name = factor(name, levels = airports_by_volume_by_2014$name)) %>%
  ggplot(aes(x = Year, y = n, group = name, color = name)) + 
  geom_line() 
gc(0,1)

## ----Relative-volume-by-major-airports-----------------------------------
rel_vol_major_airports <-
  flights[major_airports][ ,.(n = .N * sample.weight.int), by = list(Year, AirportOther)] %>%
  filter(AirportOther != "Other_airport", Year > 1987L, Year < 2015L) %>%
  arrange(Year) %>%
  group_by(AirportOther) %>%
  mutate(rel = n/first(n)) %>%
  merge(select(nycflights.airports, faa, name), by.x = "AirportOther", by.y = "faa")

last_values <- 
  rel_vol_major_airports %>%
  filter(Year == max(Year)) %>%
  arrange(rel) 

rel_vol_major_airports  %>%
  mutate(name = factor(name, levels = rev(last_values$name))) %>%
  ggplot(aes(x = Year, y = rel, group = name, color = name)) + 
  geom_line() 

## ----airport-decoder-----------------------------------------------------
otp201510 <- 
  fread("../dep_delay/On_Time_On_Time_Performance_2015_10.csv")

city_decoder <- 
  otp201510 %>%
  select(contains("Origin")) %>%
  unique

setkey(city_decoder, OriginCityMarketID)

gc(T,T)
city_market_decoder <- 
  fread("../metadata//L_CITY_MARKET_ID.csv") %>%
  setnames(old = c("Code", "Description"), 
           new = c("OriginCityMarketID", "OriginCityMarketDescription")) %>%
  setkey(OriginCityMarketID)
city_market_decoder[,OriginCityMarketID := as.integer(OriginCityMarketID)]
city_decoder <- merge(city_decoder, city_market_decoder, by = "OriginCityMarketID", all.x = TRUE, all.y = FALSE)
gc(T,T)

## ----Biggest-markets-out-of-SanFrancisco---------------------------------
market_volume_by_year <-
  flightsSanFran %>%
  filter(Dest %in% c("SFO", "OAK")) %>%
  merge(city_decoder, by = "Origin") %>%
  count(Year, OriginCityMarketDescription) %>%
  mutate(State = gsub("^.*([A-Z]{2}).*$", "\\1", OriginCityMarketDescription)) %>%
  filter(n > 3650) %>%
  mutate(Label = ifelse(Year == max(Year), OriginCityMarketDescription, NA_character_)) %>%
  arrange(Year, desc(n)) 

mkt.vol.by.yr <- function(year, colname){
  magrittr::extract2(dplyr::filter(market_volume_by_year, Year == year), colname)
}
market_volume_by_year %>%
  mutate(OriginCityMarketDescription = factor(OriginCityMarketDescription, levels = mkt.vol.by.yr(2015, "OriginCityMarketDescription"))) %>%
  ggplot(aes(x = Year, y = n, color = OriginCityMarketDescription, group = OriginCityMarketDescription)) + 
  #facet_grid(State ~ .) + 
  geom_line() + 
  #geom_text(aes(label = Label)) + 
  #geom_dl(method = list("top.points", dl.trans(y = y+0.25), fontfamily = "bold"), aes(label = OriginCityMarketDescription)) + 
  theme(legend.position = "none") -> p
direct.label(p, list("top.points", dl.trans(y = y+0.25), fontface="bold"))
  

## ----aircraft------------------------------------------------------------
FAA_aircraft <- 
  fread("../met")

## ----Cancellations-by-date-----------------------------------------------
flights %>% 
  group_by(Year, Month, DayofMonth) %>% 
  summarise(prop_cancelled = mean(Cancelled)) %>% 
  ggplot(aes(x = fasttime::fastPOSIXct(paste(Year, Month, DayofMonth, sep = "-")), y = prop_cancelled)) + 
  geom_bar(stat = "identity", width=1)

## ----Sept11-cumulative---------------------------------------------------
 flights %>% 
  group_by(Year, Month, DayofMonth) %>% 
  summarise(prop_cancelled = mean(Cancelled)) %>% 
  ungroup %>%
  mutate(rank = dense_rank(prop_cancelled)) %>% 
  ggplot(aes(x = jitter(rank, amount = 0.1), y = prop_cancelled)) + geom_bar(stat = "identity", width=1)

## ----Sept11-airports-----------------------------------------------------
flights %>%
  filter(Year == 2001, Month == 9, DayofMonth == 11) %>%
  group_by(Origin) %>%
  summarise(latest_departure = max(DepDateTimeZulu)) %>%
  ungroup %>%
  arrange(latest_departure) %>% 
  mutate(number_airports_closed = 1:n()) %>%
  ggplot(aes(x = latest_departure, y = number_airports_closed)) + 
  geom_line(group = 1) + 
  geom_vline(xintercept = as.numeric(as.POSIXct("2001-09-11 09:17:00"))) 

## ----FINISHTIME----------------------------------------------------------
FINISH.TIME <- Sys.time()

