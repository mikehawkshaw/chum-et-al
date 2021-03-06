# Catch table matrix creation 


# What I want: CPUE will be values to start, eventually IAs. 
#______________________________________________________________
#   Event         |   Bay 2     |    Bay 6     |     Bay 11    |
#_________________|_____________|______________|_______________|
# 20170403-0600   |   0.000     |              |               |
#          0601   |   0.000     |              |               |   
#          0602   |   0.000     |              |               |   
#          0615   |   0.000     |              |               |   
#          0616   |     x       |       x      |       x       |   
#          0620   |             |    0.000     |               |   
#          0631   |             |    0.000     |               |   
#          0632   |             |    0.000     |               |   
#          0635   |             |    0.000     |               |   
#          0636   |     x       |       x      |       x       |   
#          0640   |             |              |     0.000     |   
#          0641   |             |              |     0.000     |   
#          0642   |             |              |     0.000     |   
#          0655   |             |              |     0.000     |   
#           ...   |     ...     |      ...     |      ...      |        
#______________________________________________________________


# Set wd 
setwd("~/`Stock assessment/Analysis/Data files")

# Packages
library(dplyr)
library(tidyr)
library(ggplot2)
library(lubridate)
library(withr)
library(stringr)
library(padr)
library(lme4)
library(forecast)
library(ggfortify)
library(changepoint)
library(strucchange)
library(ggpmisc)
library(purrr)
library(imputeTS)
library(xts)


# Read data
data <- read.csv("TEB_leftjoin.csv")

# Create proper run time length
data <- data %>%
  select(everything()) %>%
  mutate_at(vars(c(17)), funs(as.character)) %>%
  mutate(run_time = paste(gsub("0:", "", run_time))) %>% 
  mutate_at(vars(c(17)), funs(as.numeric)) %>%
  mutate(run_time = run_time*60)


#######################################################################################################################################
#######################################################################################################################################


#                                                   THE FOLLOWING CODE CORRESPONDS TO
#                                               KD_202019_MissionSockeyeSmoltCPUECalibrations


#######################################################################################################################################

# First, simple subset data 
data <- data %>% 
  filter(trap_type == "RST") %>% 
  print()

#-------------------------------------------------------------------------------------------------------------------------------------


#########################
# CREATE MONSTER MATRIX #
#########################



####
# 1. Calculate CPUE for each run (to be time of day eventually)
####
# Create dataframe: select RST data, apply fished volumes
data <- data %>%
  filter(trap_type =="RST") %>%
  mutate(fished_vol = as.numeric(ifelse(run_time=="600", "1243.836",                                                                                  # Nested ifelse() command to apply volume of water fished for each run length that isn't 900 s
                                 ifelse(run_time=="1020", "2114.521",                                                                          # Syntax is "run seconds", "fished volume"
                                 ifelse(run_time=="1080", "2238.905",
                                 ifelse(run_time=="1140", "2363.288",
                                 ifelse(run_time=="1200", "2487.672",
                                 ifelse(run_time=="1260", "2612.056",
                                 ifelse(run_time=="1320", "2736.439", "1865.71"))))))))) %>%
  print()

# Summarize catch by USID and date, calculate CPUE by RUN  
CPUE <- data %>% 
  group_by(date, USID, fished_vol, set_start, set_end, bay) %>% 
  summarize(total_n = unique(sockeye_smolt_total)) %>%                           # Just used raw catch here as expanded isn't required
  mutate(CPUE_run = total_n/fished_vol) %>%                                      # Calculate CPUE 
  mutate(bay = ifelse(bay=="B2", "bay2",                                         # Rename Bays
               ifelse(bay=="B6", "bay6", "bay11"))) %>%
  print()


####
# 2. Reformat CPUE date-times 
####
# First set as character
CPUE$set_start <- as.character(CPUE$set_start)                                   
CPUE$set_end <- as.character(CPUE$set_end)

