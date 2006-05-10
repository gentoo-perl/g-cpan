##### ERRORS constants (easy internationalisation ;-) #####
use constant ERR_FILE_NOTFOUND   => "Couldn't find file '%s'";                 # filename
use constant ERR_FOLDER_NOTFOUND => "Couldn't find folder '%s'";               # foldername
use constant ERR_OPEN_READ       => "Couldn't open (read) file '%s' : %s";     # filename, $!
use constant ERR_OPEN_WRITE      => "Couldn't open (write) file '%s' : %s";    # filename, $!
use constant ERR_FOLDER_OPEN     => "Couldn't open folder '%s', %s";           # foldername, $!
use constant ERR_FOLDER_CREATE   => "Couldn't create folder '%s' : %s";        # foldername, $!


1;
