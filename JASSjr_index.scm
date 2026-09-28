#!/usr/bin/env -S csi -r7rs-syntax -s

; JASSJR_INDEX.SCM
; ----------------
; Copyright (c) 2026 Vaughan Kitchen
; Minimalistic BM25 search engine.

; Requires installing the srfi-69 egg with
; chicken-install srfi-69

(import
  (scheme base)
  srfi-69
  (chicken bitwise)
  (chicken file posix)
  (chicken io)
  (chicken irregex)
  (chicken number-vector)
  (chicken process-context))

(define vocab (make-hash-table equal?)) ; the in-memory index
(define doc-ids '()) ; the primary keys
(define doc-lengths '()) ; hold the length of each document

(define docid -1)
(define document-length 0)
(define push-next #f) ; is the next token the primary key?

(define (string-downcase s)
  (list->string
    (map char-downcase (string->list s))))

(define (index tokens)
  (unless (null? tokens)
    (let ((token (car tokens)))
      ; If we see a <DOC> tag then we're at the start of the next document
      (if (string=? token "<DOC>")
        (begin
          ; Save the previous document length
          (if (not (= docid -1))
            (set! doc-lengths (cons document-length doc-lengths)))

          ; Move on to the next document
          (set! docid (+ docid 1))
          (set! document-length 0)

          (if (= (modulo docid 1000) 0)
            (print docid " documents indexed"))))

      ; if the last token we saw was a <DOCNO> then the next token is the primary key
      (if push-next
        (begin
          (set! doc-ids (cons token doc-ids))
          (set! push-next #f)))
      (if (string=? token "<DOCNO>") (set! push-next #t))

      ; Don't index XML tags
      (if (not (char=? (string-ref token 0) #\<))
        (let* (
          ; lower case the string
          (lowercase (string-downcase token))

          ; truncate any long tokens at 255 charactes (so that the length can be stored first and in a single byte)
          (lowercase (substring lowercase 0 (min 255 (string-length lowercase)))))

          ; add the posting to the in-memory index
          (let ((postings (hash-table-ref/default vocab lowercase #f)))
            (cond
              ; if the term isn't in the vocab yet
              ((not postings)
               (hash-table-set! vocab lowercase
                  (list 1 docid)))

              ; if the docno for this occurence has changed then create a new <d,tf> pair
              ((not (= (cadr postings) docid))
                (hash-table-set! vocab lowercase
                  (cons 1 (cons docid postings))))

              ; else increase the tf
              (else
                (set-car! postings
                  (+ (car postings) 1)))))

          ; Compute the document length
          (set! document-length (+ document-length 1))))

      (index (cdr tokens)))))

(define (tokenise file)
  (let loop ((line (read-line file)))
    (if (eof-object? line)
      (close-input-port file)
      (begin
        (index (irregex-extract "[a-zA-Z0-9][a-zA-Z0-9-]*|<[^>]*>" line))
        (loop (read-line file))))))

(define (write-u32 n port)
  (write-u8 (bitwise-and n #xff) port)
  (write-u8 (bitwise-and (arithmetic-shift n -8) #xff) port)
  (write-u8 (bitwise-and (arithmetic-shift n -16) #xff) port)
  (write-u8 (bitwise-and (arithmetic-shift n -24) #xff) port))

(define (main args)
  ; Make sure we have one parameter, the filename
  (if (null? args)
    (display (string-append "Usage: " (program-name) " <infile.xml>\n"))
    (begin
      ; open the file to index
      (tokenise (open-input-file (car args)))

      ; If we didn't index any documents then we're done.
      (if (= docid -1) (exit))

      ; Save the final document length
      (set! doc-lengths (cons document-length doc-lengths))

      ; tell the user we've got to the end of parsing
      (print "Indexed " (+ docid 1) " documents. Serialising...")

      ; store the primary keys
      (with-output-to-file "docids.bin"
        (lambda ()
          (for-each print (reverse doc-ids))))

      ; serialise the in-memory index to disk
      (call-with-port
        (open-output-file "postings.bin")
        (lambda (postings-port)
          (call-with-port
            (open-output-file "vocab.bin")
            (lambda (vocab-port)
              (hash-table-for-each vocab
                (lambda (token postings)
                  (let* ((where (file-position postings-port))
                         (vec (list->u32vector (reverse postings)))
                         (bv (u32vector->bytevector/shared vec))
                         (size (bytevector-length bv)))
                    ; write the postings list to one file
                    (write-bytevector bv postings-port)

                    ; write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
                    (write-u8 (string-length token) vocab-port)
                    (write-string token vocab-port)
                    (write-u8 0 vocab-port)
                    (write-u32 where vocab-port)
                    (write-u32 size vocab-port))))))))

      ; store the document lengths
      (call-with-port (open-output-file "lengths.bin")
        (lambda (port)
          (write-bytevector (u32vector->bytevector/shared (list->u32vector (reverse doc-lengths))) port)))
    )))

(main (command-line-arguments))
