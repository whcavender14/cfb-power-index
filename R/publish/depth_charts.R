# =============================================================================
# R/publish/depth_charts.R — team depth charts from TWO·DEEP (thetwodeep.com), used with permission (2026-09-26).
#
# Display only: nothing here feeds the model. One page per FBS team (https://www.thetwodeep.com/college/<slug>),
# fetched politely (one request at a time, a pause between them), parsed to rows of
#   group (QB, RB, WR, TE, OL, DL, EDGE, LB, CB, S, special teams), slot (the team's own name: LT, JACK, NB, BS ...),
#   and the first two players listed (name, jersey, 2026 snap share when TWO·DEEP shows one).
# Saved to output/state/depth_charts_<season>.rds with the fetch time. A team whose page fails or parses to nothing is
# left out (the site then falls back to its usage-based chart); nothing is invented.
# =============================================================================
TWODEEP_BASE <- "https://www.thetwodeep.com/college/"
TWODEEP_SLUG <- c("texas-a-and-m" = "texas-am")   # our slug -> TWO·DEEP slug, where they differ

twodeep_text <- function(x) {
  x <- gsub("<!-- -->", "", x, fixed = TRUE)
  x <- gsub("&#x27;", "'", x, fixed = TRUE); x <- gsub("&amp;", "&", x, fixed = TRUE)
  x <- gsub("&quot;", "\"", x, fixed = TRUE); x <- gsub("&#39;", "'", x, fixed = TRUE)
  trimws(x)
}
twodeep_first <- function(pattern, x) { m <- regmatches(x, regexec(pattern, x, perl = TRUE))[[1]]; if (length(m) >= 2) m[2] else NA_character_ }

parse_twodeep <- function(page) {
  starts <- gregexpr('<div style="display:grid;grid-template-columns:68px', page, fixed = TRUE)[[1]]
  if (starts[1] < 0) return(NULL)
  ends <- c(starts[-1] - 1L, nchar(page))
  rows <- list(); seen <- character()
  for (i in seq_along(starts)) {
    row <- substr(page, starts[i], ends[i])
    group <- twodeep_first("font-weight:800;font-size:17px[^>]*>([^<]+)<", row)
    if (is.na(group)) next
    slot <- twodeep_first("font-size:8px;font-weight:700;letter-spacing:0.05em;color:#957a3c\">([^<]+)<", row)
    group <- twodeep_text(group); slot <- if (is.na(slot)) group else twodeep_text(slot)
    key <- paste(group, slot)
    if (key %in% seen) next                                  # the page repeats the chart for its mobile layout
    links <- regmatches(row, gregexpr('<a class="td-plink".*?</a>', row, perl = TRUE))[[1]]
    players <- list()
    for (a in links) {                                        # depth order: codes <slot>1, <slot>2, ...; stop at the first break
      code <- twodeep_first('color:#98948a;flex:none">([^<]+)<', a)
      want <- paste0(slot, length(players) + 1L)
      if (is.na(code) || twodeep_text(code) != want) break
      name <- twodeep_first('class="td-pname"[^>]*>([^<]+)<', a)
      if (is.na(name)) break
      players[[length(players) + 1L]] <- list(name = twodeep_text(name),
        jersey = suppressWarnings(as.integer(twodeep_first('font-size:17px;background:[^"]*">(\\d+)<', a))),
        snaps = suppressWarnings(as.integer(twodeep_first("(\\d+)% snaps", a))))
    }
    if (!length(players)) next
    seen <- c(seen, key)
    rows[[length(rows) + 1L]] <- list(group = group, slot = slot, players = players)
  }
  if (length(rows)) rows else NULL
}

pull_depth_charts <- function(slugs, pause = 1.5) {
  out <- list()
  for (i in seq_along(slugs)) {
    s <- slugs[i]
    if (i == 11L && !length(out)) { message("Depth charts: the first 10 teams all failed; giving up (site down or changed)."); break }
    url <- paste0(TWODEEP_BASE, if (s %in% names(TWODEEP_SLUG)) TWODEEP_SLUG[[s]] else s)
    page <- tryCatch({
      req <- httr2::request(url) |> httr2::req_user_agent("CFPi+ site export (with TWO-DEEP's permission)") |>
        httr2::req_timeout(30) |> httr2::req_retry(max_tries = 2)
      httr2::resp_body_string(httr2::req_perform(req))
    }, error = function(e) { message("Depth chart ", s, ": ", conditionMessage(e)); NULL })
    if (!is.null(page)) { rows <- parse_twodeep(page); if (!is.null(rows)) out[[s]] <- rows else message("Depth chart ", s, ": nothing parsed.") }
    Sys.sleep(pause)
  }
  attr(out, "fetched_at") <- Sys.time()
  out
}