# Add zero to start of 3 digit numbers (i.e., 945 becomes 0945)
CPUE$set_start <- with_options(c(scipen = 999), str_pad(CPUE$set_start, 4, pad = "0"))
CPUE$set_end <- with_options(c(scipen = 999), str_pad(CPUE$set_end, 4, pad = "0"))

# Add colon after ever 2 digits
CPUE <- CPUE %>% 
  ungroup() %>%
  mutate(set_start = gsub('(.{2})', '\\1:', set_start)) %>%
  mutate(set_end = gsub('(.{2})', '\\1:', set_end))

    # Remove trailing colon
    CPUE$set_start <- str_sub(CPUE$set_start, 1, str_length(CPUE$set_start)-1)
    CPUE$set_end <- str_sub(CPUE$set_end, 1, str_length(CPUE$set_end)-1)

# Make as date-time (POSIXct) for minute intervals
CPUE$date_start = as.POSIXct(paste(CPUE$date, CPUE$set_start),tz = "")
CPUE$date_end = as.POSIXct(paste(CPUE$date, CPUE$set_end),tz = "")

####
# 3. Restructure, reformat dataframe
####
# Remove extra unneeded columns 
CPUE2 <- CPUE %>% 
  select(-c(fished_vol, total_n, date)) %>%
  print()

# Restructure start/end to be long form and rename columns
CPUE2 <- CPUE2 %>%
  gather("date_start", "date_end", 6:7) %>%                                           # Long form
  rename(key = date_start,
         value = date_end) %>% 
  print()

####
# 4. Expanding sampling time series
####
# Pad date-time minute intervals between sampling event start/end times 
CPUE_sub2 <- pad(CPUE2, interval="min", group="USID")

# Fill values between sampling event start and end (i.e., copy down 'bay' and 'CPUE_run' values)
CPUE_sub3 <- CPUE_sub2 %>%
  group_by(USID) %>%
  fill(set_start, set_end, bay, CPUE_run)

    # Remove other extra columns
    CPUE_sub3 <- CPUE_sub3 %>% 
      select(-set_start, -set_end, -key) %>% 
      arrange(value) %>%
      print()

    # Reformat to be wide format 
    CPUE_spr <- CPUE_sub3 %>% 
      spread(bay, CPUE_run) %>%                                                       # Wide form
      print()

####
# 5. Creating new time series to fill in un-sampled windows
####
# New empty time series for length of whole season, 1 minute intervals
ts.min <- data.frame(value=seq(ymd_hm("2017-04-03 06:07", tz=""), ymd_hm("2017-06-14 23:59", tz=""), by="1 min"))

# Merge CPUE and empty time series dataframes
CPUE_spr.merge <- left_join(ts.min, CPUE_spr, by="value")                             # left_join will preserve sampling intervals and just infill minute intervals between the end of a run and the beginning of another

    # Re-order columns for easy reading
    CPUE_spr.merge <- CPUE_spr.merge %>% 
      select(USID, value, bay2, bay6, bay11) %>% 
      arrange(value) %>% 
      print()

####
# 6. Ensure there are no duplicated date-time intervals
####
# Identify the row numbers of duplicates (used to index below)
which(duplicated(CPUE_spr.merge$value) | duplicated(CPUE_spr.merge$value, fromLast = TRUE))                   

# Pull out the metadata for each row number 
dupl_CPUE.merge <- CPUE_spr.merge %>% 
  mutate(dup_val = duplicated(value)) %>% 
  filter(dup_val) %>% 
  print()

# Change sampling date-time intervals for duplicated events manually 
CPUE_spr.merge[1509,2] <- as.POSIXct("2017-04-04 07:14:59")                                                    # dataframe[row, column]
CPUE_spr.merge[1510,2] <- as.POSIXct("2017-04-04 07:15:01")                                                       

