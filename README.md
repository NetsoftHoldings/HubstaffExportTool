# Hubstaff Export Tool

This is an export tool for hubstaff screenshots. It also gives a hint of how you can write a ruby class to make requests
to the hubstaff public API.

### Synopsis
  - This is a simple hubstaff.com export tool for the screenshots.
  - It uses the Hubstaff API.

### Examples
Commands to call

    ruby hubstaff-export.rb token PersonalAccessRefreshToken
    ruby hubstaff-export.rb export-screens 2015-07-01T00:00:00Z 2015-07-01T07:00:00Z -o 84 -i both

### Obtaining a personal access token

Go to the [Hubstaff developer site](https://developer.hubstaff.com/personal_access_tokens) to create a personal access token with the Ability to read hubstaff data scope.  

### Usage
    ruby hubstaff-export.rb [action] [options]

    For help use: ruby hubstaff-export.rb -h

### Options
    -h, --help          Displays help message
    -v, --version       Display the version, then exit
    -V, --verbose       Verbose output
    -j, --projects      Comma separated list of project IDs
    -u, --users         Comma separated list of user IDs
    -i, --image         What image to export (full || thumb || both)
    -o, --organization  The organization ID
    -d, --directory     A path to the output directory (otherwise ./screens is assumed)

### Author
  Chocksy - @Hubstaff
