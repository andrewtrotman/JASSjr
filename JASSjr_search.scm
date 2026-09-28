#!/usr/bin/env -S csi -r7rs-syntax -s

; JASSJR_SEARCH.SCM
; -----------------
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
  (chicken number-vector)
  (chicken sort)
  (chicken string))

(define k1 0.9) ; BM25 k1 parameter
(define b 0.4) ; BM25 b parameter

(define (bytevector-u32-ref bv i)
  (+ (bytevector-u8-ref bv i)
     (arithmetic-shift (bytevector-u8-ref bv (+ i 1)) 8)
     (arithmetic-shift (bytevector-u8-ref bv (+ i 2)) 16)
     (arithmetic-shift (bytevector-u8-ref bv (+ i 3)) 24)))

; basic implementation of srfi-133 vector-unfold
(define (vector-unfold f length)
  (let ((vec (make-vector length)))
    (vector-unfold! f vec 0 length)
    vec))

(define (vector-unfold! f vec start end)
  (let loop ((i start))
    (when (< i end)
      (vector-set! vec i (f i))
      (loop (+ i 1)))))

(define (for-each-pair f xs)
  (unless (null? xs)
    (f (car xs) (cadr xs))
    (for-each-pair f (cddr xs))))

(define (for-each-with-index f lst)
  (let loop ((lst lst) (index 1))
    (unless (null? lst)
      (f index (car lst))
      (loop (cdr lst) (+ index 1)))))

; stolen from https://wiki.call-cc.org/eggref/6/srfi-1
(define (take-while pred lis)
  (let recur ((lis lis))
    (if (null? lis) '()
	(let ((x (car lis)))
	  (if (pred x)
	      (cons x (recur (cdr lis)))
	      '())))))

(define (float->4dp x)
  (let* ((rounded (/ (round (* x 10000)) 10000))
         (s (number->string rounded))
         (dot (substring-index "." s)))
    (if dot
      (substring (string-append s "0000") 0 (+ dot 5))
      (string-append s ".0000"))))

; Read the document lengths
(define doc-lengths
  (call-with-input-file "lengths.bin"
    (lambda (port)
      (let ((bv (make-bytevector (file-size port))))
        (read-bytevector! bv port)
        (bytevector->u32vector/shared bv)))))

; Compute the average document length for BM25
(define average-doc-length
  (/ (foldl + 0 (u32vector->list doc-lengths)) (u32vector-length doc-lengths)))

; Read the primary_keys
(define doc-ids (list->vector (read-lines (open-input-file "docids.bin"))))

; Open the postings list file
(define postings-file (open-input-file "postings.bin"))

; Build the vocabulary in memory
(define vocab
  (call-with-input-file "vocab.bin"
    (lambda (port)
      (let ((vocab (make-hash-table))
            (bv (make-bytevector (file-size port))))
        (read-bytevector! bv port)
        (let loop ((current 0))
          (when (< current (bytevector-length bv))
            (let* ((string-length (bytevector-u8-ref bv current))
                   (term-start (+ current 1))
                   (where (bytevector-u32-ref bv (+ current string-length 2))) ; +1 for the length and + 1 for the '\0'
                   (size (bytevector-u32-ref bv (+ current string-length 2 4))) ; +1 for the length and + 1 for the '\0'
                   (term (utf8->string (bytevector-copy bv term-start (+ term-start string-length)))))
              (hash-table-set! vocab term (cons where size))
              (loop (+ current string-length 10)))))
        vocab))))

; Array of rsv values
(define rsv (make-vector (vector-length doc-ids)))

; Set up the rsv pointers
(define rsv-pointers (vector-unfold values (vector-length doc-ids)))

; Search (one query per line)
(let loop ((line (read-line)))
  (unless (eof-object? line)
    ; Zero the accumulator array.
    (vector-fill! rsv 0)
    ; If the first token is a number then assume a TREC query number, and skip it
    (let* ((tokens (string-split line))
           (n (string->number (car tokens)))
           (query-id (or n 0))
           (tokens (if n (cdr tokens) tokens)))
      (for-each
        (lambda (token)
          (let ((term-details (hash-table-ref/default vocab token #f)))
            ; Does the term exist in the collection?
            (when term-details
              ; Seek and read the postings list
              (set-file-position! postings-file (car term-details))
              ; Compute the IDF component of BM25 as log(N/n)
              (let ((idf (log (/ (vector-length doc-ids) (/ (cdr term-details) 8)))))
                ; Process the postings list by simply adding the BM25 component for this document into the accumulators array
                (for-each-pair
                  (lambda (d tf)
                    (vector-set! rsv d (+ (vector-ref rsv d) (/ (* idf tf (+ k1 1)) (+ tf (* k1 (+ (- 1 b) (* b (/ (u32vector-ref doc-lengths d) average-doc-length)))))))))
                  (u32vector->list (bytevector->u32vector/shared (read-bytevector (cdr term-details) postings-file))))))))
        tokens)
      ; Sort the results list
      (sort! rsv-pointers
        (lambda (ap bp)
          (let ((a (vector-ref rsv ap))
                (b (vector-ref rsv bp)))
            (if (> a b) #t (if (= a b) (> ap bp) #f)))))
      ; Print the (at most) top 1000 documents in the results list in TREC eval format which is:
      ; query-id Q0 document-id rank score run-name
      (for-each-with-index
        (lambda (idx p)
          (print query-id " Q0 " (vector-ref doc-ids p) " " idx " " (float->4dp (vector-ref rsv p)) " JASSjr"))
        (take-while (lambda (p) (not (zero? (vector-ref rsv p)))) (vector->list (vector-copy rsv-pointers 0 (min 1000 (vector-length rsv-pointers)))))))
    (loop (read-line))))