CPUE_spr.merge[4642,2] <- as.POSIXct("2017-04-06 11:26:59")                                                        
CPUE_spr.merge[4643,2] <- as.POSIXct("2017-04-06 11:27:01")                                                        

CPUE_spr.merge[20207,2] <- as.POSIXct("2017-04-17 06:50:59")                                                       
CPUE_spr.merge[20208,2] <- as.POSIXct("2017-04-17 06:51:00")                                                    # This one actually had a catch associated so wanted to make sure it was maintained in that designation


# Re-check duplicates
which(duplicated(CPUE_spr.merge$value) | duplicated(CPUE_spr.merge$value, fromLast = TRUE))

dupl_CPUE.merge <- CPUE_spr.merge %>% 
  mutate(dup_val = duplicated(value)) %>% 
  filter(dup_val) %>% 
  print()

# The remaining duplicates appear to be data transcription errors where end and start times overlap (confirmed on hard copy).
  # I will change the second entry for each duplicate to move it ahead to allow for no overlap. 

####
# 7. Deal with two events with overlapping set end/start times
####
# APRIL 18 SERIES
CPUE_spr.merge[21806,2] <- as.POSIXct("2017-04-18 09:26:59")           # Changed from 09:27 to 09:26:59
CPUE_spr.merge[21803,2] <- as.POSIXct("2017-04-18 09:27:01")           # Changed from 09:27 to 09:27:01             
CPUE_spr.merge[21805,2] <- as.POSIXct("2017-04-18 09:41:00")           # Changed from 09:25 to 09:41 (just put to end rather than bump every entry as it doesn't actually matter)
CPUE_spr.merge[21807,2] <- as.POSIXct("2017-04-18 09:42:00")           # Changed from 09:26 to 09:42 (just put to end rather than bump every entry as it doesn't actually matter)

  # Remove duplicates at the end of the event
  CPUE_spr.merge <- CPUE_spr.merge[-c(21821, 21822), ]                   # Remove the old empty rows from 09:41 and 09:42

  # Export as csv otherwise row numbers get fucked up 
  write.csv(CPUE_spr.merge, "CPUE_spr_merge.csv", row.names = F)
  
  
# MAY 19 SERIES
# Re-load data 
CPUE_spr.merge2 <- read.csv("CPUE_spr_merge.csv")
CPUE_spr.merge2$value <- as.POSIXct(CPUE_spr.merge2$value)
  
# Re-check duplicates
which(duplicated(CPUE_spr.merge2$value) | duplicated(CPUE_spr.merge2$value, fromLast = TRUE))

dupl_CPUE.merge <- CPUE_spr.merge2 %>% 
  mutate(dup_val = duplicated(value)) %>% 
  filter(dup_val) %>% 
  print()

# May 19 overlap series
CPUE_spr.merge2[66322,2] <- as.POSIXct("2017-05-19 07:21:59")           # Changed from 07:22 to 07:21:59
CPUE_spr.merge2[66319,2] <- as.POSIXct("2017-05-19 07:36:00")           # Changed from 07:20 to 07:36 (just put to end rather than bump every entry as it doesn't actually matter)             
CPUE_spr.merge2[66321,2] <- as.POSIXct("2017-05-19 07:37:00")           # Changed from 07:21 to 07:37 (just put to end rather than bump every entry as it doesn't actually matter)
CPUE_spr.merge2[66323,2] <- as.POSIXct("2017-05-19 07:22:01")           # Changed from 07:22 to 07:22:01 

  # Remove duplicates at the end of the event
  CPUE_spr.merge2 <- CPUE_spr.merge2[-c(66337, 66338), ]                   # Remove the old empty rows from 07:36 and 07:37

  
