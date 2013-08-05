#' @title makeWAR
#' 
#' @description Compute openWAR
#' 
#' @details Computes openWAR, given an MLBAM data set
#' 
#' @param data An MLBAM data.frame 
#' 
#' @return a data.frame
#' 
#' @export
#' @examples
#' 
#' ds = getData()
#' res = makeWAR(ds)
#' 

makeWAR = function (data, method = "simple", verbose = FALSE, ...) {
  # Step 1: Define \delta, the change in expected runs
  message("...Estimating Expected Runs...")
  fit.rem = getRunEx(data)
  data = transform(data, startExR = fit.rem(startCode, startOuts))
  data = transform(data, endExR = fit.rem(endCode, endOuts))
  data = transform(data, delta = endExR - startExR + runsOnPlay)
  
  # Step 2: Define RAA for the defense
  message("...Estimating Fielding Runs Above Average...")
  # Work only with the subset of data for which the ball is in play and keep track of the indices
  bip.idx = which(data$isBIP == TRUE)
  ds.field = data[bip.idx,]
  ds.field = getFielderRAA(ds.field)
  new.names = names(ds.field)[!names(ds.field) %in% names(data)]
  for(col.name in new.names) {
    data[bip.idx, col.name] = ds.field[,col.name]
  }
  
  # Step 3: Define RAA for the pitcher
  message("...Estimating Pitching Runs Above Average...")
  data$delta.pitch = with(data, ifelse(is.na(delta.field), delta, delta - delta.field))
  mod.pitch = lm(delta.pitch ~ stadium + (throws == stand), data = data)
  #  summary(mod.pitch)
  data$raa.pitch = -mod.pitch$residuals
  
  # Step 4: Define RAA for the batter
  message("...Estimating Batting Runs Above Average...")
  require(plyr)
  
  if ( method == "ghostrunner") {
    # Figure out the most common outcome for every beginning state and event type
    getMostCommon = function(df) {
      outcomes = ddply(df, ~endCode + endOuts + runsOnPlay, summarise, N = length(endCode))
      outcomes$Pct = outcomes$N / nrow(df)
      names(outcomes)[which(names(outcomes) %in% c("endCode", "endOuts", "runsOnPlay"))] = c("endBatCode", "endBatOuts", "batRunsOnPlay")
      return(outcomes[which.max(outcomes$N),])
    }
    event.lkup = ddply(data, ~startCode + startOuts + event, getMostCommon)
    #  densityplot(~Pct, data=event.lkup)
    event.lkup = transform(event.lkup, bat.ExR = fit.rem(endBatCode, endBatOuts) + batRunsOnPlay)
    data = merge(x=data, y=event.lkup[, c("startCode", "startOuts", "event", "endBatCode", "endBatOuts", "batRunsOnPlay", "bat.ExR")]
                 , by = c("startCode", "startOuts", "event"), all.x=TRUE)
    
    # Assign that difference to the batter
    data = transform(data, delta.bat = bat.ExR - startExR)     
    mod.bat = lm(delta.bat ~ as.factor(batterPos) + stadium + (stand == throws), data=data)
    #  summary(mod.bat)
    data = transform(data, raa.bat = mod.bat$residuals)   
  } else {
    # Control for circumstances
    mod.off = lm(delta ~ stadium + (stand == throws), data=data)
    # summary(mod.off)
    # delta.off is the contribution above average of the batter AND all of the runners
    data = transform(data, delta.off = mod.off$residuals)  
    # Siphon off the portion attributable to the baserunners
    br.idx = which(data$startCode > 0)
    mod.br = lm(delta.off ~ event * as.factor(startCode) * as.factor(startOuts), data=data[br.idx,])
    data[br.idx, "delta.br"] = mod.br$residuals
    # Whatever is left over goes to the batter
    data$delta.bat = with(data, ifelse(is.na(delta.br), delta, delta - delta.br))
#    data = transform(data, delta.bat = delta - delta.br)
    mod.bat = lm(delta.bat ~ as.factor(batterPos), data=data)
    data = transform(data, raa.bat = mod.bat$residuals)
  }
  
  if (verbose) {
    cat(coef(mod.bat))
  }
  
  # Step 5: Define RAA for the baserunners
  message("...Estimating Baserunning Runs Above Average...")
  
  require(MASS)
  require(stringr)
  # Figure out what happened to the runner on 3B
  data$dest.br3 = with(data, ifelse(str_count(runnerMovement, paste(start3B, ":3B::T:", sep="")), "H", NA))
  data$dest.br3 = with(data, ifelse(!is.na(start3B) & !is.na(end3B) & start3B == end3B, "3B", dest.br3))
  
  br3.idx = which(!is.na(data$start3B))
  ds3 = data[br3.idx,]
  br3.scored = with(ds3, str_count(runnerMovement, paste(start3B, ":3B::T:", sep="")))
  br3.out = with(ds3, str_count(runnerMovement, paste(start3B, ":3B:::", sep="")))
  ds3$basesAdvanced = ifelse(br3.scored == 1, 1, ifelse(br3.out == 1, -3, 0))
  
  # Figure out what happened to the runner on 2B
  data$dest.br2 = with(data, ifelse(str_count(runnerMovement, paste(start2B, ":2B::T:", sep="")), "H", NA))
  data$dest.br2 = with(data, ifelse(!is.na(start2B) & !is.na(end3B) & start2B == end3B, "3B", dest.br2))
  data$dest.br2 = with(data, ifelse(!is.na(start2B) & !is.na(end2B) & start2B == end2B, "2B", dest.br2))
  
  br2.idx = which(!is.na(data$start2B))
  ds2 = data[br2.idx,]
  br2.scored = with(ds2, str_count(runnerMovement, paste(start2B, ":2B::T:", sep="")))
  br2.out = with(ds2, str_count(runnerMovement, paste(start2B, ":2B:::", sep="")))
  br2.advanced = with(ds2, str_count(runnerMovement, paste(start2B, ":2B:3B::", sep="")))
  ds2$basesAdvanced = ifelse(br2.scored == 1, 2, ifelse(br2.out == 1, -2, ifelse(br2.advanced == 1, 1, 0)))
  
  # Figure out what happened to the runner on 1B
  data$dest.br1 = with(data, ifelse(str_count(runnerMovement, paste(start1B, ":1B::T:", sep="")), "H", NA))
  data$dest.br1 = with(data, ifelse(!is.na(start1B) & !is.na(end3B) & start1B == end3B, "3B", dest.br1))
  data$dest.br1 = with(data, ifelse(!is.na(start1B) & !is.na(end2B) & start1B == end2B, "2B", dest.br1))
  data$dest.br1 = with(data, ifelse(!is.na(start1B) & !is.na(end1B) & start1B == end1B, "1B", dest.br1))
  
  br1.idx = which(!is.na(data$start1B))
  ds1 = data[br1.idx,]
  br1.scored = with(ds1, str_count(runnerMovement, paste(start1B, ":1B::T:", sep="")))
  br1.out = with(ds1, str_count(runnerMovement, paste(start1B, ":1B:::", sep="")))
  br1.advanced.one = with(ds1, str_count(runnerMovement, paste(start1B, ":1B:2B::", sep="")))
  br1.advanced.two = with(ds1, str_count(runnerMovement, paste(start1B, ":1B:3B::", sep="")))
  ds1$basesAdvanced = ifelse(br1.scored == 1, 3, ifelse(br1.out == 1, -1, ifelse(br1.advanced.one == 1, 1, ifelse(br1.advanced.two == 1, 2, 0))))
  
  # Compute the number of bases advanced by each baserunner
  # data$br0.adv = ifelse(br0.scored == 1, 4, ifelse(br0.advanced.one == 1, 1, ifelse(br0.advanced.two == 1, 2, ifelse(br0.advanced.three == 1, 3, 0))))
  data[br1.idx, "br1.adv"] = ds1$basesAdvanced
  data[br2.idx, "br2.adv"] = ds2$basesAdvanced
  data[br3.idx, "br3.adv"] = ds3$basesAdvanced
  
  # Compute the empirical probabilities
  # events for the runner on third
#   ds3Tab <- ddply(ds3, basesAdvanced ~ event + startOuts + startCode, summarize, N=length(basesAdvanced))
#   ds3TabEvent <- ddply(ds3Tab, ~event + startOuts + startCode, summarize, Nevent=sum(N))
#   ds3Probs<-merge(ds3Tab,ds3TabEvent,by.x=c("event","startOuts","startCode"),by.y=c("event","startOuts","startCode"),all.x=TRUE)
#   ds3Probs$probs<-ds3Probs$N/ds3Probs$Nevent
#   ds3Probs$index<-paste(ds3Probs$event,ds3Probs$startOuts,ds3Probs$startCode,sep="-")
#   ds3Probs<-ds3Probs[order(ds3Probs$index,ds3Probs$basesAdvanced),]
#   cdf.br3 <- tapply(ds3Probs$probs, ds3Probs$index,cumsum)
#   ds3Probs<-cbind(ds3Probs,cdf.br3=unlist(cdf.br3))
#   ds3Probs<-ds3Probs[,c("startCode","startOuts","event","basesAdvanced","cdf.br3")]
#   data<-merge(data,ds3Probs,by.x=c("startCode","startOuts","event","br3.adv"),by.y=c("startCode","startOuts","event","basesAdvanced"),all.x=TRUE)
#   
#   #events for the runner on second
#   ds2Tab<-ddply(ds2, basesAdvanced~event+startOuts+startCode, summarize, N=length(basesAdvanced))
#   ds2TabEvent<-ddply(ds2Tab,~event+startOuts+startCode,summarize,Nevent=sum(N))
#   ds2Probs<-merge(ds2Tab,ds2TabEvent,by.x=c("event","startOuts","startCode"),by.y=c("event","startOuts","startCode"),all.x=TRUE)
#   ds2Probs$probs<-ds2Probs$N/ds2Probs$Nevent
#   ds2Probs$index<-paste(ds2Probs$event,ds2Probs$startOuts,ds2Probs$startCode,sep="-")
#   ds2Probs<-ds2Probs[order(ds2Probs$index,ds2Probs$basesAdvanced),]
#   cdf.br2<-tapply(ds2Probs$probs,ds2Probs$index,cumsum)
#   ds2Probs<-cbind(ds2Probs,cdf.br2=unlist(cdf.br2))
#   ds2Probs<-ds2Probs[,c("startCode","startOuts","event","basesAdvanced","cdf.br2")]
#   data<-merge(data,ds2Probs,by.x=c("startCode","startOuts","event","br2.adv"),by.y=c("startCode","startOuts","event","basesAdvanced"),all.x=TRUE)
#   
#   
#   #events for the runner on first
#   ds1Tab<-ddply(ds1, basesAdvanced~event+startOuts+startCode, summarize, N=length(basesAdvanced))
#   ds1TabEvent<-ddply(ds1Tab,~event+startOuts+startCode,summarize,Nevent=sum(N))
#   ds1Probs<-merge(ds1Tab,ds1TabEvent,by.x=c("event","startOuts","startCode"),by.y=c("event","startOuts","startCode"),all.x=TRUE)
#   ds1Probs$probs<-ds1Probs$N/ds1Probs$Nevent
#   ds1Probs$index<-paste(ds1Probs$event,ds1Probs$startOuts,ds1Probs$startCode,sep="-")
#   ds1Probs<-ds1Probs[order(ds1Probs$index,ds1Probs$basesAdvanced),]
#   cdf.br1<-tapply(ds1Probs$probs,ds1Probs$index,cumsum)
#   ds1Probs<-cbind(ds1Probs,cdf.br1=unlist(cdf.br1))
#   ds1Probs<-ds1Probs[,c("startCode","startOuts","event","basesAdvanced","cdf.br1")]
#   data<-merge(data,ds1Probs,by.x=c("startCode","startOuts","event","br1.adv"),by.y=c("startCode","startOuts","event","basesAdvanced"),all.x=TRUE)
#   
#   
#   ds1Tab <- ddply(ds1, ~ event + startCode + startOuts + basesAdvanced, summarise, N = length(basesAdvanced))
#   ds1TabEvent <- ddply(ds1Tab, ~ event + startCode + startOuts, summarise, Nevent = sum(N))
#   ds1Probs <- merge(ds1Tab, ds1TabEvent, all.x=TRUE)
#   ds1Probs = transform(ds1Probs, p = N / Nevent)
#   ds1Probs <- ds1Probs[with(ds1Probs, order(event, startCode, startOuts, basesAdvanced)),]
#   ds1Cdf = ddply(ds1Probs, ~ event + startCode + startOuts, summarise, cdf = c(0, cumsum(p[-length(p)])))
#   ds1Probs$cdf = ds1Cdf$cdf
  
#  ds = subset(ds1, event == "Double" & startCode == 3 & startOuts == 1)
  
  getCDF = function (ds) {
    events = ddply(ds, ~basesAdvanced, summarise, N = length(basesAdvanced))
    events = transform(events, numObs = nrow(ds))
    events = transform(events, p = N / numObs)
    events$cdf = cumsum(events$p)
    events$cdf.lag = c(0, cumsum(events$p[-nrow(events)]))
    return(events)
  }
  
  ds3Probs = ddply(ds3, ~event + startCode + startOuts, getCDF)
  ds2Probs = ddply(ds2, ~event + startCode + startOuts, getCDF)
  ds1Probs = ddply(ds1, ~event + startCode + startOuts, getCDF)
  
  # Merge onto the main data frame
  join.idx = c("event", "startCode", "startOuts")
  data = merge(x = data, y = ds3Probs[,c(join.idx, "basesAdvanced", "cdf.lag")], by.x = c(join.idx, "br3.adv"), by.y = c(join.idx, "basesAdvanced"), all.x=TRUE)
  # Rename column
  data = rename(data, c("cdf.lag" = "cdf.br3"))

  data = merge(x = data, y = ds2Probs[,c(join.idx, "basesAdvanced", "cdf.lag")], by.x = c(join.idx, "br2.adv"), by.y = c(join.idx, "basesAdvanced"), all.x=TRUE)
  data = rename(data, c("cdf.lag" = "cdf.br2"))
  data = merge(x = data, y = ds1Probs[,c(join.idx, "basesAdvanced", "cdf.lag")], by.x = c(join.idx, "br1.adv"), by.y = c(join.idx, "basesAdvanced"), all.x=TRUE)
  data = rename(data, c("cdf.lag" = "cdf.br1"))
  
  # Compute a share for each baserunner
  data$cdf.br1[is.na(data$cdf.br1)]<-0
  data$cdf.br2[is.na(data$cdf.br2)]<-0
  data$cdf.br3[is.na(data$cdf.br3)]<-0
  
  #normalize the cdf probs
  data$share.br1<-data$cdf.br1 / (data$cdf.br1 + data$cdf.br2 + data$cdf.br3)
  data$share.br2<-data$cdf.br2 / (data$cdf.br1 + data$cdf.br2 + data$cdf.br3)
  data$share.br3<-data$cdf.br3 / (data$cdf.br1 + data$cdf.br2 + data$cdf.br3)
  
  
  
  #  data$delta.br0 = with(data, ifelse(basesAdvanced == 0, 0, delta.br * (br0.extra / basesAdvanced)))
  data$delta.br[is.na(data$delta.br)]<-0
  data$raa.br1 = data$share.br1*data$delta.br
  data$raa.br2 = data$share.br2*data$delta.br
  data$raa.br3 = data$share.br3*data$delta.br
  
  #  mod.br3 = lm(basesAdvanced ~ event * as.factor(startOuts), data = ds3)
  #  mod.br2 = lm(basesAdvanced ~ event * as.factor(startOuts), data = ds2)
  #  mod.br1 = lm(basesAdvanced ~ event * as.factor(startOuts), data = ds1)
  #  mod.br0 = lm(br0.adv ~ event * as.factor(startOuts), data = data)
  #  bwplot(mod.br3$resid ~ event, data=ds3)
  #  bwplot(mod.br2$resid ~ event, data=ds2)
  
  #mod.br3 = lm(delta.br3 ~ event * as.factor(startOuts), data = data)
  #mod.br2 = lm(delta.br2 ~ event * as.factor(startOuts), data = data)
  #mod.br1 = lm(delta.br1 ~ event * as.factor(startOuts), data = data)
  #  mod.br0 = lm(delta.br0 ~ event + as.factor(startOuts), data = data)
  
  # Placeholder in case we want to use this later on
  #  data$raa.br0 = mod.br0$residuals
  #data$raa.br0 = 0
  #data[!is.na(data$delta.br3), "raa.br3"] = mod.br3$residuals
  #data[!is.na(data$delta.br2), "raa.br2"] = mod.br2$residuals
  #data[!is.na(data$delta.br1), "raa.br1"] = mod.br1$residuals
  
  return(data)
}


