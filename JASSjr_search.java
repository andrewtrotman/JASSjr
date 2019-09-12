/*
	JASSjr_search.java
	-----------------
	Copyright (c) 2019 Andrew Trotman and Kat Lilly
	Minimalistic BM25 search engine.
*/
import java.io.File;
import java.util.List;
import java.util.HashMap;
import java.util.Scanner;
import java.nio.IntBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.nio.ByteBuffer;
import java.io.FileInputStream;
import java.util.StringTokenizer;

class JASSjr_search
    {
	/*
	  Constants
	  ---------
	*/
	final double k1 = 0.9;      // BM25 k1 parameter
	final double b = 0.4;	      // BM25 b parameter

	/*
	  Class VocabEntry
	  ----------------
	*/
	class VocabEntry
	{
	    int where, size;		// where on the disk and how large (in bytes) is the postings list?

	    VocabEntry(int where, int size)
	    {
		this.where = where;
		this.size = size;
	    }
	}

	/*
	  readEntireFile()
	  ----------------
	  Read the entire contents of the given file into memory and return its size.
	*/
	ByteBuffer readEntireFile(String filename) throws Exception
	{
	    File file = new File(filename);
	    FileInputStream stream = new FileInputStream(file);
	    ByteBuffer bytes = ByteBuffer.allocate((int)file.length());
	    if (stream.read(bytes.array()) == -1)
		return null;
	    else
		return bytes;
	}

	/*
	  Engage()
	  --------
	  Simple search engine ranking on BM25.
	*/
	public void engage(String args[]) throws Exception
	{
	    /*
	      Read the document lengths
	    */
	    ByteBuffer lengthsAsBytes = readEntireFile("lengths.bin");
            lengthsAsBytes.order(ByteOrder.nativeOrder());
	    IntBuffer lengthsAsIntegers = lengthsAsBytes.asIntBuffer();
	    int[] lengthVector = new int [lengthsAsBytes.capacity() / 4];
	    lengthsAsIntegers.get(lengthVector);

	    /*
	      Compute the average document length for BM25
	    */
    	    double documentsInCollection = lengthVector.length;
	    double averageDocumentLength = 0;
	    for (int which : lengthVector)
		averageDocumentLength += which;
	    averageDocumentLength /= documentsInCollection;

	    /*
	      Read the primary_keys
	    */
	    List<String> primaryKey = Files.readAllLines(Paths.get("docids.bin"));

	    /*
	      Build the vocabulary in memory
	    */
	    HashMap<String, VocabEntry>dictionary = new HashMap<String, VocabEntry>(); // the vocab
	    ByteBuffer vocabAsBytes = readEntireFile("vocab.bin");
	    vocabAsBytes.order(ByteOrder.nativeOrder());

	    while (vocabAsBytes.position() < vocabAsBytes.capacity())
		{
		    byte stringLength = vocabAsBytes.get();
		    byte[] termAsBytes = new byte[stringLength];
		    vocabAsBytes.get(termAsBytes);
		    String term = new String(termAsBytes);
		    byte zero = vocabAsBytes.get();      // read the '\0' string terminator

		    int where = vocabAsBytes.getInt();
		    int size = vocabAsBytes.getInt();

		    dictionary.put(term, new VocabEntry(where, size));
		}
/*
        Search (one query per line)
*/
        Scanner stdin = new Scanner(System.in);
        while (stdin.hasNextLine())
	    {
		StringTokenizer tokenizer = new StringTokenizer(stdin.nextLine());
		while (tokenizer.hasMoreTokens())
		    {
			String token = tokenizer.nextToken();
			System.out.println(token);
		    }
				    
	    }


	    
//	    for (HashMap.Entry<String, VocabEntry> name : dictionary.entrySet())
//		System.out.println("[" + name.getKey() + "]-> w:" + name.getValue().where + " s:" + name.getValue().size);

		
	}
	
	/*
	  Main()
	  ------
	*/
	public static void main(String args[])
	{
	    try
		{
		    JASSjr_search engine = new JASSjr_search();
		    engine.engage(args);
		}
	    catch (Exception e)
		{
		    e.printStackTrace();
		}
	}
}
