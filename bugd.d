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
string databaseHeader = "bugd_database";

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
	foreach (entry;db) {
		if (entry.id == id) return entry;
	}
	throw new BugdException("Unable to find entry: " ~ id.to!string);
}


/**
	Finds the maximum id in the given database
	Return: the max id
	Params:
		db = the database to look through
*/
uint maxId(Database db)
{
	if (db.empty()) return 0;
	auto iterator = db.opSlice;

	uint max = iterator.front.id;
	iterator.popFront();

	foreach (element; iterator) {
		if (max < element.id) max = element.id;
	}
	return max;

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
	Creates a database entry line from a DbEntry object
	Returns: a database line
	Params:
		entry = the entry to use
*/
string genDbLine(DbEntry entry)
{
	return format!("%s\t%s\t%s\t%s")(entry.id,entry.state,entry.name,entry.description.plaintextToDbLine);
}

unittest
{
	auto db1 = new DbEntry(["9","state","name","desc"]);
	auto line1 = genDbLine(db1);

	auto db2 = new DbEntry(["144","more complicated state","more complicated name","desc\nwith tabs\n\tand newlines"]);
	auto line2 = genDbLine(db2);

	assert(line1 == "9\tstate\tname\tdesc");
	assert(line2 == "144\tmore complicated state\tmore complicated name\tdesc\\nwith tabs\\n\\tand newlines");
}


/**
	opens the current db file with the given mode
	Returns: the database file
	Params:
		mode = the mode to open the file with
*/
File openDbFile(string mode)
{
	string databasePath;
	try {
		auto databaseNameFile = File(expandTilde(databaseNamePath),"r");
		scope(exit) databaseNameFile.close();
		databasePath = databaseNameFile.readln();
	} catch(ErrnoException) {
		throw new BugdException("Error: No current database");
	}

	File databaseFile;
	try {
		databaseFile = File(databasePath,mode);
		auto firstLine = databaseFile.readln();

		//add "\n" becuaus readline add's one
		enforceBugd(firstLine == (databaseHeader~"\n"),"Error: " ~ databasePath ~ " is not a dbug database");

	} catch (ErrnoException) {
		throw new BugdException("Error: unable to open " ~ databasePath);
	}
	return databaseFile;
}

/**
	Writes a db entry to the end of the db file
	Params:
		entry = the entry to write
*/
void appendToDb(DbEntry entry)
{
	auto dbfile = openDbFile("a+");
	scope(exit) dbfile.close();

	dbfile.writeln(genDbLine(entry));
}

/**
	Updates an entry in the database
	Params:
		entry = what to update the entry with
		id = which entry to update
*/
void updateDbEntry(DbEntry entry,uint id)
{
	auto database = openDbFile("r");
	scope (exit) database.close();
	auto buf = DList!string();

	while (!database.eof()) {
		auto line = database.readln();

		if (line.startsWith(id.to!string)) {
			buf.insertBack(genDbLine(entry));
		} else {
			buf.insertBack(line);
		}
	}

	auto dbname = database.name;
	database.close();

	try {
		database = File(dbname,"w");
	} catch (ErrnoException) {
		throw new BugdException("Error: unable to open " ~ dbname);
	}

	database.writeln(databaseHeader);
	foreach (line;buf) {
		database.write(line);
	}
}

/**
	Load the active database
	Returns: The active database
*/
Database loadDatabase()
{
	auto databaseFile = openDbFile("r");
	scope(exit) databaseFile.close();

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
	auto file = createTmpFile();//throws exception on failure
	auto filename = file.name;

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
	entryFile.writeln("-------------------------");
	entryFile.writeln("State: " ~ state);
	entryFile.writeln("Name: " ~ name);
	entryFile.writeln("--- Description Below ---");
	auto fname = entryFile.name;
	entryFile.close();
	return fname;
}


/**
	Parses an entry file after it has been filled out
	Return: the DbEntry parsed from the file
	Params:
		filename = the file to parse
*/
DbEntry parseEntryFile(string filename)
{
	auto file = new File(filename);

	file.readln();//Skip the id and blank line the user can't set the id throught the editor
	file.readln();

	auto stateln = file.readln();
	enforceBugd(stateln.startsWith("State:"),"Error: state line is malformed");
	auto state = strip(stateln[count("State:") .. $]);

	auto nameln = file.readln();
	enforceBugd(nameln.startsWith("Name: "),"Error: name line is malformed");
	auto name = strip(nameln[count("Name: ") .. $]);

	file.readln();//skip the Description line

	string desc;
	while (!file.eof) {
		desc ~= file.readln();
	}
	desc = strip(desc);
	desc = desc;

	return new DbEntry(["0",state,name,desc]);
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
void createEntry()
{
	auto database = loadDatabase();

	auto newId = database.maxId() + 1;
	auto tmpName = createEntryFile(newId);
	launchEditor(tmpName);

	auto entry = parseEntryFile(tmpName);
	remove(tmpName);
	entry.id = newId;

	appendToDb(entry);
}

/**
	edits an entry and saves it back to the database
	Params:
		id = the entry to edit
*/
void editEntry(uint id)
{
	auto database = loadDatabase();
	auto entry = database.findEntry(id);

	string tmpName = createEntryFile(entry.id,entry.state,entry.name,entry.description);
	launchEditor(tmpName);
	entry = parseEntryFile(tmpName);
	entry.id = id;
	remove(tmpName);

	updateDbEntry(entry,id);
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
	writeln("Description:");
	writeln("-----------------");
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
			case "new":
			{
				createEntry();
				break;
			}
			case "view":
			{
				enforceBugd(args.length >= 3,"Error: view expects an argument");
				displayEntry(args[2].to!int);
				break;
			}
			case "edit":
			{
				enforceBugd(args.length >= 3,"Error: edit exepects an argument");
				editEntry(args[2].to!int);
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
