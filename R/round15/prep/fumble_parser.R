# Round 15 P2: fumble-play parser = Round 8 parser (Round 13 vocab "r8"), plus rules for the 2025+ stat-crew text format
# ("#9 R.Johnson rush right for 38 yards gain to the FIU09 fumbled by ..."). The added rules run only for seasons >= 2025,
# so every earlier classification is unchanged by construction (P2 pass rule, predeclaration §4.3).
r15_parse_fumble_text <- function(text, season, r13env) {
  base <- r13env$r13_parse_fumble_text(text, "r8")
  new <- season >= 2025 & is.na(base$type)
  if (!any(new)) return(base)
  pre <- sub("(?i)fumbled.*$", "", ifelse(is.na(text[new]), "", text[new]), perl = TRUE)
  m <- regmatches(pre, regexec("(?i)\\brush(?: (?:left|right|middle|up the middle))? for (?:([0-9]+) yards? (gain|loss)|(0) yards|no gain)", pre, perl = TRUE))
  hit <- lengths(m) > 0
  n <- vapply(m, function(z) if (length(z) && nzchar(z[2])) as.numeric(z[2]) else 0, numeric(1))
  sgn <- vapply(m, function(z) if (length(z) && tolower(z[3]) == "loss") -1 else 1, numeric(1))
  base$type[new][hit] <- "Rush"; base$gained[new][hit] <- (sgn * n)[hit]
  base
}
