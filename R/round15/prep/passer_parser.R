# Round 15 P3: primary-passer identification from play text, in both CFBD text formats.
#   old:        "Athan Kaliakmanis pass complete to ..."            -> "Athan Kaliakmanis"
#   stat crew:  "(14:23) Shotgun #16 A.Kaliakmanis pass complete ..." -> "#16 A.Kaliakmanis"
# Names are compared within a team and season only, so the two formats never need to be reconciled.
r15_dropback_types <- c("Pass", "Pass Reception", "Pass Completion", "Pass Incompletion", "Passing Touchdown", "Sack",
                        "Pass Interception Return", "Pass Interception", "Interception", "Interception Return Touchdown")
r15_passer <- function(text) {
  text <- ifelse(is.na(text), "", text)
  crew <- regmatches(text, regexec("#([0-9]+) ([A-Z][-A-Za-z.' ]*?) (?:pass |sacked)", text, perl = TRUE))
  old <- regmatches(text, regexec("^([A-Z][-A-Za-z.' ]*?) (?:pass |sacked)", text, perl = TRUE))
  out <- rep(NA_character_, length(text))
  k <- lengths(crew) > 0; out[k] <- vapply(crew[k], function(z) paste0("#", z[2], " ", trimws(z[3])), "")
  j <- !k & lengths(old) > 0; out[j] <- vapply(old[j], function(z) trimws(z[2]), "")
  out
}
