#!/bin/bash

cat .github-pages-ignore > _site/.gitignore
bundle exec gh-pages-travis