#' @title shakeWAR
#' 
#' @description resample a data.frame to obtain variance estimate for WAR
#' 
#' @details Resamples the rows of an MLBAM data set
#' 
#' @param data An MLBAM data.frame 
#' @param N the number of resamples (default 5000)
#' 
#' @return a data.frame with RAA values 
#' 
#' @export
#' @examples
#' 
#' ds = getData()
#' ds = makeWAR()
#' res = shakeWAR(ds)
#' res = getWAR(ds)
#' 

shakeWAR = function (data, N = 10, ...) {
  require(mosaic)
  raa.fields = c("raa.bat", "raa.br1", "raa.br2", "raa.br3", "raa.pitch", "raa.P", "raa.C", "raa.1B"
                 , "raa.2B", "raa.3B", "raa.SS", "raa.LF", "raa.CF", "raa.RF")
  if (length(intersect(raa.fields, names(data))) < length(raa.fields)) {
    ds = makeWAR(data)
  } else {
    ds = data
  }
  id.fields = c("batterId", "start1B", "start2B", "start3B", "pitcherId", "playerId.C", "playerId.1B"
                , "playerId.2B", "playerId.3B", "playerId.SS", "playerId.LF", "playerId.CF", "playerId.RF"
                , "batterName", "pitcherName", "gameId", "event")
  ds.raa = ds[, c(id.fields, raa.fields)]
  bstrap = do(N) * getWAR(resample(ds.raa))
  return(bstrap)
}

