import std.stdio;
import std.file;
import std.exception;
import std.path;
import std.conv;
import std.string;
import std.array;
import std.algorithm;
import std.random;
import core.sys.posix.stdlib;
import std.process;
import std.container;

///The file storing the path to the current database
string databaseNamePath = "~/.bugd_database_name";

///The header of a dbug database, used to see if it is actually a dbug database
string databaseHeader = "dbug_database";

class BugdException : Exception
{
	mixin basicExceptionCtors;
}

alias enforceBugd = enforceEx!BugdException;

/**
	A structure used to store a single entry
*/
class DbEntry {
	this() {};
	this(uint nid)
	{
		id = nid;
	}
	this(string[] parts)
	{
		id = parts[0].to!uint;
		state = parts[1];
		name = parts[2];
		description = parts[3];
	}

	bool opEquals(ref const DbEntry rhs) 
	{
		return (this.id == rhs.id);
	}

	bool opEquals(ref const uint rhs)
	{
		return (this.id == rhs);
	}

	alias opCmp = Object.opCmp;
	int opCmp(ref const DbEntry rhs)
	{
		return (this.id - rhs.id);
	}


	uint id;
	string state;
	string name;
	string description;
}

alias Database = DList!DbEntry;

/**
	Searches for the entry with the given ID in the database, throws a BugdException if the entry is not found
	Return: The entry searched for
	Params:
		db = the database to look through
		id = the id to look for
*/
DbEntry findEntry(Database db,uint id)
{
	foreach(entry;db)
	{
		if (entry.id == id) return entry;
	}
	throw new BugdException("Unable to find entry: " ~ id.to!string);
}

/**
	Sets the active database in databaseNamePath
	Params:
		databasePath = what the database should be set to
*/
void setDatabase(string databasePath)
{
	databasePath = absolutePath(databasePath);
	try {
		auto databasePathFile = File(expandTilde(databaseNamePath),"w");
		databasePathFile.write(databasePath);
	} catch (ErrnoException) {
		throw new BugdException("Error: unable to open " ~ databaseNamePath);
	}
}


/**
	creates a new database and sets it as the active datbase
	Params:
		databasePath = what the database should be set to
*/
void initDatabase(string databasePath)
{

	enforceBugd(!exists(databasePath),"Error: " ~ databasePath ~ " exists, unable to create database");

	try {
		auto databaseFile = File(databasePath,"w+");
		databaseFile.writeln(databaseHeader);
	} catch(ErrnoException) {
		writeln("Error: unable open " ~ databasePath);
	}

	setDatabase(databasePath);

}


/**
	converts a description line from the database to plaintext
*/
string dbLineToPlaintext(string line)
{
	line = line.replace("\\n","\n");
	line = line.replace("\\t","\t");
	return line;
}

/**
	converts a plaintext line to a line sutible for entry to the database
*/
string plaintextToDbLine(string text)
{
	text = text.replace("\n","\\n");
	text = text.replace("\t","\\t");
	return text;
}

///
unittest {
	auto str1 = "This\\nis\\nsome\\ntext";
	auto str2 = "This\\tis\\tsome\\ttext";
	auto str3 = "More\\n\\tText";

	auto str4 = "This\nis\nsome\ntext";
	auto str5 = "This\tis\tsome\ttext";
	auto str6 = "More\n\tText";

	assert(str1.dbLineToPlaintext == str4);
	assert(str2.dbLineToPlaintext == str5);
	assert(str3.dbLineToPlaintext == str6);
	assert(str1.dbLineToPlaintext.plaintextToDbLine == str1);
	assert(str2.dbLineToPlaintext.plaintextToDbLine == str2);
	assert(str3.dbLineToPlaintext.plaintextToDbLine == str3);
}

/**
	Takes a single entry line from a database and converts it to a DbEntry object
	Returns: a DbEntry representation of the given line
	Params:
		line = the The line to parse
*/
DbEntry parseDbLine(string line)
{
	auto parts = array(splitter(line,'\t'));
	enforceBugd(parts.length = 4,"Error: Malformed line: " ~ line);

	parts[3] = parts[3].dbLineToPlaintext;
	return new DbEntry(parts);
}

