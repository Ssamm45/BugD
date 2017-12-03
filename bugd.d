import std.stdio;
import std.file;
import std.exception;
import std.path;
import std.conv;

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
	Load the active database
	Returns: The active database
*/
File loadDatabase()
{
	string databasePath;
	try {
		auto databaseNameFile = File(expandTilde(databaseNamePath),"r");
		databasePath = databaseNameFile.readln();
	} catch(ErrnoException) {
		throw new BugdException("Error: No current database");
	}

	try {
		auto databaseFile = File(databasePath,"r+");
		auto firstLine = databaseFile.readln();

		//add "\n" becuaus readline add's one
		enforceBugd(firstLine == (databaseHeader~"\n"),"Error: " ~ databasePath ~ " is not a dbug database");
		return databaseFile;

	} catch (ErrnoException) {
		throw new BugdException("Error: unable to open " ~ databasePath);
	}
	assert(0);//we will either return or throw an exception before we get here
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