#' @title getWAR
#' 
#' @description Retrieve openWAR
#' 
#' @details Retrieves openWAR, aggregated by player, given an MLBAM data set
#' 
#' @param data An MLBAM data.frame 
#' 
#' @return a data.frame of RAA values per player
#' 
#' @export
#' @examples
#' 
#' ds = getData()
#' res = getWAR(ds)
#' 

getWAR = function (data, recompute = FALSE, ...) {
  # Check to see if the WAR fields already exist
  raa.fields = c("raa.bat", "raa.br1", "raa.br2", "raa.br3", "raa.pitch", "raa.P", "raa.C", "raa.1B"
                 , "raa.2B", "raa.3B", "raa.SS", "raa.LF", "raa.CF", "raa.RF")
  if (length(intersect(raa.fields, names(data))) < length(raa.fields) | recompute) {
    ds = makeWAR(data)
  } else {
    ds = data
  }
  
  message("...Tabulating RAA per player...")
  require(plyr)
  war.bat = ddply(ds, ~ batterId, summarise, Name = max(as.character(batterName))
                  , PA = length(batterId), G = length(unique(gameId)), HR = sum(event=="Home Run")
                  , RAA.bat = sum(raa.bat, na.rm=TRUE))
  # war.br0 = ddply(ds, ~batterId, summarise, RAA.br0 = sum(raa.br0, na.rm=TRUE))
  war.br1 = ddply(ds, ~start1B, summarise, RAA.br1 = sum(raa.br1, na.rm=TRUE))
  war.br2 = ddply(ds, ~start2B, summarise, RAA.br2 = sum(raa.br2, na.rm=TRUE))
  war.br3 = ddply(ds, ~start3B, summarise, RAA.br3 = sum(raa.br3, na.rm=TRUE))
  
  war.P = ddply(ds, ~pitcherId, summarise, RAA.P = sum(raa.P, na.rm=TRUE))
  war.C = ddply(ds, ~playerId.C, summarise, RAA.C = sum(raa.C, na.rm=TRUE))
  war.1B = ddply(ds, ~playerId.1B, summarise, RAA.1B = sum(raa.1B, na.rm=TRUE))
  war.2B = ddply(ds, ~playerId.2B, summarise, RAA.2B = sum(raa.2B, na.rm=TRUE))
  war.3B = ddply(ds, ~playerId.3B, summarise, RAA.3B = sum(raa.3B, na.rm=TRUE))
  war.SS = ddply(ds, ~playerId.SS, summarise, RAA.SS = sum(raa.SS, na.rm=TRUE))
  war.LF = ddply(ds, ~playerId.LF, summarise, RAA.LF = sum(raa.LF, na.rm=TRUE))
  war.CF = ddply(ds, ~playerId.CF, summarise, RAA.CF = sum(raa.CF, na.rm=TRUE))
  war.RF = ddply(ds, ~playerId.RF, summarise, RAA.RF = sum(raa.RF, na.rm=TRUE))
  war.pitch = ddply(ds, ~ pitcherId, summarise, Name = max(as.character(pitcherName)), BF = length(pitcherId), RAA.pitch = sum(raa.pitch))
  
  # players = merge(x=war.bat, y=war.br0, by.x="batterId", by.y="batterId", all=TRUE)
  players = merge(x=war.bat, y=war.br1, by.x="batterId", by.y="start1B", all=TRUE)
  players = merge(x=players, y=war.br2, by.x="batterId", by.y="start2B", all=TRUE)
  players = merge(x=players, y=war.br3, by.x="batterId", by.y="start3B", all=TRUE)
  players = merge(x=players, y=war.pitch, by.x="batterId", by.y="pitcherId", all=TRUE)
  players$Name = with(players, ifelse(is.na(Name.x), Name.y, Name.x))
  players = merge(x=players, y=war.P, by.x="batterId", by.y="pitcherId", all=TRUE)
  players = merge(x=players, y=war.C, by.x="batterId", by.y="playerId.C", all=TRUE)
  players = merge(x=players, y=war.1B, by.x="batterId", by.y="playerId.1B", all=TRUE)
  players = merge(x=players, y=war.2B, by.x="batterId", by.y="playerId.2B", all=TRUE)
  players = merge(x=players, y=war.3B, by.x="batterId", by.y="playerId.3B", all=TRUE)
  players = merge(x=players, y=war.SS, by.x="batterId", by.y="playerId.SS", all=TRUE)
  players = merge(x=players, y=war.LF, by.x="batterId", by.y="playerId.LF", all=TRUE)
  players = merge(x=players, y=war.CF, by.x="batterId", by.y="playerId.CF", all=TRUE)
  players = merge(x=players, y=war.RF, by.x="batterId", by.y="playerId.RF", all=TRUE)
  players[is.na(players)] = 0
  players = transform(players, RAA.br =  RAA.br1 + RAA.br2 + RAA.br3)
  players = transform(players, RAA.off = RAA.bat + RAA.br)
  players = transform(players, RAA.field = RAA.P + RAA.C + RAA.1B + RAA.2B + RAA.3B + RAA.SS + RAA.LF + RAA.CF + RAA.RF)
  players = transform(players, RAA = RAA.bat + RAA.br + RAA.pitch + RAA.field)
  players = transform(players, TPA = PA + BF)
  players = players[, setdiff(names(players), c("Name.x", "Name.y"))]
  return(players)
}