/**
	Load the active database
	Returns: The active database
*/
Database loadDatabase()
{

	assert(is(typeof(binaryFun!"a < b"(DbEntry.init,DbEntry.init))));
	string databasePath;
	try {
		auto databaseNameFile = File(expandTilde(databaseNamePath),"r");
		databasePath = databaseNameFile.readln();
	} catch(ErrnoException) {
		throw new BugdException("Error: No current database");
	}

	File databaseFile;
	try {
		databaseFile = File(databasePath,"r+");
		auto firstLine = databaseFile.readln();

		//add "\n" becuaus readline add's one
		enforceBugd(firstLine == (databaseHeader~"\n"),"Error: " ~ databasePath ~ " is not a dbug database");

	} catch (ErrnoException) {
		throw new BugdException("Error: unable to open " ~ databasePath);
	}

	//auto database = appender!(DbEntry[]);
	//DbEntry[int] database;
	//DbEntry[] database = new RedBlackTree!DbEntry;
	auto database = Database();
	
	string line;
	while ((line = databaseFile.readln()) !is null) {
		DbEntry entry = line.parseDbLine;
		database.insertBack(entry);
	}

	return database;

}

/**
	creates a temporary file to pass to an external editor
	currently only works posix systems due to use of mkstemp
	Returns: A temporary file
*/
File createTmpFile()
{
	auto fnTemplate = "/tmp/bugd-XXXXXX";
	char[] nameBuf = new char[fnTemplate.length+1];
	nameBuf[0 .. fnTemplate.length] = fnTemplate[];
	nameBuf[fnTemplate.length] = '\0';
	auto fd = mkstemp(nameBuf.ptr);
	return File(nameBuf.to!string,"w+");
}

///
unittest
{
	auto file = createTmpFile();
	auto filename = file.name;
	writeln("Successfully created: " ~ filename);
	file.close();
	remove(filename);
	
}

/**
	Creates a file for editing an entry
	Return: the file created
	Params:
		id = id of the entry
		state = the state of the entry, can be empty
		name = the name of the entry, can be empty
		description = the description of the entry, can be empty
*/
string createEntryFile(int id,string state = "", string name="", string description="")
{
	auto entryFile=createTmpFile();
	entryFile.writeln("Editing entry id: " ~ id.to!string);
	entryFile.write("\n");
	entryFile.writeln("State: " ~ state);
	entryFile.writeln("Name: " ~ name);
	entryFile.writeln("### Description Below ###");
	auto fname = entryFile.name;
	entryFile.close();
	return fname;
}

/**
	Try to find a text editor and open the given file
	Currently only looks in environment variables VISUAL and EDITOR
	Params:
		filename = The file to try and open
*/
void launchEditor(string filename)
{
	string editor;
	try {
		editor = environment["VISUAL"];
	} catch(Exception) {
		try {
			editor = environment["EDITOR"];
		}
		catch(Exception) {
			throw new BugdException("Error: Unable to find an editor");
		}
	}


	writeln(filename);
	auto pid = spawnProcess([editor , filename]);
	wait(pid);
}

/**
	Loads the current database and lists out the entries
*/
void displayEntryList()
{
	auto data = loadDatabase();
	writefln("%-7s%-17s%s","Id","State","name");
	writeln("----------------------------");
	foreach (entry; data) {
		writefln("%-7d%-17s%s",entry.id,entry.state,entry.name);
	}
}


/**
	Creates a new bug entry
*/
void CreateEntry()
{
	auto database = loadDatabase();

	auto tmpName = createEntryFile(5);
	launchEditor(tmpName);
	auto tmp = new File(tmpName);
	auto buf = tmp.rawRead(new char[500]);
	write(buf);
}


/**
	Display a single entry
	Params:
		id = the entry to display
*/
void displayEntry(int id)
{
	auto database = loadDatabase();

	auto entry = database.findEntry(id);

	writeln("ID: " ~ entry.id.to!string);
	writeln("State: " ~ entry.state);
	writeln("Name: " ~ entry.name);
	writeln("Description:\n");
	write(entry.description);
}


///prints out usage information
void usage()
{
	writeln("bugd <command> [<args>]");
}

int main(string[] args)
{
	try {

		if (args.length < 2) {
			usage();
			return 0;
		}

		switch(args[1]) {
			case "init":
			{
				enforceBugd(args.length >= 3,"Error: init expects an argument");
				initDatabase(args[2]);
				break;
			}
			case "set":
			{
				enforceBugd(args.length >= 3,"Error: set expects an argument");
				setDatabase(args[2]);
				loadDatabase(); //see if we can load it
				break;
			}
			case "list":
			{
				displayEntryList();
			} break;
			case "view":
			{
				enforceBugd(args.length >= 3,"Error: view expects an argument");
				displayEntry(args[2].to!int);
				break;
			}
			case "new":
			{
				CreateEntry();
				break;
			}
			case "help":
			default:
			{
				usage();
			}
		}

	} catch (BugdException e) {
		writeln(e.msg);
		return 1;
	}
	return 0;
}
