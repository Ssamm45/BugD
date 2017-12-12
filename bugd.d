import std.stdio;
import std.file;
import std.exception;
import std.path;
import std.conv;
import std.string;
import std.array;
import std.algorithm;

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
this(string[] parts)
	{
		id = parts[0].to!uint;
		state = parts[1];
		name = parts[2];
		description = parts[3];
	}
	uint id;
	string state;
	string name;
	string description;
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
	if (exists(databasePath)) {
	}

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
	line = line.replace("\n","\\n");
	line = line.replace("\t","\\t");
	return line;
}

/**
	converts a plaintext line to a line sutible for entry to the database
*/
string plaintextToDbLine(string text)
{
	text = text.replace("\\n","\n");
	text = text.replace("\\t","\t");
	return text;
}

///
unittest{
	auto str1 = "This\nis\nsome\ntext";
	auto str2 = "This\tis\tsome\t\text";
	auto str3 = "More\n\tText";


	assert(str1.dbLineToPlaintext().plaintextToDbLine() == str1);
	assert(str2.dbLineToPlaintext().plaintextToDbLine() == str2);
	assert(str3.dbLineToPlaintext().plaintextToDbLine() == str3);
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

	parts[3] =  parts[3].dbLineToPlaintext;
	return new DbEntry(parts);
}

/**
	Load the active database
	Returns: The active database
*/
DbEntry[] loadDatabase()
{
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

	auto database = appender!(DbEntry[]);
	string line;
	while ((line = databaseFile.readln()) !is null) {
		database.put(line.parseDbLine);
	}

	return database.data;

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
				loadDatabase();//see if we can load it
				break;
			}
			case "list":
			{
				displayEntryList();
			} break;
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
