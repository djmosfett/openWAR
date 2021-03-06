% Generated by roxygen2 (4.0.1): do not edit by hand
\name{plot.do.openWARPlayers}
\alias{plot.do.openWARPlayers}
\title{plot.do.openWARPlayers}
\usage{
\method{plot}{do.openWARPlayers}(data, playerIds = c(431151, 285079), ...)
}
\arguments{
\item{playerIds}{A vector of valid MLBAM player IDs present in the data argument}

\item{data}{A data.frame resulting from shakeWAR() of class \code{do.openWARPlayers}}
}
\value{
a faceted densityplot
}
\description{
Visualize WAR
}
\details{
Density Plot for WAR estimates
}
\examples{
ds = getData()
# not run
openWAR = makeWAR(ds)
openWAR.sim = shakeWAR(openWAR)
plot(data=openWAR.sim, playerIds = c(431151, 502517, 408234, 285078, 518774, 285079))
}