# SUMMARY OF DUPLICATE WORK: 
  # For runs where the end and start times were the same (e.g., one run ended at 07:15 and the next started at 07:15), I separated
  # them by 1 second - new end time would become 07:14:59 and new start time would become 07:15:01. 
  # For the two cases (Apr 18 and May 19) where run end and start times overlapped by 2-3 minutes, the later run of the two was bumped
    # ahead by the time interval: 
      # Apr 18: Run 10 start and end times remained the same but bumped by 1 second (09:12 - 09:26:59)
              # Run 11 start and end times bumped 2 minutes forward. Old times: 09:25 - 09:40. New times: 09:27:10 - 09:42
      # May 19: Run 3 start and end times remained the same but bumped by 1 second (07:07 - 07:21:59)
              # Run 4 start and end times bumped 2 minutes forward. Old times: 07:20 - 07:35. New times: 07:22:01 - 07:37
# These times were given to Matt (Shane/Tod) so that the same corrections can be made in the raw Excel file, but I did not make any
# changes to the file myself! 
  
  
####
# 7. Export
####

write.csv(CPUE_spr.merge2, "mission_SO_CPUE_matrix.csv", row.names=F)






#-------------------------------------------------------------------------------------------------------------------------------------


                                                #_____________________#
                                                #      IA MATRIX      #
                                                #_____________________#



###############################################################
# 1. Calculate IA for each run (to be time of day eventually) #
###############################################################

# Create dataframe: select RST data, apply fished volumes
data <- data %>%
  filter(trap_type =="RST") %>%
  mutate(fished_vol = as.numeric(ifelse(run_time=="600", "1243.836",                                                                                  # Nested ifelse() command to apply volume of water fished for each run length that isn't 900 s
                                 ifelse(run_time=="1020", "2114.521",                                                                          # Syntax is "run seconds", "fished volume"
                                 ifelse(run_time=="1080", "2238.905",
                                 ifelse(run_time=="1140", "2363.288",
                                 ifelse(run_time=="1200", "2487.672",
                                 ifelse(run_time=="1260", "2612.056",
                                 ifelse(run_time=="1320", "2736.439", "1865.71"))))))))) %>%
  print()

# Summarize catch by USID and date, calculate CPUE by RUN  
IA <- data %>% 
  mutate(bay = ifelse(bay=="B2", "bay2",                                         
               ifelse(bay=="B6", "bay6", "bay11"))) %>%
  group_by(date, USID, fished_vol, set_start, set_end, bay) %>% 
  summarize(total_n = unique(sockeye_smolt_total), run_time = unique(run_time), 
            velocity=unique(current_speed_mps)) %>%                           
  mutate(CPUE_run = total_n/fished_vol) %>%                                     
  mutate(bay_width = 440/3) %>%                                                                                                                           # New column for Bay width (total river width = 440m/3 = Bay width)                                                                                                                                               
  mutate(bay_depth = 1.13) %>%                                                                                                                            # Bay depth for now is considered the RST fishing depth (1.13m)
  mutate(bay_volume_m3 = bay_width*bay_depth*velocity*run_time) %>%                                                                                   # Step 2: Volume of water in Bay during the whole run (Bay area*current velocity*run length)
  mutate(IA = CPUE_run*bay_volume_m3) 


####
# 2. Reformat IA date-times 
####
# First set as character
IA$set_start <- as.character(IA$set_start)                                   
IA$set_end <- as.character(IA$set_end)

# Add zero to start of 3 digit numbers (i.e., 945 becomes 0945)
IA$set_start <- with_options(c(scipen = 999), str_pad(IA$set_start, 4, pad = "0"))
IA$set_end <- with_options(c(scipen = 999), str_pad(IA$set_end, 4, pad = "0"))

# Add colon after ever 2 digits
IA <- IA %>% 
  ungroup() %>%
  mutate(set_start = gsub('(.{2})', '\\1:', set_start)) %>%
  mutate(set_end = gsub('(.{2})', '\\1:', set_end))

    # Remove trailing colon
    IA$set_start <- str_sub(IA$set_start, 1, str_length(IA$set_start)-1)
    IA$set_end <- str_sub(IA$set_end, 1, str_length(IA$set_end)-1)

