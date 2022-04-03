#!/bin/sh

docker run --rm -e TZ=America/Los_Angeles -v /home/sean/Documents/blogs/technology-blog:/blogs --user 1000:1000 -p 1315:1313 hugo-alpine:1.0 $1 --bind 0.0.0.0