#' 
#' @title getFielderRAA
#' 
#' @description Determine the RAA of the fielders
#' 
#' @details RAA is the residuals from a simple fielding model
#' 
#' @param data An MLBAM data.frame of BIPs
#' 
#' @return a matrix of Runs Above Average (RAA)
#' 
#' @export
#' @examples
#' 
#' ds = getData()
#' ds$resp.field = getFieldResp(ds)
#' 

getFielderRAA = function (data) {
  # Compute the collective responsibility of all fielders
  data$resp.field = getFieldResp(data)
  # Compute the individual responsibility of each fielder
  resp.fielders = getFielderResp(data)
  
  # Step 2a: Define \delta.field for the defense, collectively
  data$delta.field = with(data, delta * resp.field)
  # Step 2b: Define \delta.field for the defense, individually
  delta.fielders = data$delta.field * resp.fielders
  names(delta.fielders) = gsub("resp", "delta", names(delta.fielders))
  data = cbind(data, delta.fielders)
  
  # Build a model for each fielder's expected change in runs
  mod.P = lm(delta.P ~ stadium, data = data)
  mod.C = lm(delta.C ~ stadium, data = data)
  mod.1B = lm(delta.1B ~ stadium, data = data)
  mod.2B = lm(delta.2B ~ stadium, data = data)
  mod.3B = lm(delta.3B ~ stadium, data = data)
  mod.SS = lm(delta.SS ~ stadium, data = data)
  mod.LF = lm(delta.LF ~ stadium, data = data)
  mod.CF = lm(delta.CF ~ stadium, data = data)
  mod.RF = lm(delta.RF ~ stadium, data = data)
  
  # Define RAA to be the residuals from the individual fielders models
  raa = -data.frame(mod.P$residuals, mod.C$residuals, mod.1B$residuals, mod.2B$residuals, mod.3B$residuals
                    , mod.SS$residuals, mod.LF$residuals, mod.CF$residuals, mod.RF$residuals)
  names(raa) = gsub("mod", "raa", gsub(".residuals", "", names(raa)))
  
  # The column-wise sums should all be zero
  #  colSums(raa)
  data = cbind(data, raa)
  return(data)
}



