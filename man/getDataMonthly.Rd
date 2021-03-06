% Generated by roxygen2 (4.0.1): do not edit by hand
\name{getDataMonthly}
\alias{getDataMonthly}
\title{getDataMonthly}
\usage{
getDataMonthly(yyyy = 2013, m = 5)
}
\arguments{
\item{yyyy}{A year}

\item{m}{a numeric value corresponding to a month}
}
\value{
A data.frame of class GameDayPlays consisting of play-by-play data
}
\description{
Retrieves MLBAM GameDay files for a single month
}
\details{
Given a year and month, this function will retrieve data from the
GameDay server from the specified month and process them into a single data.frame.
}
\examples{
#Retrieve all of the MLBAM data from May 2013
ds = getMonthlyData(2013, 5)
}