# Make as date-time (POSIXct) for minute intervals
IA$date_start = as.POSIXct(paste(IA$date, IA$set_start),tz = "")
IA$date_end = as.POSIXct(paste(IA$date, IA$set_end),tz = "")

####
# 3. Restructure, reformat dataframe
####
# Remove extra unneeded columns 
IA2 <- IA %>% 
  select(-c(fished_vol, total_n, date, fished_vol, run_time, velocity, CPUE_run, bay_width, bay_depth, bay_volume_m3)) %>%
  print()

# Restructure start/end to be long form and rename columns
IA2 <- IA2 %>%
  gather("date_start", "date_end", 6:7) %>%                                           # Long form
  rename(key = date_start,
         value = date_end) %>% 
  print()

####
# 4. Expanding sampling time series
####
# Pad date-time minute intervals between sampling event start/end times 
IA_sub2 <- pad(IA2, interval="min", group="USID")

# Fill values between sampling event start and end (i.e., copy down 'bay' and 'CPUE_run' values)
IA_sub3 <- IA_sub2 %>%
  group_by(USID) %>%
  fill(set_start, set_end, bay, IA)

    # Remove other extra columns
    IA_sub3 <- IA_sub3 %>% 
      select(-set_start, -set_end, -key) %>% 
      arrange(value) %>%
      print()

    # Reformat to be wide format 
    IA_spr <- IA_sub3 %>% 
      spread(bay, IA) %>%                                                       # Wide form
      print()

####
# 5. Creating new time series to fill in un-sampled windows
####
# New empty time series for length of whole season, 1 minute intervals
ts.min <- data.frame(value=seq(ymd_hm("2017-04-03 06:07", tz=""), ymd_hm("2017-06-14 23:59", tz=""), by="1 min"))

# Merge CPUE and empty time series dataframes
IA_spr.merge <- left_join(ts.min, IA_spr, by="value")                             # left_join will preserve sampling intervals and just infill minute intervals between the end of a run and the beginning of another

    # Re-order columns for easy reading
    IA_spr.merge <- IA_spr.merge %>% 
      select(USID, value, bay2, bay6, bay11) %>% 
      arrange(value)

####
# 6. Ensure there are no duplicated date-time intervals
####
# Identify the row numbers of duplicates (used to index below)
which(duplicated(IA_spr.merge$value) | duplicated(IA_spr.merge$value, fromLast = TRUE))                   

# Pull out the metadata for each row number 
dupl_IA.merge <- IA_spr.merge %>% 
  mutate(dup_val = duplicated(value)) %>% 
  filter(dup_val) %>% 
  print()

# Change sampling date-time intervals for duplicated events manually 
IA_spr.merge[1509,2] <- as.POSIXct("2017-04-04 07:14:59")                                                    # dataframe[row, column]
IA_spr.merge[1510,2] <- as.POSIXct("2017-04-04 07:15:01")                                                       

IA_spr.merge[4642,2] <- as.POSIXct("2017-04-06 11:26:59")                                                        
IA_spr.merge[4643,2] <- as.POSIXct("2017-04-06 11:27:01")                                                        

IA_spr.merge[20207,2] <- as.POSIXct("2017-04-17 06:50:59")                                                       
IA_spr.merge[20208,2] <- as.POSIXct("2017-04-17 06:51:00")                                                    # This one actually had a catch associated so wanted to make sure it was maintained in that designation


# Re-check duplicates
which(duplicated(IA_spr.merge$value) | duplicated(IA_spr.merge$value, fromLast = TRUE))

dupl_IA.merge <- IA_spr.merge %>% 
  mutate(dup_val = duplicated(value)) %>% 
  filter(dup_val) %>% 
  print()