#' 
#' @title getFieldResp
#' 
#' @description Determine the responsibility of the fielders
#' 
#' @details Computes a 2D kernel smoothed estimate of the probability that *any* of the 9 fielders
#' will make a play on a ball in play
#' 
#' @param data An MLBAM data.frame 
#' 
#' @return a vector representing the probability that each ball in play will be fielded
#' 
#' @export
#' @examples
#' 
#' ds = getData()
#' ds$resp.field = getFieldResp(ds)
#' 

getFieldResp = function (data) {
  require(KernSmooth)
  outs = subset(data, !is.na(fielderId), select=c("our.x", "our.y"))
  hits = subset(data, is.na(fielderId), select=c("our.x", "our.y"))
  # Find 2D kernel density estimates for hits and outs
  # Make sure to specify the range, so that they over estimated over the same grid
  grid = list(range(data$our.x, na.rm=TRUE), range(data$our.y, na.rm=TRUE))
  fit.out <- bkde2D(outs, bandwidth = c(10,10), range.x = grid)
  fit.hit <- bkde2D(hits, bandwidth = c(10,10), range.x = grid)
  
  field.smooth = data.frame(cbind(expand.grid(fit.out$x1, fit.out$x2), isOut = as.vector(fit.out$fhat)), isHit = as.vector(fit.hit$fhat))
  names(field.smooth)[1:2] = c("x", "y")
  # Plot the surfaces
  #  wireframe(isOut ~ x + y, data=field.smooth, scales = list(arrows = FALSE), drape = TRUE, colorkey = TRUE)
  #  wireframe(isHit ~ x + y, data=field.smooth, scales = list(arrows = FALSE), drape = TRUE, colorkey = TRUE)
  
  # Make sure to add a small amount to avoid division by zero
  field.smooth = transform(field.smooth, wasFielded = isOut / (isOut + isHit + 0.00000001))
  # summary(field.smooth)
  # wireframe(wasFielded ~ x + y, data=field.smooth, scales = list(arrows = FALSE), drape = TRUE, colorkey = TRUE)
  
  fit.all = function (x, y) {
    require(Hmisc)
    x.idx = whichClosest(field.smooth$x, x)
    y.idx = whichClosest(field.smooth$y, y)
    match = subset(field.smooth, x == field.smooth$x[x.idx] & y == field.smooth$y[y.idx])
    return(match$wasFielded)
  }
  
  resp.field = mapply(fit.all, data$our.x, data$our.y)
  return(resp.field)
}

