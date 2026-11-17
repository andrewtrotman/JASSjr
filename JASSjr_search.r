#!/usr/bin/env Rscript

# JASSjr_search.r
# Copyright (c) 2026 Vaughan Kitchen
# Minimalistic BM25 search engine.

options(warn = 1)

K1 <- 0.9 # BM25 k1 parameter
B <- 0.4 # BM25 b parameter

# decode the vocabulary (one byte length, string, '\0', 4 byte where, 4 byte size)
load_vocab <- function(path) {
    vocab <- new.env(hash = TRUE, parent = emptyenv())

    con <- file(path, open = "rb")
    on.exit(close(con))

    while (TRUE) {
        length_byte <- readBin(con, "raw", n = 1L)

        if (length(length_byte) == 0L)
            break

        string_length <- as.integer(length_byte)

        string_raw <- readBin(con, "raw", n = string_length)

        string <- rawToChar(string_raw)
        Encoding(string) <- "UTF-8"

        # Consume the terminating NULL.
        readBin(con, "raw", n = 1L)

        where <- readBin(con, integer(), 1, size = 4)
        size  <- readBin(con, integer(), 1, size = 4)

        assign(string, c(where = where, size = size), envir = vocab)
    }

    vocab
}

# Read the primary_keys
doc_ids <- readLines("docids.bin", encoding = "UTF-8", warn = FALSE)

# Read the document lengths
doc_lengths <- readBin("lengths.bin", integer(), length(doc_ids), size = 4)

# Compute the average document length for BM25
average_length <- mean(doc_lengths)

# Build the vocabulary in memory
vocab <- load_vocab("vocab.bin")

# Open the postings list file
postings_con <- file("postings.bin", open = "rb")
on.exit(close(postings_con))

# Search (one query per line)
stdin_con <- file("stdin", open = "r")
on.exit(close(stdin_con), add = TRUE)

repeat {
    line <- readLines(stdin_con, n = 1L, warn = FALSE)

    if (length(line) == 0L)
        break

    # If the first token is a number then assume a TREC query number, and skip it
    terms <- strsplit(trimws(line), "\\s+")[[1]]
    query_id <- suppressWarnings(as.integer(terms[1]))

    if (!is.na(query_id)) {
        terms <- terms[-1]
    } else {
        query_id <- 0
    }

    scores <- numeric(length(doc_ids))

    for (term in terms) {
        # Does the term exist in the collection?
        if (!exists(term, envir = vocab, inherits = FALSE))
            next

        entry <- get(term, envir = vocab, inherits = FALSE)

        where <- entry["where"]
        size <- entry["size"]

        # Seek and read the postings list
        seek(postings_con, where, origin = "start")

        postings <- readBin(postings_con, integer(), size / 4, size = 4)

        # Compute the IDF component of BM25 as log(N/n).
        idf <- log(length(doc_ids) / (length(postings) / 2))

        # Process the postings list by simply adding the BM25 component for this document into the accumulators array
        postings <- matrix(postings, ncol = 2L, byrow = TRUE)

        docid <- postings[, 1L] + 1L
        tf <- postings[, 2L]

        lengths <- doc_lengths[docid]

        denominator <- tf + K1 * (
            1 - B + B * lengths / average_length
        )

        contribution <- idf * (
            tf * (K1 + 1) / denominator
        )

        scores[docid] <- scores[docid] + contribution
    }

    candidates <- which(scores > 0)

    # Sort the results list. Tie break on the document ID.
    ranking <- order(
        -scores[candidates],
        -candidates
    )

    candidates <- candidates[
        head(ranking, 1000L)
    ]

    # Print the (at most) top 1000 documents in the results list in TREC eval format which is:
    # query-id Q0 document-id rank score run-name
    output <- sprintf(
        "%s Q0 %s %d %.4f JASSjr",
        query_id,
        doc_ids[candidates],
        seq_len(length(candidates)),
        scores[candidates]
    )
    cat(paste(output, collapse = "\n"), "\n", sep = "")
}