# The remaining duplicates appear to be data transcription errors where end and start times overlap (confirmed on hard copy).
  # I will change the second entry for each duplicate to move it ahead to allow for no overlap. 

####
# 7. Deal with two events with overlapping set end/start times
####
# APRIL 18 SERIES
IA_spr.merge[21806,2] <- as.POSIXct("2017-04-18 09:26:59")           # Changed from 09:27 to 09:26:59
IA_spr.merge[21803,2] <- as.POSIXct("2017-04-18 09:27:01")           # Changed from 09:27 to 09:27:01             
IA_spr.merge[21805,2] <- as.POSIXct("2017-04-18 09:41:00")           # Changed from 09:25 to 09:41 (just put to end rather than bump every entry as it doesn't actually matter)
IA_spr.merge[21807,2] <- as.POSIXct("2017-04-18 09:42:00")           # Changed from 09:26 to 09:42 (just put to end rather than bump every entry as it doesn't actually matter)

  # Remove duplicates at the end of the event
  IA_spr.merge <- IA_spr.merge[-c(21821, 21822), ]                   # Remove the old empty rows from 09:41 and 09:42

  # Export as csv otherwise row numbers get fucked up 
  write.csv(IA_spr.merge, "IA_spr_merge.csv", row.names = F)
  
  
# MAY 19 SERIES
# Re-load data 
IA_spr.merge2 <- read.csv("IA_spr_merge.csv")
IA_spr.merge2$value <- as.POSIXct(IA_spr.merge2$value)
  
# Re-check duplicates
which(duplicated(IA_spr.merge2$value) | duplicated(IA_spr.merge2$value, fromLast = TRUE))

dupl_IA.merge <- IA_spr.merge2 %>% 
  mutate(dup_val = duplicated(value)) %>% 
  filter(dup_val) %>% 
  print()

# May 19 overlap series
IA_spr.merge2[66322,2] <- as.POSIXct("2017-05-19 07:21:59")           # Changed from 07:22 to 07:21:59
IA_spr.merge2[66319,2] <- as.POSIXct("2017-05-19 07:36:00")           # Changed from 07:20 to 07:36 (just put to end rather than bump every entry as it doesn't actually matter)             
IA_spr.merge2[66321,2] <- as.POSIXct("2017-05-19 07:37:00")           # Changed from 07:21 to 07:37 (just put to end rather than bump every entry as it doesn't actually matter)
IA_spr.merge2[66323,2] <- as.POSIXct("2017-05-19 07:22:01")           # Changed from 07:22 to 07:22:01 

  # Remove duplicates at the end of the event
  IA_spr.merge2 <- IA_spr.merge2[-c(66337, 66338), ]                   # Remove the old empty rows from 07:36 and 07:37

  
# SUMMARY OF DUPLICATE WORK: 
  # For runs where the end and start times were the same (e.g., one run ended at 07:15 and the next started at 07:15), I separated
  # them by 1 second - new end time would become 07:14:59 and new start time would become 07:15:01. 
  # For the two cases (Apr 18 and May 19) where run end and start times overlapped by 2-3 minutes, the later run of the two was bumped
    # ahead by the time interval: 
      # Apr 18: Run 10 start and end times remained the same but bumped by 1 second (09:12 - 09:26:59)
              # Run 11 start and end times bumped 2 minutes forward. Old times: 09:25 - 09:40. New times: 09:27:10 - 09:42
      # May 19: Run 3 start and end times remained the same but bumped by 1 second (07:07 - 07:21:59)
              # Run 4 start and end times bumped 2 minutes forward. Old times: 07:20 - 07:35. New times: 07:22:01 - 07:37
# These times were given to Matt (Shane/Tod) so that the same corrections can be made in the raw Excel file, but I did not make any
# changes to the file myself! 
  
  
####
# 7. Export
####

write.csv(IA_spr.merge2, "mission_SO_IA_matrix.csv", row.names=F)





#               // end script

