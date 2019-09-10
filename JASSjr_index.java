import java.util.HashMap;
import java.util.ArrayList;
import java.util.stream.Stream;
import java.nio.file.Files;
import java.io.IOException;
import java.nio.file.Paths;
import java.lang.Thread;
import java.io.FileOutputStream;
import java.io.DataOutputStream;

class JASSjr_index
{ 
    public class Posting 
    {
        public int d, tf;
	
	Posting(int d, int tf)
	{
	    this.d = d;
	    this.tf = tf;
	}
    }

    String buffer;
    int current;
    String next_token;
    
    HashMap<String, ArrayList<Posting>> vocab = new HashMap<String, ArrayList<Posting>>();
    ArrayList<String> doc_ids = new ArrayList<String>() ;
    ArrayList<Integer> length_vector = new ArrayList<Integer>();


    public int to_little(int value)
    {
	return ((value & 0xFF) << 24) | (((value >>> 8) & 0xFF) << 16) | (((value >>> 16) & 0xFF) << 8) | (((value >>> 14) & 0xFF) << 0);
    }
    
    /*
      LEX_GET_NEXT()
      --------------
      One-character lookahead lexical analyser
    */
    public String lex_get_next()
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
	    return null;      // must be at end of line
	else if (Character.isLetterOrDigit(buffer.charAt(current)))
	    while (current < buffer.length() && (Character.isLetterOrDigit(buffer.charAt(current)) || buffer.charAt(current) == '-'))				// TREC <DOCNO> primary keys have a hyphen in them
		current++;
	else if (buffer.charAt(current) == '<')
	    {
		current++;
		while (current < buffer.length() && buffer.charAt(current - 1) != '>')
		    current++;
	    }

	/*
	  Copy and return the token
	*/		
	return buffer.substring(start, current);
    }
    
    /*
      LEX_GET_FIRST()
      ---------------
      Start the lexical analysis process
    */
    public String lex_get_first(String with)
    {
	buffer = with;
	current = 0;

	return lex_get_next();
    }


    public void go(String args[]) 
    {
	int docid = -1;
	int document_length = 0;

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
		for (String line : (Iterable<String>) stream::iterator)
		    {
			String token;
			Boolean push_next = false;
			for (token = lex_get_first(line); token != null; token = lex_get_next())
			    {
				//				System.out.println(token);
			    
				if (token.equals("<DOC>"))
				    {
					/*
					  Save the previous document length
					*/
					if (docid != -1)
					    length_vector.add(document_length);

					/*
					  Move on to the next document
					*/
					docid++;
					document_length = 0;

					if ((docid % 1) == 0)
					    System.out.println(docid + " documents indexed");
				    }

				/*
				  if the last token we saw was a <DOCID> then the next token is the primary key
				*/
				if (push_next)
				    {
					doc_ids.add(token);
					push_next = false;
				    }
			    
				if (token.equals("<DOCNO>"))
				    push_next = true;

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
				  truncate and long tokens at 255 charactes (so that the length can be stored first and in a single byte)
				*/
				if (token.length() > 0xFF)
				    token = token.substring(0, 0xFF);

				/*
				  add the posting to the in-memory index
				*/
				ArrayList<Posting> list = vocab.get(token);
			 	if (list == null)
				    {
					ArrayList<Posting> new_list = new ArrayList<Posting>();
					new_list.add(new Posting(docid, 1));
					vocab.put(token, new_list);     // if the term isn't in the vocab yet 
				    }
				else
				    {
					if (list.get(list.size() - 1).d != docid)
					    list.add(new Posting(docid, 1));							// if the docno for this occurence hasn't changed the increase tf
					else
					    list.get(list.size() - 1).tf++;												// else create a new <d,tf> pair.
				    }

				/*
				  Compute the document length
				*/
				document_length++;
			    }
			    
		    }
	    }
	catch (IOException e)
	    {
		e.printStackTrace();
	    }


	try
	    {
		FileOutputStream baos = new FileOutputStream("a.out");
		DataOutputStream oos = new DataOutputStream(baos);

		for (HashMap.Entry<String, ArrayList<Posting>> entry : vocab.entrySet())
		    {
	      
			String term = entry.getKey();
			ArrayList<Posting> list = entry.getValue();

			System.out.print(baos.getChannel().position() + "::" + term + ":");
	  
			for (Posting pair : list)
			    {
				oos.writeInt(to_little(pair.d));
				oos.writeInt(to_little(pair.tf));
				System.out.print("<" + pair.d + "," + pair.tf + ">");
			    }
 

			System.out.print(" ->" + baos.getChannel().position());
			System.out.println();

	  
		    }
		//		oos.close();
	    }
	catch (Exception e)
	    {
		System.out.println(e);
		e.printStackTrace();

	    }
    }
		  
  
    
    public static void main(String args[]) 
    {
	JASSjr_index indexer = new JASSjr_index();
	indexer.go(args);
    } 
} 

