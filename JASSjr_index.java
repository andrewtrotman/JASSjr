/*
  JASSjr_index.java
  ----------------
  Copyright (c) 2019 Andrew Trotman and Kat Lilly
  Minimalistic BM25 search engine.
*/
import java.lang.Thread;
import java.util.HashMap;
import java.nio.IntBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.nio.ByteBuffer;
import java.io.IOException;
import java.util.stream.Stream;
import java.io.FileOutputStream;
import java.io.DataOutputStream;

/*
  CLASS JASSJR_INDEX
  ------------------
*/
class JASSjr_index
{
    /*
      CLASS POSTING
      -------------
    */
    public class Posting 
    {
        public int d, tf;
	
	Posting(int d, int tf)
	{
	    this.d = d;
	    this.tf = tf;
	}
    }

    public class PostingsList extends ArrayList<Posting> {} 

    String buffer;
    int current;
    String nextToken;
    HashMap<String, PostingsList> vocab = new HashMap<String, PostingsList>();
    ArrayList<String> docIds = new ArrayList<String>();
    ArrayList<Integer> lengthVector = new ArrayList<Integer>();

    /* 
       toLittleEndian()
       ----------------
       Rearrange byte order so index matches that of CPP indexer
    */
    public int toLittleEndian(int value)
    {
	return ((value & 0xFF) << 24) | (((value >>> 8) & 0xFF) << 16) | (((value >>> 16) & 0xFF) << 8) | (((value >>> 14) & 0xFF) << 0);
    }
    
    /*
      lexGetNext()
      ------------
      One-character lookahead lexical analyser
    */
    public String lexGetNext()
    {
	/*
	  Skip over whitespace and punctuation (but not XML tags)
	*/	
	while (current < buffer.length() && !Character.isLetterOrDigit(buffer.charAt(current)) && buffer.charAt(current) != '<')
	    current++;

	/*
	  A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
	*/
	int start = current;
	if (current >= buffer.length())
	    return null;     // must be at end of line
	else if (Character.isLetterOrDigit(buffer.charAt(current)))
	    while (current < buffer.length() && (Character.isLetterOrDigit(buffer.charAt(current)) || buffer.charAt(current) == '-'))				// TREC <DOCNO> primary keys have a hyphen in them
		current++;
	else if (buffer.charAt(current) == '<')
	    for (current++; current < buffer.length() && buffer.charAt(current - 1) != '>'; current++)
		{ /* do nothing */ }
	/*
	  Copy and return the token
	*/		
	return buffer.substring(start, current);
    }
    
    /*
      lexGetFirst()
      -------------
      Start the lexical analysis process
    */
    public String lexGetFirst(String with)
    {
	buffer = with;
	current = 0;
	
	return lexGetNext();
    }

