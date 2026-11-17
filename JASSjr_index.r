#!/usr/bin/env Rscript

# JASSjr_index.r
# Copyright (c) 2026 Vaughan Kitchen
# Minimalistic BM25 search engine.

# Make sure we have one paramter, the filename
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L)
    stop("Usage: ./JASSjr_index.r <infile.xml>", call. = FALSE)

vocab <- new.env(hash = TRUE, parent = emptyenv()) # the in-memory index
doc_ids <- character() # the primary keys
doc_lengths <- list() # hold the length of each document

# A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
# TREC <DOCNO> primary keys have a hyphen in them
lexer <- "[A-Za-z0-9][A-Za-z0-9-]*|<[^>]*>"
tokenize <- function(line) {
    matches <- gregexpr(lexer, line, perl = TRUE)
    regmatches(line, matches)[[1L]]
}

docid <- -1L
document_length <- 0L
push_next <- FALSE # is the next token the primary key?

con <- file(args[1L], open = "r")
on.exit(close(con))

repeat {
    line <- readLines(con, n = 1L, warn = FALSE)

    if (length(line) == 0L)
        break

    for (token in tokenize(line)) {
        # If we see a <DOC> tag then we're at the start of the next document
        if (token == "<DOC>") {
            # Save the previous document length
            if (docid != -1L)
                doc_lengths[[length(doc_lengths) + 1L]] <- document_length

            # Move on to the next document
            docid <- docid + 1L
            document_length <- 0L

            if (docid %% 1000L == 0L)
                cat(docid, "documents indexed\n")
        }

        # if the last token we saw was a <DOCNO> then the next token is the primary key
        if (push_next) {
            doc_ids <- c(doc_ids, token)
            push_next <- FALSE
        }

        if (token == "<DOCNO>")
            push_next <- TRUE

        # Don't index XML tags
        if (startsWith(token, "<"))
            next

        # Normalise and truncate the token (so that the length can be stored first and in a single byte)
        token <- substr(tolower(token), 1L, 255L)

        # add the posting to the in-memory index
        postings_list <- get0(token, envir = vocab, inherits = FALSE)

        if (is.null(postings_list)) {
            postings_list <- integer()
        }

        n <- length(postings_list)

        if (n == 0L || postings_list[n - 1L] != docid)
            # if the docno for this occurence has changed then create a new <d,tf> pair
            postings_list <- c(postings_list, docid, 1L)
        else
            # else increase the tf
            postings_list[n] <- postings_list[n] + 1L

        assign(token, postings_list, envir = vocab)

        # Compute the document length
        document_length <- document_length + 1L
    }
}

# If we didn't index any documents then we're done.
if (docid == -1L)
    quit(save = "no", status = 0L)

# Save the final document length
doc_lengths[[length(doc_lengths) + 1L]] <- document_length

# tell the user we've got to the end of parsing
cat("Indexed", docid + 1L, "documents. Serialising...\n")

# store the primary keys
writeLines(doc_ids, "docids.bin", useBytes = TRUE)

# serialise the in-memory index to disk
postings_con <- file("postings.bin", open = "wb")
vocab_con <- file("vocab.bin", open = "wb")

for (term in ls(vocab, all.names = TRUE)) {
    postings <- unlist(get(term, envir = vocab, inherits = FALSE), use.names = FALSE)

    # write the postings list to one file
    where <- seek(postings_con)
    writeBin(as.integer(unlist(postings, use.names = FALSE)), postings_con, size = 4L, endian = "little")

    # write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
    writeBin(as.raw(nchar(term)), vocab_con)
    writeBin(charToRaw(term), vocab_con)
    writeBin(as.raw(0L), vocab_con) # string is null terminated

    writeBin(as.integer(where), vocab_con, size = 4L, endian = "little")
    writeBin(as.integer(length(postings) * 4), vocab_con, size = 4L, endian = "little") # no. of bytes
}

close(postings_con)
close(vocab_con)

# store the document lengths
lengths_con <- file("lengths.bin", open = "wb")
writeBin(as.integer(unlist(doc_lengths, use.names = FALSE)), lengths_con, size = 4L, endian = "little")
close(lengths_con)
