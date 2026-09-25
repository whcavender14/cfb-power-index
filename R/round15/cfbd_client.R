# Budget-guarded, caching CFBD GET client (read-only). The key comes from CFBD_API_KEY and is never printed or stored.
# A cached response is returned without a call; a new response is written once and never overwritten.
suppressPackageStartupMessages({ library(httr2); library(jsonlite); library(data.table) })

cfbd_client <- function(cache_dir, max_calls = 50L, floor = 300L) {
  key <- Sys.getenv("CFBD_API_KEY"); if (!nzchar(key)) stop("CFBD_API_KEY is not set", call. = FALSE)
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  st <- new.env(); st$calls <- 0L; st$log <- list()
  get <- function(path, query = list(), tag = NULL, refresh = FALSE) {
    if (is.null(tag)) tag <- paste(c(gsub("/", "_", sub("^/", "", path)), unlist(Map(paste0, names(query), query))), collapse = "_")
    f <- file.path(cache_dir, paste0(tag, ".rds"))
    if (file.exists(f) && !refresh) return(readRDS(f))
    if (st$calls >= max_calls) stop("CFBD call budget for this run reached (", max_calls, ")", call. = FALSE)
    resp <- request("https://api.collegefootballdata.com") |> req_url_path_append(path) |> req_url_query(!!!query) |>
      req_headers(Authorization = paste("Bearer", key), Accept = "application/json") |> req_retry(max_tries = 3) |>
      req_error(is_error = function(r) FALSE) |> req_perform()
    st$calls <- st$calls + 1L; Sys.sleep(1)
    rem <- suppressWarnings(as.integer(resp_header(resp, "X-CallLimit-Remaining")))
    st$log[[length(st$log) + 1]] <- data.table(tag, status = resp_status(resp), remaining_after = rem,
                                               retrieved_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
    if (resp_status(resp) != 200) stop("CFBD ", path, " returned HTTP ", resp_status(resp), call. = FALSE)
    x <- fromJSON(resp_body_string(resp), simplifyVector = TRUE, flatten = TRUE)
    if (file.exists(f)) { g <- sub("\\.rds$", sprintf("_%s.rds", format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")), f); saveRDS(x, g) } else saveRDS(x, f)
    if (is.finite(rem) && rem < floor) stop("CFBD account calls below floor (", rem, ")", call. = FALSE)
    x
  }
  list(get = get, calls = function() st$calls, log = function() rbindlist(st$log, fill = TRUE))
}
