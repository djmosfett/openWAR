% Generated by roxygen2 (4.0.1): do not edit by hand
\name{plot.openWARPlayers}
\alias{plot.openWARPlayers}
\title{plot.openWARPlayers}
\usage{
\method{plot}{openWARPlayers}(data, ...)
}
\arguments{
\item{data}{An object of class \code{"openWARPlayers"}}
}
\description{
Display a season's worth of openWAR results
}
\details{
Given an openWARPlayers object, draw a plot displaying each player's RAA, WAR, and replacement
level shadow.
}
\examples{
ds = getData()
out = makeWAR(ds)
players = getWAR(out$openWAR)
summary(players)
plot(players)
}

