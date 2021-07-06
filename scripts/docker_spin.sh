#!/bin/sh

docker run --rm -e TZ=America/Los_Angeles --net=host -v /home/sean/Documents/blogs/technology-blog:/blogs --user 1000:1000 hugo-alpine:1.0 $1
