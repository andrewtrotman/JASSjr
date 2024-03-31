/*
	JASSjr_search.go
	----------------
	Copyright (c) 2024 Vaughan Kitchen
	Minimalistic BM25 search engine.
*/

package main

import (
	"bufio"
	"bytes"
	"cmp"
	"encoding/binary"
	"fmt"
	"math"
	"os"
	"slices"
	"strconv"
	"strings"
)

/*
Constants
---------
*/
const k1 = 0.9 // BM25 k1 parameter
const b = 0.4  // BM25 b parameter

/*
Struct vocabEntry
-----------------
*/
type vocabEntry struct {
	where, size int32 // where on the disk and how large (in bytes) is the postings list?
}

func check(e error) {
	if e != nil {
		panic(e)
	}
}

/*
main()
------
Simple search engine ranking on BM25.
*/
func main() {
	/*
	  Read the document lengths
	*/
	lengthsAsBytes, err := os.ReadFile("lengths.bin")
	check(err)
	lengthVector := make([]int32, len(lengthsAsBytes)/4)
	err = binary.Read(bytes.NewReader(lengthsAsBytes), binary.NativeEndian, lengthVector)
	check(err)

	/*
	  Compute the average document length for BM25
	*/
	documentsInCollection := len(lengthVector)
	var averageDocumentLength float64 = 0
	for _, which := range lengthVector {
		averageDocumentLength += float64(which)
	}
	averageDocumentLength /= float64(documentsInCollection)

	/*
	  Read the primary keys
	*/
	primaryKeysAsBytes, err := os.ReadFile("docids.bin")
	check(err)
	// This isn't performant for large files. Prefer bufio.Scanner there
	// But for small files like what we have here it is faster
	primaryKeys := strings.Split(string(primaryKeysAsBytes), "\n")

	/*
	  Open the postings list file
	*/
	postingsFile, err := os.Open("postings.bin")
	check(err)

	/*
	  Build the vocabulary in memory
	*/
	dictionary := make(map[string]vocabEntry) // the vocab
	vocabAsBytes, err := os.ReadFile("vocab.bin")
	check(err)
	for offset := 0; offset < len(vocabAsBytes); {
		strLength := int(vocabAsBytes[offset])
		offset += 1

		term := string(vocabAsBytes[offset : offset+strLength])
		offset += strLength + 1 // read the '\0' string terminator

		where := binary.NativeEndian.Uint32(vocabAsBytes[offset:])
		offset += 4
		size := binary.NativeEndian.Uint32(vocabAsBytes[offset:])
		offset += 4

		// TODO pointer type?
		dictionary[term] = vocabEntry{int32(where), int32(size)}
	}

	/*
	  Allocate buffers
	*/
	rsv := make([]float64, documentsInCollection) // array of rsv values

	/*
	  Set up the rsv pointers
	*/
	rsvPointers := make([]int, documentsInCollection) // pointers to each member of rsv[] so that we can sort

	/*
	  Search (one query per line)
	*/
	stdin := bufio.NewScanner(os.Stdin)
	for stdin.Scan() {
		/*
		  Zero the accumulator array.
		*/
		for i := range rsv {
			rsv[i] = 0
		}
		/*
		  Re-initialise the rsv pointers
		  this saves us from using a slow sort comparator
		*/
		for i := len(rsvPointers) - 1; i >= 0; i-- {
			rsvPointers[i] = i
		}
		var queryId int = 0
		for i, token := range strings.Fields(stdin.Text()) {
			/*
			  If the first token is a number then assume a TREC query number, and skip it
			*/
			if i == 0 {
				if num, err := strconv.Atoi(token); err == nil {
					queryId = num
					continue
				}
			}

			/*
			  Does the term exist in the collection?
			*/
			termDetails, ok := dictionary[token]
			if !ok {
				continue
			}

			/*
			  Seek and read the postings list
			*/
			currentListAsBytes := make([]byte, termDetails.size)
			_, err := postingsFile.ReadAt(currentListAsBytes, int64(termDetails.where))
			check(err)
			currentList := make([]int32, len(currentListAsBytes)/4)
			err = binary.Read(bytes.NewReader(currentListAsBytes), binary.NativeEndian, currentList)
			check(err)
			postings := len(currentListAsBytes) / 8

			/*
			  Compute the IDF component of BM25 as log(N/n).
			  if IDF == 0 then don't process this postings list as the BM25 contribution of this term will be zero.
			*/
			if documentsInCollection == postings {
				continue
			}

			idf := math.Log(float64(documentsInCollection) / float64(postings))

			/*
			  Process the postings list by simply adding the BM25 component for this document into the accumulators array
			*/
			for i := 0; i < len(currentList); i += 2 {
				d := currentList[i]
				tf := float64(currentList[i+1])
				rsv[d] += idf * ((tf * (k1 + 1)) / (tf + k1*(1-b+b*(float64(lengthVector[d])/averageDocumentLength))))
			}
		}
		/*
		  Sort the results list
		*/
		slices.SortStableFunc(rsvPointers, func(a, b int) int {
			return cmp.Compare(rsv[b], rsv[a])
		})

		/*
		  Print the (at most) top 1000 documents in the results list in TREC eval format which is:
		  query-id Q0 document-id rank score run-name
		*/
		for i, r := range rsvPointers {
			if rsv[r] == 0 || i == 1000 {
				break
			}
			fmt.Printf("%d Q0 %s %d %.4f JASSjr\n", queryId, primaryKeys[rsvPointers[i]], i+1, rsv[r])
		}
	}
	if err := stdin.Err(); err != nil {
		panic(err)
	}
}
