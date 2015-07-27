# Hubstaff Export Tool

This is an export tool for hubstaff screenshots. It also gives a hint of how you can write a ruby class to make requests
to the hubstaff public API.

### Synopsis
  - This is a simple hubstaff.com export tool for the screenshots.
  - It uses the Hubstaff API.

### Examples
    Commands to call
      ruby hubstaff-export.rb authentication abc345 bob@example.com MyAwesomePass
      ruby hubstaff-export.rb export-screens 2015-06-01T00:00Z 2015-07-01T00:00Z -o 3 -e both -d ./screens-june

### Usage
    ruby hubstaff-export.rb [action] [options]

    For help use: ruby hubstaff-export.rb -h

### Options
    -h, --help          Displays help message
    -v, --version       Display the version, then exit
    -V, --verbose       Verbose output

### Author
   Chocksy - @Hubstaff
