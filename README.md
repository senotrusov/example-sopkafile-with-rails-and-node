## Sopkafile to deploy Rails/Node.js projects to Linux servers

![Sopka menu screenshot](docs/sopka-menu-screenshot.png)

* Deploy local developer workstation to work with Rails and Node.js projects
* Deploy new production server with the copy of the database from the developer machine
* Copy the database from production to developer machine

To keep those steps as declarative as I could possible express in Bash, I made a separate library [Sopka](https://github.com/senotrusov/sopka). Basically, this Sopkafile you are looking at is the things I want to setup and configure for that exact task (my workstation) and [Sopka](https://github.com/senotrusov/sopka) is the abstract library that makes it all possible.
