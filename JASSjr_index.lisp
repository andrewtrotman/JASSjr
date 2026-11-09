#!/usr/bin/env -S sbcl --dynamic-space-size 4Gb --script

;;;; JASSJR_INDEX.LISP
;;;; -----------------
;;;; Copyright (c) 2026 Vaughan Kitchen
;;;; Minimalistic BM25 search engine.

(require :asdf)

(defparameter *vocab* (make-hash-table :test #'equal)) ; the in-memory index
(defparameter *doc-ids* '()) ; the primary keys
(defparameter *doc-lengths* '()) ; hold the length of each document

(defparameter *docid* -1)
(defparameter *document-length* 0)
(defparameter *push-next* nil)

;;; One-character lookahead lexical analyser
(defstruct lexer
  stream
  (next-char nil)
  (initialized nil))

(defun lexer-peek (lexer)
  (unless (lexer-initialized lexer)
    (setf (lexer-next-char lexer)
          (read-char (lexer-stream lexer) nil :eof)
          (lexer-initialized lexer) t))
  (lexer-next-char lexer))

(defun lexer-read (lexer)
  (let ((char (lexer-peek lexer)))
    (setf (lexer-initialized lexer) nil)
    char))

(defun lexer-next-token (lexer)
  ;; Skip over whitespace and punctuation (but not XML tags)
  (loop for char = (lexer-peek lexer)
        do
          (cond
            ((eq char :eof)
             (return-from lexer-next-token nil))

            ((char= char #\<)
             (return))

            ((alphanumericp char)
             (return))

            (t
             (lexer-read lexer))))

  ;; A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
  (when (char= (lexer-peek lexer) #\<)
    (let ((token (make-string-output-stream)))
      (write-char (lexer-read lexer) token)

      (loop for char = (lexer-read lexer)
            do
              (when (eq char :eof)
                (return))

              (write-char char token)

              (when (char= char #\>)
                (return)))

      (return-from lexer-next-token
        (get-output-stream-string token))))

  ;; TREC <DOCNO> primary keys have a hyphen in them
  (let ((token (make-string-output-stream)))
    (loop for char = (lexer-peek lexer)
          while (or (alphanumericp char)
                    (and (characterp char)
                         (char= char #\-)))
          do
            (write-char (lexer-read lexer) token))

    (get-output-stream-string token)))

;;; Index tokens
(defun index-token (token)
  ;; If we see a <DOC> tag then we're at the start of the next document.
  (when (string= token "<DOC>")
    ;; Save the previous document length.
    (unless (= *docid* -1)
      (push *document-length* *doc-lengths*))

    ;; Move on to the next document.
    (incf *docid*)
    (setf *document-length* 0)

    (when (zerop (mod *docid* 1000))
      (format t "~D documents indexed~%" *docid*)))

  ;; If the last token was a <DOCNO> then the next token is the primary key.
  (when *push-next*
    (push token *doc-ids*)
    (setf *push-next* nil))

  (when (string= token "<DOCNO>")
    (setf *push-next* t))

  ;; Don't index XML tags.
  (unless (char= (char token 0) #\<)
    ;; Lower case the string
    (let* ((lowercase (string-downcase token))
           ;; Truncate any long tokens at 255 charactes (so that the length can be stored first and in a single byte)
           (lowercase (subseq lowercase 0
                              (min 255 (length lowercase))))
           (postings (gethash lowercase *vocab*)))

      ;; Add the posting to the in-memory index.
      (cond
        ;; If the term isn't in the vocab yet
        ((null postings)
         (setf (gethash lowercase *vocab*)
               (list 1 *docid*)))

        ;; If the docno for this occurence has changed then create a new <d,tf> pair
        ((/= (cadr postings) *docid*)
         (setf (gethash lowercase *vocab*)
               (cons 1 (cons *docid* postings))))

        ;; Else increase the tf
        (t
         (incf (car postings))))

      ;; Compute the document length.
      (incf *document-length*))))

;;; Tokenize input
(defun tokenise-file (pathname)
  (with-open-file (stream pathname
                          :direction :input
                          :external-format :utf-8)
    (let ((lexer (make-lexer :stream stream)))
      (loop for token = (lexer-next-token lexer)
            while token
            do (index-token token)))))

(defun write-u8 (n stream)
  (write-byte (logand n #xff) stream))

(defun write-u32 (n stream)
  (write-u8 n stream)
  (write-u8 (ash n -8) stream)
  (write-u8 (ash n -16) stream)
  (write-u8 (ash n -24) stream))

(defun write-utf8-string (string stream)
  (let ((octets (sb-ext:string-to-octets
                 string
                 :external-format :utf-8)))
    (write-sequence octets stream)))

(defun write-u32-list (numbers stream)
  (dolist (n numbers)
    (write-u32 n stream)))

;;; Store the primary keys
(defun write-doc-ids ()
  (with-open-file (stream "docids.bin"
                          :direction :output
                          :external-format :utf-8
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (dolist (doc-id (reverse *doc-ids*))
      (write-line doc-id stream))))

;;; Serialise the in-memory index to disk
(defun write-index ()
  (with-open-file (postings-stream "postings.bin"
                                   :direction :output
                                   :element-type '(unsigned-byte 8)
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
    (with-open-file (vocab-stream "vocab.bin"
                                 :direction :output
                                 :element-type '(unsigned-byte 8)
                                 :if-exists :supersede
                                 :if-does-not-exist :create)

      (maphash
       (lambda (token postings)
         (let* ((where (file-position postings-stream))
                (ordered (reverse postings))
                (size (* 4 (length ordered))))

           ;; Write the postings list to one file
           (write-u32-list ordered postings-stream)

           ;; Write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
           (write-u8 (length token) vocab-stream)
           (write-utf8-string token vocab-stream)
           (write-u8 0 vocab-stream)
           (write-u32 where vocab-stream)
           (write-u32 size vocab-stream)))

       *vocab*))))

;;; Store the document lengths
(defun write-doc-lengths ()
  (with-open-file (stream "lengths.bin"
                          :direction :output
                          :element-type '(unsigned-byte 8)
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-u32-list (reverse *doc-lengths*) stream)))

;;; Simple indexer for TREC WSJ collection
(defun main (args)
  ;; Make sure we have one parameter, the filename.
  (if (null args)
      (format t "Usage: ./JASSjr_index.lisp <infile.xml>~%")

      (progn
        ;; Open the file to index
        (tokenise-file (first args))

        ;; If we didn't index any documents then we're done.
        (when (= *docid* -1)
          (return-from main nil))

        ;; Save the final document length.
        (push *document-length* *doc-lengths*)

        ;; Tell the user we've got to the end of parsing
        (format t "Indexed ~D documents. Serialising...~%"
                (1+ *docid*))

        ;; Serialize the index.
        (write-doc-ids)
        (write-index)
        (write-doc-lengths))))

(main (uiop:command-line-arguments))
