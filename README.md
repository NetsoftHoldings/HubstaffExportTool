# Hubstaff Export Tool

This is an export tool for hubstaff screenshots. It also gives a hint of how you can write a ruby class to make requests
to the hubstaff public API.

### Synopsis
  - This is a simple hubstaff.com export tool for the screenshots.
  - It uses the Hubstaff API.

### Examples
  Commands to call

    ruby hubstaff-export.rb authentication -t apptoken -e user@email.com -p password
    ruby hubstaff-export.rb export-screens -s 2015-07-01T00:00:00Z -f 2015-07-01T07:00:00Z -o 84 -i both

### Usage
    ruby hubstaff-export.rb [action] [options]

    For help use: ruby hubstaff-export.rb -h

### Options
    -h, --help          Displays help message
    -v, --version       Display the version, then exit
    -V, --verbose       Verbose output
    -t, --apptoken      The application token in hubstaff
    -p, --password      The password to authenticate account
    -e, --email         The email used for authentication
    -s, --start_time    Start date to pick the screens
    -f, --stop_time     End date to pick screens
    -j, --projects      Comma separated list of project IDs
    -u, --users         Comma separated list of user IDs
    -i, --image         What image to export (full || thumb || both)
    -o, --organizations Comma separated list of organization IDs
    -d, --directory     A path to the output directory (otherwise ./screens is assumed)

### Author
  Chocksy - @Hubstaff