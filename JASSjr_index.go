/*
	JASSjr_index.go
	---------------
	Copyright (c) 2024 Vaughan Kitchen
	Minimalistic BM25 search engine.
*/

package main

import (
	"bufio"
	"encoding/binary"
	"fmt"
	"os"
	"strings"
)

func check(e error) {
	if e != nil {
		panic(e)
	}
}

func isAlpha(c byte) bool {
	return ('A' <= c && c <= 'Z') || ('a' <= c && c <= 'z')
}

func isDigit(c byte) bool {
	return '0' <= c && c <= '9'
}

func isAlnum(c byte) bool {
	return isAlpha(c) || isDigit(c)
}

/*
Struct posting
--------------
*/
type posting struct {
	d, tf int32
}

/*
Struct lexer
------------
*/
type lexer struct {
	buffer  []byte
	current int
}

/*
lexer.getNext()
------------
One-character lookahead lexical analyser
*/
func (l *lexer) getNext() *string {
	/*
		Skip over whitespace and punctuation (but not XML tags)
	*/
	for l.current < len(l.buffer) && !isAlnum(l.buffer[l.current]) && l.buffer[l.current] != '<' {
		l.current++
	}

	/*
		A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
	*/
	start := l.current
	if l.current >= len(l.buffer) {
		return nil
	} else if isAlnum(l.buffer[l.current]) {
		for l.current < len(l.buffer) && (isAlnum(l.buffer[l.current]) || l.buffer[l.current] == '-') {
			l.current++
		}
	} else if l.buffer[l.current] == '<' {
		for l.current++; l.current < len(l.buffer) && l.buffer[l.current-1] != '>'; l.current++ {
			/* do nothing */
		}
	}
	/*
		Copy and return the token
	*/
	result := string(l.buffer[start:l.current])
	return &result
}

/*
main()
------
Simple indexer for TREC WSJ collection
*/
func main() {
	vocab := make(map[string][]posting)
	docIds := make([]string, 0)
	lengthVector := make([]int32, 0)

	var docId int32 = -1
	var documentLength int32 = 0

	/*
		Make sure we have one parameter, the filename
	*/
	if len(os.Args) != 2 {
		fmt.Println("Usage: ", os.Args[0], " <infile.xml>")
		os.Exit(0)
	}

	fh, err := os.Open(os.Args[1])
	check(err)
	defer fh.Close()

	scanner := bufio.NewScanner(fh)
	pushNext := false
	for scanner.Scan() {
		lex := lexer{scanner.Bytes(), 0}
		for token := lex.getNext(); token != nil; token = lex.getNext() {
			token := *token
			if token == "<DOC>" {
				/*
					Save the previous document length
				*/
				if docId != -1 {
					lengthVector = append(lengthVector, documentLength)
				}

				/*
					Move on to the next document
				*/
				docId++
				documentLength = 0

				if docId%1000 == 0 {
					fmt.Println(docId, "documents indexed")
				}
			}

			/*
				if the last token we saw was a <DOCNO> then the next token is the primary key
			*/
			if pushNext {
				docIds = append(docIds, token)
				pushNext = false
			}
			if token == "<DOCNO>" {
				pushNext = true
			}

			/*
				Don't index XML tags
			*/
			if strings.HasPrefix(token, "<") {
				continue
			}

			/*
				lower case the string
			*/
			token = strings.ToLower(token)

			/*
				truncate any long tokens at 255 charactes (so that the length can be stored first and in a single byte)
			*/
			if len(token) > 0xFF {
				token = token[:0xFF+1]
			}

			/*
				add the posting to the in-memory index
			*/
			list, ok := vocab[token]
			if !ok {
				newList := make([]posting, 0)
				newList = append(newList, posting{docId, 1})
				vocab[token] = newList // if the term isn't in the vocab yet
			} else if list[len(list)-1].d != docId {
				vocab[token] = append(list, posting{docId, 1}) // if the docno for this occurence has changed then create a new <d,tf> pair
			} else {
				list[len(list)-1].tf++ // else increase the tf
			}

			/*
				compute the document length
			*/
			documentLength++
		}
	}
	check(scanner.Err())

	/*
		Save the final document length
	*/
	lengthVector = append(lengthVector, documentLength)

	/*
		tell the user we've got to the end of parsing
	*/
	fmt.Println("Indexed", docId+1, "documents. Serialing...")

	/*
		store the primary keys
	*/
	docIdFile, err := os.Create("docids.bin")
	check(err)
	defer docIdFile.Close()
	docIdWriter := bufio.NewWriter(docIdFile)
	defer docIdWriter.Flush()
	for _, primaryKey := range docIds {
		docIdWriter.WriteString(primaryKey + "\n")
	}

	/*
		serialise the in-memory index to disk
	*/
	postingsFile, err := os.Create("postings.bin")
	check(err)
	defer postingsFile.Close()
	postingsWriter := bufio.NewWriter(postingsFile)
	defer postingsWriter.Flush()
	vocabFile, err := os.Create("vocab.bin")
	check(err)
	defer vocabFile.Close()
	vocabWriter := bufio.NewWriter(vocabFile)
	defer vocabWriter.Flush()

	var where uint32 = 0
	byteBuffer := make([]byte, 4)
	for term, postings := range vocab {
		/*
			write the postings list to one file
		*/
		err = binary.Write(postingsWriter, binary.NativeEndian, postings)
		check(err)

		/*
			write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
		*/
		err = vocabWriter.WriteByte(byte(len(term)))
		check(err)
		_, err = vocabWriter.WriteString(term)
		check(err)
		err = vocabWriter.WriteByte(0)
		check(err)
		binary.NativeEndian.PutUint32(byteBuffer, where)
		_, err = vocabWriter.Write(byteBuffer)
		check(err)
		binary.NativeEndian.PutUint32(byteBuffer, uint32(len(postings)*8))
		_, err = vocabWriter.Write(byteBuffer)
		check(err)

		where += uint32(len(postings) * 8)
	}

	/*
		store the document lengths
	*/
	docLengthsFile, err := os.Create("lengths.bin")
	check(err)
	defer docLengthsFile.Close()
	docLengthsWriter := bufio.NewWriter(docLengthsFile)
	defer docLengthsWriter.Flush()
	err = binary.Write(docLengthsWriter, binary.NativeEndian, lengthVector)
	check(err)
}