#' @title getFielderResp
#' 
#' @description Find the shared responsibility for balls in play
#' 
#' @details Fits 9 logistic regression models, each giving the probability of 
#' a fielder at one of the 9 defensive positions successfully converting the 
#' ball into at least one out.
#' 
#' @param data An MLBAM data.frame 
#' 
#' @return data.frame with 9 columns, each row representing a ball in play
#' 
#' @export
#' @examples
#' 
#' ds = getData()
#' setBIPresp(ds)

getFielderResp = function (data, ...) {
  require(mosaic)
  ds = transform(data, wasFielded = !is.na(fielderId))
  ds$fielderPos = with(ds, ifelse(is.na(fielderId), "Hit", "Out"))
  ds$fielderPos = with(ds, ifelse(!is.na(fielderId) & fielderId == pitcherId, "P", fielderPos))
  ds$fielderPos = with(ds, ifelse(!is.na(fielderId) & fielderId == playerId.C, "C", fielderPos))
  ds$fielderPos = with(ds, ifelse(!is.na(fielderId) & fielderId == playerId.1B, "1B", fielderPos))
  ds$fielderPos = with(ds, ifelse(!is.na(fielderId) & fielderId == playerId.2B, "2B", fielderPos))
  ds$fielderPos = with(ds, ifelse(!is.na(fielderId) & fielderId == playerId.3B, "3B", fielderPos))
  ds$fielderPos = with(ds, ifelse(!is.na(fielderId) & fielderId == playerId.SS, "SS", fielderPos))
  ds$fielderPos = with(ds, ifelse(!is.na(fielderId) & fielderId == playerId.LF, "LF", fielderPos))
  ds$fielderPos = with(ds, ifelse(!is.na(fielderId) & fielderId == playerId.CF, "CF", fielderPos))
  ds$fielderPos = with(ds, ifelse(!is.na(fielderId) & fielderId == playerId.RF, "RF", fielderPos))
  
  mod.P = glm((fielderPos == "P") ~ poly(our.x, 2) + poly(our.y, 2) + I(our.x * our.y), data=ds, family="binomial")
  mod.C = glm((fielderPos == "C") ~ poly(our.x, 2) + poly(our.y, 2) + I(our.x * our.y), data=ds, family="binomial")
  mod.1B = glm((fielderPos == "1B") ~ poly(our.x, 2) + poly(our.y, 2), data=ds, family="binomial")
  mod.2B = glm((fielderPos == "2B") ~ poly(our.x, 2) + poly(our.y, 2) + I(our.x * our.y), data=ds, family="binomial")
  mod.3B = glm((fielderPos == "3B") ~ poly(our.x, 2) + poly(our.y, 2) + I(our.x * our.y), data=ds, family="binomial")
  mod.SS = glm((fielderPos == "SS") ~ poly(our.x, 2) + poly(our.y, 2) + I(our.x * our.y), data=ds, family="binomial")
  mod.LF = glm((fielderPos == "LF") ~ poly(our.x, 2) + poly(our.y, 2) + I(our.x * our.y), data=ds, family="binomial")
  mod.CF = glm((fielderPos == "CF") ~ poly(our.x, 2) + poly(our.y, 2) + I(our.x * our.y), data=ds, family="binomial")
  mod.RF = glm((fielderPos == "RF") ~ poly(our.x, 2) + poly(our.y, 2) + I(our.x * our.y), data=ds, family="binomial")
  
  #   mod = mod.CF
  #   summary(mod)
  #   fit = makeFun(mod)
  #   plotFun(fit(x,y) ~ x + y, surface=TRUE, alpha=0.9
  #           , xlim = c(-350, 350), ylim = c(0, 550)
  #           , xlab = "Horizontal Distance from Home Plate (ft.)"
  #           , ylab = "Vertical Distance from Home Plate (ft.)"
  #           , zlab = "Probability of Making a Play"
  #   )
  
  out = data.frame(mod.P$fitted, mod.C$fitted, mod.1B$fitted, mod.2B$fitted, mod.3B$fitted
                   , mod.SS$fitted, mod.LF$fitted, mod.CF$fitted, mod.RF$fitted)
  row.sums = apply(out, 1, sum)
  out = out / row.sums
  names(out) = c("resp.P", "resp.C", "resp.1B", "resp.2B", "resp.3B", "resp.SS", "resp.LF", "resp.CF", "resp.RF")
  return(out)
}