#!/usr/bin/env -S sbcl --script

;;;; JASSJR_SEARCH.LISP
;;;; ------------------
;;;; Copyright (c) 2026 Vaughan Kitchen
;;;; Minimalistic BM25 search engine.

(require :asdf)
(require :sb-posix)

(defconstant +k1+ 0.9d0) ; BM25 k1 parameter
(defconstant +b+ 0.4d0) ; BM25 b parameter

;;; File helpers
(defun read-binary-file (pathname)
  (with-open-file (stream pathname :direction :input
                                  :element-type '(unsigned-byte 8))
    (let ((data (make-array (file-length stream)
                            :element-type '(unsigned-byte 8))))
      (read-sequence data stream)
      data)))

(defun read-u32-le (data offset)
  (logior
   (aref data offset)
   (ash (aref data (+ offset 1)) 8)
   (ash (aref data (+ offset 2)) 16)
   (ash (aref data (+ offset 3)) 24)))

(defun read-u32-vector (pathname)
  (let* ((bytes (read-binary-file pathname))
         (length (/ (length bytes) 4))
         (result (make-array length
                             :element-type '(unsigned-byte 32))))
    (dotimes (i length result)
      (setf (aref result i)
            (read-u32-le bytes (* i 4))))))

(defun read-u32-vector-from-stream (stream byte-count)
  (let* ((count (/ byte-count 4))
         (bytes (make-array byte-count
                            :element-type '(unsigned-byte 8)))
         (result (make-array count
                             :element-type '(unsigned-byte 32))))
    (unless (= (read-sequence bytes stream) byte-count)
      (error "Unexpected EOF reading postings"))
    (dotimes (i count result)
      (setf (aref result i)
            (read-u32-le bytes (* i 4))))))

;;; Read the document lengths
(defparameter *doc-lengths*
  (read-u32-vector "lengths.bin"))

;;; Compute the average document length for BM25
(defparameter *average-doc-length*
  (/ (reduce #'+ *doc-lengths*) (length *doc-lengths*)))

;;; Read the primary_keys
(defparameter *doc-ids*
  (with-open-file (stream "docids.bin")
    (coerce
     (loop for line = (read-line stream nil nil)
           while line
           collect line)
     'vector)))

;;; Open the postings list file
(defparameter *postings-file*
  (open "postings.bin"
        :direction :input
        :element-type '(unsigned-byte 8)))

;;; Build the vocabulary in memory
(defun read-vocabulary (pathname)
  (let ((data (read-binary-file pathname))
        (vocab (make-hash-table :test #'equal)))
    (loop with current = 0
          while (< current (length data))
          do
             (let* ((string-length (aref data current))
                    (term-start (+ current 1))
                    (where (read-u32-le
                            data
                            (+ current string-length 2)))
                    (size (read-u32-le
                           data
                           (+ current string-length 6)))
                    (term (sb-ext:octets-to-string
                           data
                           :start term-start
                           :end (+ term-start string-length)
                           :external-format :utf-8)))
               (setf (gethash term vocab)
                     (cons where size))
               (incf current (+ string-length 10))))
    vocab))

(defparameter *vocab*
  (read-vocabulary "vocab.bin"))

;;; Array of rsv values
(defparameter *rsv*
  (make-array (length *doc-ids*)
              :initial-element 0d0))

;;; Set up the rsv pointers
(defparameter *rsv-pointers*
  (make-array (length *doc-ids*)
              :initial-contents
              (loop for i below (length *doc-ids*)
                    collect i)))

(defun process-term (token)
  (multiple-value-bind (term-details found)
      (gethash token *vocab*)
    ;; Does the term exist in the collection?
    (when found
      (let* ((where (car term-details))
             (size (cdr term-details))
	     ;; Compute the IDF component of BM25 as log(N/n)
             (idf (log (/ (length *doc-ids*)
                          (/ size 8d0)))))

        ;; Seek and read the postings list
        (file-position *postings-file* where)

        (let ((postings
                (read-u32-vector-from-stream
                 *postings-file* size)))

          ;; Process the postings list by simply adding the BM25 component for this document into the accumulators array
          (loop for i from 0 below (length postings) by 2
                for d = (aref postings i)
                for tf = (aref postings (1+ i))
                do
                  (let* ((doc-length (aref *doc-lengths* d))
                         (normalization
                           (+ tf
                              (* +k1+
                                 (+ (- 1d0 +b+)
                                    (* +b+
                                       (/ doc-length
                                          *average-doc-length*))))))
                         (score
                           (/ (* idf tf (+ +k1+ 1d0))
                              normalization)))
                    (incf (aref *rsv* d) score))))))))

;;; Sort the results list
(defun sort-results ()
  (sort *rsv-pointers*
        (lambda (ap bp)
          (let ((a (aref *rsv* ap))
                (b (aref *rsv* bp)))
            (if (= a b)
                (> ap bp)
                (> a b))))))

(defun search-query (line)
  ;; Zero the accumulator array.
  (fill *rsv* 0d0)

  ;; If the first token is a number then assume a TREC query number, and skip it
  (let* ((tokens (uiop:split-string line))
         (first-token (first tokens))
         (query-number
           (and first-token
                (ignore-errors
                  (parse-integer first-token :junk-allowed nil))))
         (query-id (or query-number 0))
         (tokens (if query-number
                     (rest tokens)
                     tokens)))

    ;; Process query terms
    (dolist (token tokens)
      (process-term token))

    ;; Sort the results list
    (sort-results)

    ;; Print the (at most) top 1000 documents in the results list in TREC eval format which is:
    ;; query-id Q0 document-id rank score run-name
    (loop for position across *rsv-pointers*
          for rank from 1
          for score = (aref *rsv* position)
          while (and (< (1- rank) 1000)
                     (/= score 0d0))
          do
             (format t "~A Q0 ~A ~D ~,4F JASSjr~%"
                     query-id
                     (aref *doc-ids* position)
                     rank
                     score))))

;;; Search (one query per line)
(loop for line = (read-line *standard-input* nil nil)
      while line
      do (search-query (string-trim '(#\Space #\Tab #\Return #\Linefeed) line)))

(close *postings-file*)