    /*
      engage()
      --------
      Simple indexer for TREC WSJ collection
    */
    public void engage(String args[]) 
    {
	int docId = -1;
	int documentLength = 0;

	/*
	  Make sure we have one paramter, the filename
	*/
	if (args.length != 1)
	    {
		System.out.println("Usage: java " + Thread.currentThread().getStackTrace()[1].getClassName() + " <infile.xml>");
		System.exit(0);
	    }
	
	try (Stream<String> stream = Files.lines(Paths.get(args[0])))
	    {
		Boolean pushNext = false;
		for (String line : (Iterable<String>) stream::iterator)
		    {
			String token;
			for (token = lexGetFirst(line); token != null; token = lexGetNext())
			    {
				if (token.equals("<DOC>"))
				    {
					/*
					  Save the previous document length
					*/
					if (docId != -1)
					    lengthVector.add(documentLength);
			
					/*
					  Move on to the next document
					*/
					docId++;
					documentLength = 0;
			
					if ((docId % 1000) == 0)
					    System.out.println(docId + " documents indexed");
				    }

				/*
				  if the last token we saw was a <DOCID> then the next token is the primary key
				*/
				if (pushNext)
				    {
					docIds.add(token);
					pushNext = false;
				    }
				if (token.equals("<DOCNO>"))
				    pushNext = true;
		    
				/*
				  Don't index XML tags
				*/
				if (token.charAt(0) == '<')
				    continue;

				/*
				  lower case the string
				*/
				token.toLowerCase();

				/*
				  truncate any long tokens at 255 charactes (so that the length can be stored first and in a single byte)
				*/
				if (token.length() > 0xFF)
				    token = token.substring(0, 0xFF);

				/*
				  add the posting to the in-memory index
				*/
				PostingsList list = vocab.get(token);
				if (list == null)
				    {
					PostingsList newList = new PostingsList();
					newList.add(new Posting(docId, 1));
					vocab.put(token, newList);     // if the term isn't in the vocab yet 
				    }
				else if (list.get(list.size() - 1).d != docId)
				    list.add(new Posting(docId, 1));							// if the docno for this occurence hasn't changed the increase tf
				else
				    list.get(list.size() - 1).tf++;												// else create a new <d,tf> pair.
		    
				/*
				  Compute the document length
				*/
				documentLength++;
			    }
		    }
	    }
	catch (IOException e)
	    {
		e.printStackTrace();
	    }
	
	/*
	  tell the user we've got to the end of parsing
	*/
	System.out.println("Indexed " + (docId + 1) + " documents. Serialising...");
	
	/*
	  Save the final document length
	*/
	lengthVector.add(documentLength);

	try
	    {
		/*
		  store the primary keys
		*/
		int times = 0;
		DataOutputStream docIdFile = new DataOutputStream(new FileOutputStream("docids.bin"));
		for (String primaryKey :  docIds)
		    {
			primaryKey += "\n";
			docIdFile.write(primaryKey.getBytes(), 0, primaryKey.length());
			times++;
		    }

		/*
		  serialise the in-memory index to disk
		*/    
		FileOutputStream postingsFile = new FileOutputStream("postings.bin");
		DataOutputStream postingsStream = new DataOutputStream(postingsFile);
		DataOutputStream vocabFile = new DataOutputStream(new FileOutputStream("vocab.bin"));

		int[] linear = new int [docId * 2];
		ByteBuffer byteBuffer = ByteBuffer.allocate(docId * 8);
		byteBuffer.order(ByteOrder.nativeOrder());
		IntBuffer intBuffer = byteBuffer.asIntBuffer();
	    
		for (HashMap.Entry<String, PostingsList> entry : vocab.entrySet())
		    {
			/*
			  write the postings list to one file
			*/
			int where = (int)postingsFile.getChannel().position();
	    
			for (int which = 0; which < entry.getValue().size(); which++)
			    {
				linear[which * 2] = entry.getValue().get(which).d;
				linear[which * 2 + 1] = entry.getValue().get(which).tf;
			    }
       
			intBuffer.rewind();
			intBuffer.put(linear, 0, entry.getValue().size() * 2);
			postingsStream.write(byteBuffer.array(), 0, entry.getValue().size() * 8);
	    
			/*
			  write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
			*/
			vocabFile.write((byte) entry.getKey().length());
			vocabFile.write(entry.getKey().getBytes(), 0, (byte) entry.getKey().length());
			vocabFile.write('\0');
			vocabFile.writeInt(toLittleEndian(where));
			vocabFile.writeInt(toLittleEndian((int) postingsFile.getChannel().position() - where));
		    }

		/*
		  store the document lengths
		*/
		DataOutputStream docLengthsFile = new DataOutputStream(new FileOutputStream("lengths.bin"));
		for (int i= 0; i < lengthVector.size(); i++)
		    linear[i] = lengthVector.get(i);
		
		intBuffer.rewind();
		intBuffer.put(linear, 0, lengthVector.size());
		docLengthsFile.write(byteBuffer.array(), 0, lengthVector.size() * 4);
		   
		/*
		  clean up
		*/
		docIdFile.close();
		postingsStream.close();
		vocabFile.close();
		docLengthsFile.close();
	    }
	catch (Exception e)
	    {
		e.printStackTrace();
	    }
    }

    /*
      main()
      ------
    */
    public static void main(String args[]) 
    {
	JASSjr_index indexer = new JASSjr_index();
	indexer.engage(args);
    } 
} 