# Adds height and headshot from the CFBD roster (matched on jersey and last name; unmatched players keep name/jersey only)
# and drops special-teams rows. rows: parse_twodeep() output for one team; roster: that team's CFBD roster rows.
DEPTH_UNITS <- list(offense = c("QB", "RB", "FB", "WR", "TE", "OL", "SB"), defense = c("DL", "EDGE", "LB", "CB", "S"))
depth_unit <- function(group) {
  g <- sub("-.*$", "", toupper(group))
  if (g %in% DEPTH_UNITS$offense) "offense" else if (g %in% DEPTH_UNITS$defense) "defense" else NA_character_
}
enrich_depth <- function(rows, roster) {
  lastword <- function(x) vapply(strsplit(trimws(x), "\\s+"), function(w) { w <- w[!tolower(w) %in% c("jr", "jr.", "sr", "sr.", "ii", "iii", "iv", "v")]; if (length(w)) tail(w, 1) else "" }, "")
  out <- list()
  for (r in rows) {
    unit <- depth_unit(r$group); if (is.na(unit)) next
    r$unit <- unit
    r$players <- lapply(r$players, function(p) {
      k <- NA_integer_
      if (!is.null(roster) && nrow(roster) && !is.na(p$jersey)) {
        cand <- which(suppressWarnings(as.integer(roster$jersey)) == p$jersey)
        if (length(cand)) {
          hit <- cand[tolower(gsub("[^A-Za-z]", "", lastword(roster$last_name[cand]))) == tolower(gsub("[^A-Za-z]", "", lastword(p$name)))]
          if (length(hit)) k <- hit[1]
        }
      }
      p$height <- if (!is.na(k)) suppressWarnings(as.integer(roster$height[k])) else NA_integer_
      p$headshot <- if (!is.na(k) && "headshot_url" %in% names(roster)) roster$headshot_url[k] else NA_character_
      p
    })
    out[[length(out) + 1L]] <- r
  }
  out
}

# Long format for the weekly input file: one row per team, spot and depth. Keyed by season, week and team_id.
depth_long <- function(dc, teams, season, week) {
  id <- setNames(as.character(teams$team_id), teams$slug)
  out <- lapply(names(dc), function(slug) {
    rows <- dc[[slug]]
    do.call(rbind, lapply(seq_along(rows), function(i) {
      r <- rows[[i]]
      data.frame(season = as.integer(season), week = as.integer(week), team_id = unname(id[slug]), slug = slug,
                 order = i, unit = depth_unit(r$group), group = r$group, slot = r$slot, depth = seq_along(r$players),
                 player = vapply(r$players, `[[`, "", "name"),
                 jersey = vapply(r$players, function(p) if (is.null(p$jersey)) NA_integer_ else as.integer(p$jersey), 0L),
                 snaps_pct = vapply(r$players, function(p) if (is.null(p$snaps)) NA_integer_ else as.integer(p$snaps), 0L),
                 stringsAsFactors = FALSE)
    }))
  })
  x <- do.call(rbind, out)
  x$fetched_at <- attr(dc, "fetched_at")
  x[!is.na(x$team_id), ]
}
# Latest week's chart for one team back to the nested rows the page uses (starter + first backup per spot).
depth_rows <- function(long, team_id, keep = 2L) {
  x <- long[long$team_id == team_id, , drop = FALSE]
  if (!nrow(x)) return(NULL)
  x <- x[x$week == max(x$week), , drop = FALSE]
  x <- x[order(x$order, x$depth), , drop = FALSE]
  lapply(split(x, x$order), function(r) list(group = r$group[1], slot = r$slot[1],
    players = lapply(seq_len(min(nrow(r), keep)), function(j) list(name = r$player[j], jersey = r$jersey[j], snaps = r$snaps_pct[j]))))
}
